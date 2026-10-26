#include "chrome/browser/ui/crest/crest_engine_tab_groups.h"

#include <algorithm>
#include <utility>
#include <vector>

#include "base/auto_reset.h"
#include "base/strings/utf_string_conversions.h"
#include "base/token.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_browsers.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "chrome/browser/ui/tabs/tab_group_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/tab_groups/tab_group_color.h"
#include "components/tabs/public/tab_group.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/range/range.h"

namespace crest {

namespace {

// The engine contract lists the group colors in Chromium's own order.
static_assert(static_cast<int>(engine::TabGroupColor::kGrey) == static_cast<int>(tab_groups::TabGroupColorId::kGrey));
static_assert(static_cast<int>(engine::TabGroupColor::kOrange) ==
              static_cast<int>(tab_groups::TabGroupColorId::kOrange));
static_assert(static_cast<int>(tab_groups::TabGroupColorId::kNumEntries) == 9);

// A group's token as the core spells it, high half first.
engine::Guid GroupGuid(const tab_groups::TabGroupId& group) {
  const base::Token& token = group.token();
  engine::Guid guid{};
  for (size_t index = 0; index < 8; ++index) {
    guid[index] = static_cast<uint8_t>(token.high() >> (56 - 8 * index));
    guid[index + 8] = static_cast<uint8_t>(token.low() >> (56 - 8 * index));
  }
  return guid;
}

tab_groups::TabGroupId GroupFor(const engine::Guid& guid) {
  uint64_t high = 0;
  uint64_t low = 0;
  for (size_t index = 0; index < 8; ++index) {
    high = high << 8 | guid[index];
    low = low << 8 | guid[index + 8];
  }
  return tab_groups::TabGroupId::FromRawToken(base::Token(high, low));
}

// The indices of `group`'s tabs in `strip`, which holds it and is not in the
// middle of changing.
std::vector<int> GroupIndices(const TabStripModel& strip, const tab_groups::TabGroupId& group) {
  std::vector<int> indices;
  const gfx::Range tabs = strip.group_model()->GetTabGroup(group)->ListTabs();
  for (uint32_t index = tabs.start(); index < tabs.end(); ++index) {
    indices.push_back(static_cast<int>(index));
  }
  return indices;
}

}  // namespace

EngineTabGroups::EngineTabGroups(EngineBinding& binding) : binding_(binding) {}

EngineTabGroups::~EngineTabGroups() = default;

// What the engine changed.

void EngineTabGroups::GroupedStateChanged(Browser* browser,
                                          const std::optional<tab_groups::TabGroupId>& old_group,
                                          const std::optional<tab_groups::TabGroupId>& new_group,
                                          tabs::TabInterface* tab) {
  // The strip lets go of a tab it removes before it says which group the
  // tab left, so a tab still in the strip was taken out of its group.
  if (old_group && browser->tab_strip_model()->GetIndexOfTab(tab) != TabStripModel::kNoTab) {
    Changed(browser, *old_group);
  }
  if (new_group) {
    Changed(browser, *new_group);
  }
}

void EngineTabGroups::GroupChanged(Browser* browser, const TabGroupChange& change) {
  if (change.type == TabGroupChange::kCreated || change.type == TabGroupChange::kVisualsChanged) {
    Changed(browser, change.group);
  }
}

void EngineTabGroups::Changed(Browser* browser, const tab_groups::TabGroupId& group) {
  if (applying_ || binding_->disposing()) {
    return;
  }
  TabStripModel* strip = browser->tab_strip_model();
  const std::string window = binding_->Browsers().WindowOf(browser);
  if (window.empty() || !strip->SupportsTabGroups() || !strip->group_model()->ContainsTabGroup(group)) {
    return;
  }
  due_.insert_or_assign(group, DueGroup{window, *strip->group_model()->GetTabGroup(group)->visual_data()});
  binding_->ReportTabGroupsSoon();
}

void EngineTabGroups::ReportDue() {
  std::map<tab_groups::TabGroupId, DueGroup> due = std::move(due_);
  due_.clear();
  for (const auto& [group, last] : due) {
    engine::PageGroupChanged report{.group_id = GroupGuid(group)};
    Browser* browser = binding_->Browsers().HoldingGroup(group);
    const tab_groups::TabGroupVisualData* visuals = &last.visuals;
    if (browser) {
      const TabStripModel& strip = *browser->tab_strip_model();
      visuals = strip.group_model()->GetTabGroup(group)->visual_data();
      for (int index : GroupIndices(strip, group)) {
        if (EnginePage* page = binding_->PageFor(strip.GetWebContentsAt(index))) {
          report.page_ids.push_back(page->id());
        }
      }
      // A group of none of Crest's pages is no folder's.
      if (report.page_ids.empty()) {
        continue;
      }
    }
    // A group no strip holds any more was closed by its last tab leaving it,
    // in the window that held it.
    const std::optional<engine::Guid> window = ParseGuid(browser ? binding_->Browsers().WindowOf(browser) : last.window);
    if (!window) {
      continue;
    }
    report.window_id = *window;
    report.title = base::UTF16ToUTF8(visuals->title());
    report.color = static_cast<engine::TabGroupColor>(visuals->color());
    report.is_collapsed = visuals->is_collapsed();
    binding_->Report(std::move(report));
  }
}

// What the core asks.

// The group holds the pages the core names that the Browser of the first of
// them holds, since a group lives in one window's strip. A group in another
// Browser gives its tabs up there first, so a window that took over the
// pages takes over their group.
void EngineTabGroups::Apply(const engine::GroupPages& command) {
  base::AutoReset<bool> applying(&applying_, true);
  const tab_groups::TabGroupId group = GroupFor(command.group_id);
  EngineBrowsers& browsers = binding_->Browsers();
  Browser* target = nullptr;
  std::vector<content::WebContents*> asked;
  for (const engine::Guid& id : command.page_ids) {
    EnginePage* page = binding_->Find(GuidText(id));
    content::WebContents* contents = page ? page->web_contents() : nullptr;
    Browser* holder = contents ? browsers.Holding(contents) : nullptr;
    if (!holder || !holder->tab_strip_model()->SupportsTabGroups() || (target && holder != target)) {
      continue;
    }
    target = holder;
    asked.push_back(contents);
  }
  if (Browser* current = browsers.HoldingGroup(group); current && current != target) {
    Dissolve(current, group);
  }
  if (!target) {
    return;
  }
  TabStripModel& strip = *target->tab_strip_model();
  if (strip.group_model()->ContainsTabGroup(group)) {
    std::vector<int> leaving;
    for (int index : GroupIndices(strip, group)) {
      if (std::ranges::find(asked, strip.GetWebContentsAt(index)) == asked.end()) {
        leaving.push_back(index);
      }
    }
    if (!leaving.empty()) {
      strip.RemoveFromGroup(leaving);
    }
  }
  std::vector<int> joining;
  for (content::WebContents* contents : asked) {
    const int index = strip.GetIndexOfWebContents(contents);
    if (index != TabStripModel::kNoTab && strip.GetTabGroupForTab(index) != group) {
      joining.push_back(index);
    }
  }
  std::sort(joining.begin(), joining.end());
  if (!joining.empty()) {
    // Makes the group again under the same token when the strip has none.
    strip.AddToGroupForRestore(joining, group);
  }
  if (!strip.group_model()->ContainsTabGroup(group)) {
    return;
  }
  const tab_groups::TabGroupVisualData visuals(base::UTF8ToUTF16(command.title),
                                               static_cast<tab_groups::TabGroupColorId>(command.color),
                                               command.is_collapsed);
  if (*strip.group_model()->GetTabGroup(group)->visual_data() != visuals) {
    strip.ChangeTabGroupVisuals(group, visuals);
  }
}

void EngineTabGroups::Dissolve(Browser* browser, const tab_groups::TabGroupId& group) {
  TabStripModel& strip = *browser->tab_strip_model();
  if (strip.group_model()->ContainsTabGroup(group)) {
    strip.RemoveFromGroup(GroupIndices(strip, group));
  }
}

}  // namespace crest
