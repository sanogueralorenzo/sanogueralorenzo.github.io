#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_BROWSERS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_BROWSERS_H_

#include <memory>
#include <string>
#include <vector>

#include "base/functional/function_ref.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/weak_ptr.h"
#include "components/tab_groups/tab_group_id.h"

class Browser;
class Profile;

namespace content {
class WebContents;
}

namespace crest {

class EngineBinding;

// The Browsers the binding keeps, and each one's tab strip. Chromium hosts a
// tab only inside a Browser, so each Crest window has one Browser for every
// profile whose pages it shows, created when the first of them opens there.
// The engine also creates Browsers for itself: for `chrome.windows.create`, a
// renderer's popup or an extension's app window. Each of those is placed in a
// Crest window the platform reserves, and every tab the engine opens by
// itself is offered to the core, which adopts it for a tab of its own or
// refuses it.
//
// A popup an extension creates, as a password manager's popout, shows as a
// tab in the window the person is using, and its tab stays in its own
// Browser: the extension still has the window it asked for, whose id,
// `chrome.windows.remove` and close events are that tab's alone.
//
// Each Browser is built on the platform's BrowserWindow, which Chromium's
// window factory makes for it and which reports here when the Browser is
// created, shown and destroyed. The platform only makes and hosts windows and
// views; which Browser a page is in, and when a Browser opens and closes, is
// decided here.
class EngineBrowsers final {
 public:
  explicit EngineBrowsers(EngineBinding& binding);
  EngineBrowsers(const EngineBrowsers&) = delete;
  EngineBrowsers& operator=(const EngineBrowsers&) = delete;
  ~EngineBrowsers();

  // A new page's WebContents, created hidden in `profile`, which `profile_id`
  // names, in the Browser of the Crest window `window`, or nullptr when that
  // window can have no Browser for the profile. The controller keeps its
  // initial entry until the page loads its first address or restores its
  // history.
  content::WebContents* CreateContents(Profile* profile, const std::string& profile_id, const std::string& window);
  // Moves `contents` into the Browser of `profile_id`'s pages in the Crest
  // window `window`, keeping its history, renderer and extension identity,
  // and makes it that Browser's active tab.
  bool MoveToWindow(content::WebContents* contents, const std::string& profile_id, const std::string& window);
  // Makes `contents` its Browser's active tab, as an extension action run on
  // it expects. False when no Browser the binding keeps holds it.
  bool Activate(content::WebContents* contents);
  // Deletes `contents` from the Browser that holds it.
  void Destroy(content::WebContents* contents);

  // The Browser that holds `contents`, or nullptr.
  Browser* Holding(content::WebContents* contents) const;
  // The Browser whose tab strip holds the tab group `group`, or nullptr.
  Browser* HoldingGroup(const tab_groups::TabGroupId& group) const;
  // The Browser of `profile_id`'s pages in the Crest window `window`, created
  // when it has none, or nullptr when the profile is not loaded or the engine
  // refuses a Browser for it.
  Browser* ForWindow(const std::string& profile_id, const std::string& window);
  // The Crest window `browser` belongs in, or empty for none.
  std::string WindowOf(const Browser* browser) const;
  // Whether `browser` may move, resize, hide or minimize the Crest window it
  // belongs in. An extension's popup shown as a tab there may not.
  bool OwnsWindow(const Browser* browser) const;
  // The Crest window whose Browser is being created now, or empty.
  const std::string& creating_window() const { return creating_window_; }

  // Closes the Browsers of the Crest window `window`, of `profile`, or all of
  // them: an empty Browser at once, and one with tabs by closing its tabs,
  // which closes the Browser.
  void CloseWindow(const std::string& window);
  void CloseProfile(Profile* profile);
  void CloseAll();

  // What the platform's BrowserWindow reports: `browser` was created, shown
  // (in front when `focused`) or destroyed.
  void Created(Browser* browser);
  void Shown(Browser* browser, bool focused);
  void Destroyed(Browser* browser);
  // Whether the engine may create a Browser for itself in `profile`, which
  // `chrome.windows.create` asks before it creates one. A normal window gets a
  // Crest window of its own, and a popup a tab in the window the person is
  // using.
  bool MayCreate(Profile* profile);

 private:
  struct KeptBrowser;
  struct EngineWindow;

  KeptBrowser* Find(const Browser* browser) const;
  KeptBrowser* HoldingKept(content::WebContents* contents) const;
  KeptBrowser* WindowBrowser(const std::string& profile_id, const std::string& window) const;
  // Places a Browser the engine created for itself in the Crest window the
  // platform reserves for it. False when no Space can host its profile's tabs.
  bool Place(Browser* browser);
  void Close(base::FunctionRef<bool(const KeptBrowser&)> matches);
  // Offers `contents`, which the engine opened by itself, once the turn ends:
  // a page the core created registers first.
  void OfferSoon(content::WebContents* contents, bool foreground);
  void Offer(base::WeakPtr<content::WebContents> contents, bool foreground);

  const raw_ref<EngineBinding> binding_;
  std::vector<std::unique_ptr<KeptBrowser>> kept_;
  // The Browser Chromium started with, whose profile is the engine's own.
  raw_ptr<Browser> bootstrap_ = nullptr;
  std::string creating_window_;
  // The profile `chrome.windows.create` is about to create a Browser in, for
  // the one turn between asking and creating: that Browser is the extension's
  // own window. Every other Browser the engine creates joins an open window.
  raw_ptr<Profile> own_window_profile_ = nullptr;
  base::WeakPtrFactory<EngineBrowsers> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_BROWSERS_H_
