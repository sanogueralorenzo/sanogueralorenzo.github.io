#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_TAB_GROUPS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_TAB_GROUPS_H_

#include <map>
#include <optional>
#include <string>

#include "base/memory/raw_ref.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "components/tab_groups/tab_group_id.h"
#include "components/tab_groups/tab_group_visual_data.h"

class Browser;
struct TabGroupChange;

namespace tabs {
class TabInterface;
}

namespace crest {

class EngineBinding;

// The tab groups in the tab strips of the Browsers the binding keeps, which
// extensions make with `chrome.tabs.group` and `chrome.tabGroups`, and which
// Crest shows as folders. What an extension changes is reported to the core
// once the turn ends, as each changed group then stands. What the core asks
// for with GroupPages is applied here and never reported back. A tab that
// leaves a group because it leaves its tab strip, as its page closes, is put
// away or moves to another window, changes no folder and is not reported
// either. A group's identity is its token, which the core spells as a GUID,
// so a group made again keeps the identity an extension knew.
class EngineTabGroups final {
 public:
  explicit EngineTabGroups(EngineBinding& binding);
  EngineTabGroups(const EngineTabGroups&) = delete;
  EngineTabGroups& operator=(const EngineTabGroups&) = delete;
  ~EngineTabGroups();

  // What the tab strip of a Browser the binding keeps reports: `tab` left
  // `old_group` or joined `new_group`, or a group changed.
  void GroupedStateChanged(Browser* browser,
                           const std::optional<tab_groups::TabGroupId>& old_group,
                           const std::optional<tab_groups::TabGroupId>& new_group,
                           tabs::TabInterface* tab);
  void GroupChanged(Browser* browser, const TabGroupChange& change);

  // Makes the group hold what the core asked for.
  void Apply(const engine::GroupPages& command);

  // Whether a group changed since it was last reported.
  bool HasDue() const { return !due_.empty(); }
  // Reports each group that changed, as it stands now.
  void ReportDue();
  void Clear() { due_.clear(); }

 private:
  // Where a changed group was when it last changed, so a group the extension
  // closed is still reported in the window that held it.
  struct DueGroup {
    std::string window;
    tab_groups::TabGroupVisualData visuals;
  };

  void Changed(Browser* browser, const tab_groups::TabGroupId& group);
  // Takes every tab of `browser` out of `group`, which closes it there.
  void Dissolve(Browser* browser, const tab_groups::TabGroupId& group);

  const raw_ref<EngineBinding> binding_;
  std::map<tab_groups::TabGroupId, DueGroup> due_;
  // A GroupPages command is changing the tab strips.
  bool applying_ = false;
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_TAB_GROUPS_H_
