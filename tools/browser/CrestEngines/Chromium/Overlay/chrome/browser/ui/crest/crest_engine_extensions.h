#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_EXTENSIONS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_EXTENSIONS_H_

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/extensions/api/side_panel/side_panel_service.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/browser/extension_icon_image.h"
#include "extensions/browser/extension_registry_observer.h"
#include "ui/gfx/image/image.h"

class GURL;
class Profile;

namespace content {
class WebContents;
}

namespace extensions {
class Extension;
class ExtensionAction;
}  // namespace extensions

namespace crest {

// One profile's extensions as Crest shows them: the best icon each has, whether
// its files still exist, and when anything the toolbar shows changes.
// Adapted from Mori (MIT).
class ProfileExtensions final : public extensions::ExtensionRegistryObserver,
                                public extensions::ExtensionActionDispatcher::Observer,
                                public extensions::SidePanelService::Observer,
                                public ToolbarActionsModel::Observer,
                                public extensions::IconImage::Observer {
 public:
  // An extension's side panel no longer applies to the tab `tab` names, or to
  // any tab.
  using Retract =
      base::RepeatingCallback<void(Profile* profile, const std::string& extension, std::optional<int> tab)>;

  // Follows `profile`'s extensions. `changed` hears that something the
  // toolbar shows changed, at once and possibly often.
  ProfileExtensions(Profile* profile, base::RepeatingClosure changed, Retract retract);
  ProfileExtensions(const ProfileExtensions&) = delete;
  ProfileExtensions& operator=(const ProfileExtensions&) = delete;
  ~ProfileExtensions() override;

  // The best icon loaded for an extension: the action's own for `tab` — set
  // by `chrome.action.setIcon` or declared — then the manifest's, then the
  // action's default.
  gfx::Image IconFor(const extensions::Extension& extension, extensions::ExtensionAction* action, int tab);
  // Whether an extension still has the files it was installed from.
  bool IsAvailable(const extensions::Extension& extension, extensions::ExtensionAction* action);

  // extensions::ExtensionRegistryObserver:
  void OnExtensionLoaded(content::BrowserContext* context, const extensions::Extension* extension) override;
  void OnExtensionUnloaded(content::BrowserContext* context,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason reason) override;
  void OnExtensionInstalled(content::BrowserContext* context,
                            const extensions::Extension* extension,
                            bool is_update) override;
  void OnExtensionUninstalled(content::BrowserContext* context,
                              const extensions::Extension* extension,
                              extensions::UninstallReason reason) override;

  // extensions::SidePanelService::Observer:
  void OnPanelOptionsChanged(const extensions::ExtensionId& extension_id,
                             const extensions::api::side_panel::PanelOptions& options) override;
  void OnSidePanelServiceShutdown() override;

  // extensions::ExtensionActionDispatcher::Observer:
  void OnExtensionActionUpdated(extensions::ExtensionAction* action,
                                content::WebContents* contents,
                                content::BrowserContext* context) override;
  void OnShuttingDown() override;

  // ToolbarActionsModel::Observer:
  void OnToolbarActionAdded(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionRemoved(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionUpdated(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarModelInitialized() override;
  void OnToolbarPinnedActionsChanged() override;

  // extensions::IconImage::Observer:
  void OnExtensionIconImageChanged(extensions::IconImage* image) override;

 private:
  void RebuildIcons();

  const raw_ptr<Profile> profile_;
  const base::RepeatingClosure changed_;
  const Retract retract_;
  bool dispatcher_observed_ = false;
  bool side_panel_observed_ = false;
  std::map<std::string, std::unique_ptr<extensions::IconImage>> icons_;
  std::map<std::string, bool> availability_;
};

// The binding's extensions: each profile's, what the toolbar and Settings list
// of them, and what the person changes. A profile's changes are presented
// once each turn.
class EngineExtensions final {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;

  EngineExtensions(Present present, ProfileExtensions::Retract retract, base::RepeatingClosure changed);
  EngineExtensions(const EngineExtensions&) = delete;
  EngineExtensions& operator=(const EngineExtensions&) = delete;
  ~EngineExtensions();

  // The extensions of the engine profile `profile_id` names, followed from now on.
  ProfileExtensions& For(Profile* profile, const std::string& profile_id);
  void Forget(const std::string& profile_id);
  void Clear();

  // The actions the toolbar of the page showing `contents` offers.
  engine::ExtensionActionList PageActions(content::WebContents* contents, const std::string& profile_id);
  // The actions pinned in a profile, which its Space shows with no page open.
  engine::ExtensionActionList Pinned(Profile* profile, const std::string& profile_id);
  engine::InstalledExtensionList Installed(Profile* profile, const std::string& profile_id);
  bool Change(Profile* profile, const std::string& extension_id, engine::ExtensionChange change);
  // The extension, only if it has a side panel for `contents`' own tab.
  static const extensions::Extension* SidePanelExtension(content::WebContents* contents,
                                                         const std::string& extension_id);
  // Which side panel the extension has for `contents`' own tab: one it gave
  // that tab, its panel for every tab, or none.
  static engine::SidePanelScope SidePanelScopeFor(content::WebContents* contents, const std::string& extension_id);

 private:
  void Changed(const std::string& profile_id);
  void Flush();

  const Present present_;
  const ProfileExtensions::Retract retract_;
  const base::RepeatingClosure changed_;
  std::map<std::string, std::unique_ptr<ProfileExtensions>> profiles_;
  std::set<std::string> due_;
  bool flush_posted_ = false;
  base::WeakPtrFactory<EngineExtensions> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_EXTENSIONS_H_
