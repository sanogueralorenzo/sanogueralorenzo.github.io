#include "chrome/browser/ui/crest/crest_engine_browsers.h"

#include <algorithm>
#include <optional>
#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_manager_service.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_profiles.h"
#include "chrome/browser/ui/crest/crest_engine_tab_groups.h"
#include "chrome/browser/ui/tabs/tab_group_model.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"

namespace crest {

// A Browser the engine created for itself: the Space whose tabs it opens,
// whether the Crest window reserved for it has opened, and whether that window
// should come to the front when it does.
struct EngineBrowsers::EngineWindow {
  std::string space;
  bool presented = false;
  bool focused = true;
};

// One Browser the binding keeps, and the tab strip it watches for tabs the
// engine opens by itself.
struct EngineBrowsers::KeptBrowser final : TabStripModelObserver {
  KeptBrowser(EngineBrowsers& keeper,
              Browser* kept,
              std::string profile_id,
              std::string window_id,
              bool holds_pages,
              std::optional<EngineWindow> placed = std::nullopt,
              bool keeps = false)
      : owner(keeper),
        browser(kept),
        profile(std::move(profile_id)),
        window(std::move(window_id)),
        holds_window_pages(holds_pages),
        keeps_tabs(keeps),
        engine(std::move(placed)),
        strip(kept->tab_strip_model()) {
    strip->AddObserver(this);
  }
  ~KeptBrowser() override {
    if (strip) {
      strip->RemoveObserver(this);
    }
  }

  // TabStripModelObserver:
  void OnTabStripModelChanged(TabStripModel*,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override {
    if (change.type() != TabStripModelChange::kInserted || owner->binding_->disposing()) {
      return;
    }
    for (const auto& inserted : change.GetInsert()->contents) {
      owner->OfferSoon(inserted.contents, selection.new_contents == inserted.contents);
    }
  }
  void TabGroupedStateChanged(TabStripModel*,
                              std::optional<tab_groups::TabGroupId> old_group,
                              std::optional<tab_groups::TabGroupId> new_group,
                              tabs::TabInterface* tab,
                              int) override {
    if (!owner->binding_->disposing()) {
      owner->binding_->TabGroups().GroupedStateChanged(browser, old_group, new_group, tab);
    }
  }
  void OnTabGroupChanged(const TabGroupChange& change) override {
    if (!owner->binding_->disposing()) {
      owner->binding_->TabGroups().GroupChanged(browser, change);
    }
  }
  void OnTabStripModelDestroyed(TabStripModel*) override { strip = nullptr; }

  const raw_ref<EngineBrowsers> owner;
  const raw_ptr<Browser> browser;
  // The Crest profile and window the Browser belongs to; both are empty for
  // one no Crest window could take, whose tabs are offered and then refused.
  // An extension's popup follows its tab to whichever window shows it.
  const std::string profile;
  std::string window;
  // Whether `window`'s pages of `profile` go in this Browser. A window that
  // already had a Browser for the profile keeps it, and one the engine created
  // there later only holds its own tabs until the window adopts them.
  const bool holds_window_pages;
  // Whether this Browser's tabs stay in it wherever they show: the popup an
  // extension created, which is that extension's window even while its tab
  // shows in a window of the person's.
  const bool keeps_tabs;
  std::optional<EngineWindow> engine;
  raw_ptr<TabStripModel> strip;
};

EngineBrowsers::EngineBrowsers(EngineBinding& binding) : binding_(binding) {}

EngineBrowsers::~EngineBrowsers() = default;

// Pages.

content::WebContents* EngineBrowsers::CreateContents(Profile* profile,
                                                     const std::string& profile_id,
                                                     const std::string& window) {
  Browser* browser = ForWindow(profile_id, window);
  if (!browser) {
    return nullptr;
  }
  content::WebContents::CreateParams params(profile);
  params.initially_hidden = true;
  params.desired_renderer_state = content::WebContents::CreateParams::kNoRendererProcess;
  auto owned = content::WebContents::Create(params);
  content::WebContents* contents = owned.get();
  browser->tab_strip_model()->AddWebContents(std::move(owned), TabStripModel::kNoTab,
                                             ui::PAGE_TRANSITION_AUTO_TOPLEVEL, AddTabTypes::ADD_NONE);
  return contents;
}

bool EngineBrowsers::MoveToWindow(content::WebContents* contents,
                                  const std::string& profile_id,
                                  const std::string& window) {
  if (!contents) {
    return false;
  }
  // An extension's popup keeps its tab, so the window the extension named
  // still holds it and closes only it; the popup shows in `window` instead.
  if (KeptBrowser* popup = HoldingKept(contents); popup && popup->keeps_tabs) {
    if (popup->profile != profile_id) {
      return false;
    }
    popup->window = window;
    popup->strip->ActivateTabAt(popup->strip->GetIndexOfWebContents(contents));
    return true;
  }
  Browser* target = ForWindow(profile_id, window);
  if (!target) {
    return false;
  }
  TabStripModel* strip = target->tab_strip_model();
  if (strip->GetIndexOfWebContents(contents) == TabStripModel::kNoTab) {
    KeptBrowser* source = HoldingKept(contents);
    if (!source) {
      return false;
    }
    // Keeps its TabModel, navigation history, renderer and extension identity.
    auto tab = source->strip->DetachTabAtForInsertion(source->strip->GetIndexOfWebContents(contents));
    strip->InsertDetachedTabAt(strip->count(), std::move(tab), AddTabTypes::ADD_ACTIVE);
  }
  const int index = strip->GetIndexOfWebContents(contents);
  if (index == TabStripModel::kNoTab) {
    return false;
  }
  strip->ActivateTabAt(index);
  return true;
}

bool EngineBrowsers::Activate(content::WebContents* contents) {
  KeptBrowser* kept = HoldingKept(contents);
  if (!kept) {
    return false;
  }
  kept->strip->ActivateTabAt(kept->strip->GetIndexOfWebContents(contents));
  return true;
}

void EngineBrowsers::Destroy(content::WebContents* contents) {
  if (KeptBrowser* kept = HoldingKept(contents)) {
    kept->strip->DetachAndDeleteWebContentsAt(kept->strip->GetIndexOfWebContents(contents));
  }
}

// Browsers.

Browser* EngineBrowsers::Holding(content::WebContents* contents) const {
  KeptBrowser* kept = HoldingKept(contents);
  return kept ? kept->browser.get() : nullptr;
}

Browser* EngineBrowsers::HoldingGroup(const tab_groups::TabGroupId& group) const {
  for (const auto& kept : kept_) {
    if (kept->strip && kept->strip->group_model() && kept->strip->group_model()->ContainsTabGroup(group)) {
      return kept->browser;
    }
  }
  return nullptr;
}

Browser* EngineBrowsers::ForWindow(const std::string& profile_id, const std::string& window) {
  if (KeptBrowser* kept = WindowBrowser(profile_id, window)) {
    return kept->browser;
  }
  Profile* profile = binding_->Profiles().Find(profile_id);
  if (!profile) {
    return nullptr;
  }
  // Named before the status check as well as the creation: a window Crest
  // opens for itself is never subject to `MayCreate`.
  creating_window_ = window;
  if (GetBrowserWindowCreationStatusForProfile(*profile) != BrowserWindowInterface::CreationStatus::kOk) {
    creating_window_.clear();
    return nullptr;
  }
  // Browser is the only desktop BrowserWindowInterface.
  Browser* browser = static_cast<Browser*>(CreateBrowserWindow(BrowserWindowCreateParams(profile, false)));
  creating_window_.clear();
  kept_.push_back(std::make_unique<KeptBrowser>(*this, browser, profile_id, window, /*holds_window_pages=*/true));
  return browser;
}

std::string EngineBrowsers::WindowOf(const Browser* browser) const {
  KeptBrowser* kept = browser ? Find(browser) : nullptr;
  return kept ? kept->window : std::string();
}

bool EngineBrowsers::OwnsWindow(const Browser* browser) const {
  KeptBrowser* kept = browser ? Find(browser) : nullptr;
  return !kept || !kept->keeps_tabs;
}

void EngineBrowsers::CloseWindow(const std::string& window) {
  Close([&](const KeptBrowser& kept) { return kept.window == window; });
}

void EngineBrowsers::CloseProfile(Profile* profile) {
  Close([&](const KeptBrowser& kept) { return kept.browser->GetProfile() == profile; });
}

void EngineBrowsers::CloseAll() {
  Close([](const KeptBrowser&) { return true; });
}

// Each Browser leaves the binding's keeping as it is destroyed, which ends the
// loop.
void EngineBrowsers::Close(base::FunctionRef<bool(const KeptBrowser&)> matches) {
  for (;;) {
    auto found = std::find_if(kept_.begin(), kept_.end(), [&](const auto& kept) { return matches(*kept); });
    if (found == kept_.end()) {
      return;
    }
    Browser* browser = (*found)->browser;
    TabStripModel* strip = browser->tab_strip_model();
    if (strip->empty()) {
      BrowserManagerService::SynchronouslyDestroyBrowser(browser);
      continue;
    }
    for (int index = strip->count() - 1; index >= 0; --index) {
      strip->DetachAndDeleteWebContentsAt(index);
    }
  }
}

// What the platform's BrowserWindow reports.

void EngineBrowsers::Created(Browser* browser) {
  if (!bootstrap_) {
    bootstrap_ = browser;
    binding_->Profiles().SetRoot(browser->GetProfile()->GetOriginalProfile());
  }
  // Before the platform hosts Crest there is nowhere to place a Browser, and
  // one being created for a Crest window is kept once it exists.
  if (!binding_->shell() || !creating_window_.empty()) {
    return;
  }
  if (Place(browser)) {
    return;
  }
  // `MayCreate` refuses these before they are created, so this is only
  // reached by a creation path that does not ask it. The Browser is still
  // kept, so its tabs are offered and then refused rather than left running
  // unowned.
  kept_.push_back(
      std::make_unique<KeptBrowser>(*this, browser, std::string(), std::string(), /*holds_window_pages=*/false));
}

void EngineBrowsers::Shown(Browser* browser, bool focused) {
  if (!binding_->shell()) {
    return;
  }
  // `chrome.windows.create` with `focused: false` shows its Browser inactive.
  KeptBrowser* kept = Find(browser);
  if (kept && kept->engine && !kept->engine->presented) {
    kept->engine->focused = focused;
  }
}

void EngineBrowsers::Destroyed(Browser* browser) {
  if (bootstrap_ == browser) {
    bootstrap_ = nullptr;
  }
  std::erase_if(kept_, [browser](const auto& kept) { return kept->browser.get() == browser; });
}

bool EngineBrowsers::MayCreate(Profile* profile) {
  // A Browser created for a Crest window is Crest's own.
  if (!creating_window_.empty()) {
    return true;
  }
  const EngineProfiles& profiles = binding_->Profiles();
  const std::string profile_id = profiles.IdFor(profile);
  EngineBinding::Shell* shell = binding_->shell();
  if (profile_id.empty() || profiles.IsDeleting(profile_id) || !shell ||
      !shell->ReserveWindow(profile_id, /*own_window=*/true)) {
    return false;
  }
  // The Browser is created in this same turn; a creation that fails leaves
  // nothing to hand the window to.
  own_window_profile_ = profile;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<EngineBrowsers> browsers) {
                       if (browsers) {
                         browsers->own_window_profile_ = nullptr;
                       }
                     },
                     weak_factory_.GetWeakPtr()));
  return true;
}

// What the binding keeps.

EngineBrowsers::KeptBrowser* EngineBrowsers::Find(const Browser* browser) const {
  auto found =
      std::find_if(kept_.begin(), kept_.end(), [browser](const auto& kept) { return kept->browser.get() == browser; });
  return found == kept_.end() ? nullptr : found->get();
}

EngineBrowsers::KeptBrowser* EngineBrowsers::HoldingKept(content::WebContents* contents) const {
  if (!contents) {
    return nullptr;
  }
  auto found = std::find_if(kept_.begin(), kept_.end(), [contents](const auto& kept) {
    return kept->strip && kept->strip->GetIndexOfWebContents(contents) != TabStripModel::kNoTab;
  });
  return found == kept_.end() ? nullptr : found->get();
}

// A Browser whose last tab closed is deleted once Chromium's close unwinds,
// and takes no new pages meanwhile.
EngineBrowsers::KeptBrowser* EngineBrowsers::WindowBrowser(const std::string& profile_id,
                                                           const std::string& window) const {
  auto found = std::find_if(kept_.begin(), kept_.end(), [&](const auto& kept) {
    return kept->holds_window_pages && kept->profile == profile_id && kept->window == window &&
           !kept->browser->IsDeleteScheduled();
  });
  return found == kept_.end() ? nullptr : found->get();
}

// Reserves the Crest window a Browser the engine created for itself belongs
// in, so its tabs are offered with a window the core recognizes. The window
// opens only once a tab needs it. A profile with no Space to host it is
// refused rather than routed into an unrelated Space; an off-the-record
// profile belongs to the private window and is refused when that window is
// closed.
//
// A normal window `chrome.windows.create` asked for gets a Crest window of its
// own. A popup it asked for, which Chromium makes an app popup, joins the
// window the person is using as a tab it keeps, and never holds that window's
// other pages, which its extension could otherwise close with the popup.
bool EngineBrowsers::Place(Browser* browser) {
  const bool requested = own_window_profile_ == browser->GetProfile();
  own_window_profile_ = nullptr;
  const bool keeps_tabs = requested && browser->GetType() != BrowserWindowInterface::Type::TYPE_NORMAL;
  const bool own_window = requested && !keeps_tabs;
  const EngineProfiles& profiles = binding_->Profiles();
  const std::string profile_id = profiles.IdFor(browser->GetProfile());
  if (profile_id.empty() || profiles.IsDeleting(profile_id)) {
    return false;
  }
  const auto placement = binding_->shell()->ReserveWindow(profile_id, own_window);
  if (!placement) {
    return false;
  }
  const bool holds_window_pages = !keeps_tabs && !WindowBrowser(profile_id, placement->window);
  kept_.push_back(std::make_unique<KeptBrowser>(*this, browser, profile_id, placement->window, holds_window_pages,
                                                EngineWindow{.space = placement->space}, keeps_tabs));
  return true;
}

void EngineBrowsers::OfferSoon(content::WebContents* contents, bool foreground) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&EngineBrowsers::Offer, weak_factory_.GetWeakPtr(), contents->GetWeakPtr(), foreground));
}

// Offers the core a tab the engine opened by itself, in the Crest window its
// Browser belongs to.
void EngineBrowsers::Offer(base::WeakPtr<content::WebContents> contents, bool foreground) {
  EngineBinding& binding = *binding_;
  if (!contents || binding.disposing() || binding.PageFor(contents.get())) {
    return;
  }
  // A window whose link opened in Peek is never offered, and closes.
  if (binding.Withholds(contents.get())) {
    Destroy(contents.get());
    return;
  }
  KeptBrowser* host = HoldingKept(contents.get());
  // A window the engine created for itself has no Crest window until one of
  // its tabs needs it. A renderer's popup keeps its opener's window instead:
  // the core opens its tab beside the page that opened it.
  content::RenderFrameHost* opener = contents->GetOpener();
  const bool opened_by_page = opener && binding.PageFor(content::WebContents::FromRenderFrameHost(opener));
  if (host && host->engine && !host->engine->presented && !opened_by_page) {
    host->engine->presented = true;
    if (EngineBinding::Shell* shell = binding.shell()) {
      shell->PresentWindow(EngineBinding::WindowPlacement{.window = host->window, .space = host->engine->space},
                           host->engine->focused);
    }
  }
  binding.Offer(contents.get(), host ? host->window : std::string(),
                host && host->engine ? host->engine->space : std::string(), foreground);
}

// The platform's BrowserWindow reports through these hooks.

void OnBrowserWindowCreated(Browser* browser) {
  EngineBinding::Get().Browsers().Created(browser);
}

void OnBrowserWindowDestroyed(Browser* browser) {
  EngineBinding::Get().Browsers().Destroyed(browser);
}

void OnEngineWindowShown(Browser* browser, bool focused) {
  EngineBinding::Get().Browsers().Shown(browser, focused);
}

bool OwnsWindow(const Browser* browser) {
  return EngineBinding::Get().Browsers().OwnsWindow(browser);
}

}  // namespace crest
