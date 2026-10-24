#include "chrome/browser/ui/crest/crest_engine_extensions.h"

#include <utility>
#include <vector>

#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/extension_util.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/pref_names.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/common/api/extension_action/action_info.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest.h"
#include "extensions/common/manifest_handlers/icons_handler.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "extensions/common/permissions/permission_message.h"
#include "extensions/common/permissions/permissions_data.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "url/gurl.h"

namespace crest {

namespace {

// The scale an icon is drawn at for the platform's Retina displays.
constexpr float kIconScale = 2.0f;

// An icon as a PNG at `kIconScale`, or nothing.
std::optional<std::vector<uint8_t>> IconPNG(const gfx::Image& image) {
  if (image.IsEmpty()) {
    return std::nullopt;
  }
  const gfx::ImageSkia skia = image.AsImageSkia();
  const gfx::ImageSkiaRep& rep = skia.GetRepresentation(kIconScale);
  if (rep.is_null()) {
    return std::nullopt;
  }
  return gfx::PNGCodec::EncodeBGRASkBitmap(rep.GetBitmap(), /*discard_transparency=*/false);
}

bool Listed(const extensions::Extension& extension) {
  return extension.is_extension() && !extensions::Manifest::IsComponentLocation(extension.location());
}

}  // namespace

// ProfileExtensions.

ProfileExtensions::ProfileExtensions(Profile* profile, base::RepeatingClosure changed, Retract retract)
    : profile_(profile), changed_(std::move(changed)), retract_(std::move(retract)) {
  extensions::ExtensionRegistry::Get(profile_)->AddObserver(this);
  extensions::ExtensionActionDispatcher::Get(profile_)->AddObserver(this);
  dispatcher_observed_ = true;
  if (auto* panels = extensions::SidePanelService::Get(profile_)) {
    panels->AddObserver(this);
    side_panel_observed_ = true;
  }
  if (ToolbarActionsModel* model = ToolbarActionsModel::Get(profile_)) {
    model->AddObserver(this);
  }
  RebuildIcons();
}

ProfileExtensions::~ProfileExtensions() {
  extensions::ExtensionRegistry::Get(profile_)->RemoveObserver(this);
  if (dispatcher_observed_) {
    extensions::ExtensionActionDispatcher::Get(profile_)->RemoveObserver(this);
  }
  if (side_panel_observed_) {
    extensions::SidePanelService::Get(profile_)->RemoveObserver(this);
  }
  if (auto* model = ToolbarActionsModel::Get(profile_)) {
    model->RemoveObserver(this);
  }
}

gfx::Image ProfileExtensions::IconFor(const extensions::Extension& extension,
                                      extensions::ExtensionAction* action,
                                      int tab) {
  if (action) {
    if (gfx::Image icon = action->GetExplicitlySetIcon(tab); !icon.IsEmpty()) {
      return icon;
    }
    if (gfx::Image icon = action->GetDeclarativeIcon(tab); !icon.IsEmpty()) {
      return icon;
    }
  }
  if (auto found = icons_.find(extension.id()); found != icons_.end()) {
    if (gfx::Image icon = found->second->image(); !icon.IsEmpty()) {
      return icon;
    }
  }
  if (action) {
    if (gfx::Image icon = action->GetDefaultIconImage(); !icon.IsEmpty()) {
      return icon;
    }
  }
  return gfx::Image();
}

// A tracked-preference reset clears `extensions.settings` and collects the
// install directories, and an extension can also be loaded from a directory
// the person has since moved or deleted. The engine keeps such an extension
// enabled and only finds the loss when a resource is asked for, which for an
// action is its popup showing ERR_FILE_NOT_FOUND. Crest offers no action for
// one: it is missing, not broken. One stat per extension per registry change;
// every registry change drops what was found.
bool ProfileExtensions::IsAvailable(const extensions::Extension& extension, extensions::ExtensionAction* action) {
  if (auto cached = availability_.find(extension.id()); cached != availability_.end()) {
    return cached->second;
  }
  bool available = !extension.path().empty() && base::PathExists(extension.path());
  if (available && action) {
    // A default popup is the resource the action's own click needs. A popup
    // set at runtime would be read from the directory just checked.
    const GURL popup = action->GetPopupUrl(extensions::ExtensionAction::kDefaultTabId);
    if (!popup.is_empty() && extension.GetResource(popup.path()).GetFilePath().empty()) {
      available = false;
    }
  }
  availability_[extension.id()] = available;
  return available;
}

void ProfileExtensions::OnExtensionLoaded(content::BrowserContext*, const extensions::Extension*) {
  RebuildIcons();
  changed_.Run();
}

void ProfileExtensions::OnExtensionUnloaded(content::BrowserContext*,
                                            const extensions::Extension* extension,
                                            extensions::UnloadedExtensionReason) {
  retract_.Run(profile_, extension->id(), std::nullopt);
  RebuildIcons();
  changed_.Run();
}

void ProfileExtensions::OnExtensionInstalled(content::BrowserContext*, const extensions::Extension*, bool) {
  RebuildIcons();
  changed_.Run();
}

void ProfileExtensions::OnExtensionUninstalled(content::BrowserContext*,
                                               const extensions::Extension*,
                                               extensions::UninstallReason) {
  RebuildIcons();
  changed_.Run();
}

// `chrome.sidePanel.setOptions` can retract a panel Crest is showing. The
// engine hands over the extension's merged options, so a panel that no longer
// resolves to an enabled document closes.
void ProfileExtensions::OnPanelOptionsChanged(const extensions::ExtensionId& extension_id,
                                              const extensions::api::side_panel::PanelOptions& options) {
  if (options.enabled.value_or(true) && options.path && !options.path->empty()) {
    return;
  }
  retract_.Run(profile_, extension_id, options.tab_id ? std::optional<int>(*options.tab_id) : std::nullopt);
}

void ProfileExtensions::OnSidePanelServiceShutdown() {
  side_panel_observed_ = false;
}

void ProfileExtensions::OnExtensionActionUpdated(extensions::ExtensionAction*,
                                                 content::WebContents*,
                                                 content::BrowserContext*) {
  changed_.Run();
}

void ProfileExtensions::OnShuttingDown() {
  dispatcher_observed_ = false;
}

void ProfileExtensions::OnToolbarActionAdded(const ToolbarActionsModel::ActionId&) {
  changed_.Run();
}

void ProfileExtensions::OnToolbarActionRemoved(const ToolbarActionsModel::ActionId&) {
  changed_.Run();
}

void ProfileExtensions::OnToolbarActionUpdated(const ToolbarActionsModel::ActionId&) {
  changed_.Run();
}

void ProfileExtensions::OnToolbarModelInitialized() {
  changed_.Run();
}

void ProfileExtensions::OnToolbarPinnedActionsChanged() {
  changed_.Run();
}

void ProfileExtensions::OnExtensionIconImageChanged(extensions::IconImage*) {
  changed_.Run();
}

// One loading manifest icon per installed extension. An icon image
// invalidates itself when its extension unloads, so the map is rebuilt on
// every registry change.
void ProfileExtensions::RebuildIcons() {
  availability_.clear();
  auto* registry = extensions::ExtensionRegistry::Get(profile_);
  std::map<std::string, std::unique_ptr<extensions::IconImage>> next;
  for (const extensions::ExtensionSet* set : {&registry->enabled_extensions(), &registry->disabled_extensions()}) {
    for (const auto& extension : *set) {
      if (!extension->is_extension()) {
        continue;
      }
      if (auto existing = icons_.find(extension->id()); existing != icons_.end() && existing->second->is_valid()) {
        next[extension->id()] = std::move(existing->second);
        continue;
      }
      next[extension->id()] = std::make_unique<extensions::IconImage>(
          profile_, extension.get(), extensions::IconsInfo::GetIcons(extension.get()), 32, gfx::ImageSkia(), this);
    }
  }
  icons_ = std::move(next);
}

// EngineExtensions.

EngineExtensions::EngineExtensions(Present present, ProfileExtensions::Retract retract, base::RepeatingClosure changed)
    : present_(std::move(present)), retract_(std::move(retract)), changed_(std::move(changed)) {}

EngineExtensions::~EngineExtensions() = default;

ProfileExtensions& EngineExtensions::For(Profile* profile, const std::string& profile_id) {
  auto& state = profiles_[profile_id];
  if (!state) {
    state = std::make_unique<ProfileExtensions>(
        profile, base::BindRepeating(&EngineExtensions::Changed, weak_factory_.GetWeakPtr(), profile_id), retract_);
  }
  return *state;
}

void EngineExtensions::Forget(const std::string& profile_id) {
  profiles_.erase(profile_id);
  due_.erase(profile_id);
}

void EngineExtensions::Clear() {
  profiles_.clear();
  due_.clear();
}

engine::ExtensionActionList EngineExtensions::PageActions(content::WebContents* contents,
                                                          const std::string& profile_id) {
  engine::ExtensionActionList list;
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* actions = extensions::ExtensionActionManager::Get(profile);
  if (!registry || !actions) {
    return list;
  }
  const int tab = sessions::SessionTabHelper::IdForTab(contents).id();
  auto& state = For(profile, profile_id);
  auto* model = ToolbarActionsModel::Get(profile);
  for (const auto& extension : registry->enabled_extensions()) {
    if (!Listed(*extension) ||
        (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(extension->id(), profile))) {
      continue;
    }
    auto* action = actions->GetExtensionAction(*extension);
    // An extension whose files are gone has no action to offer.
    if (!action || !state.IsAvailable(*extension, action)) {
      continue;
    }
    list.actions.push_back(engine::ExtensionAction{.id = extension->id(),
                                                   .name = extension->name(),
                                                   .badge = action->GetExplicitlySetBadgeText(tab),
                                                   .icon = IconPNG(state.IconFor(*extension, action, tab)),
                                                   .pinned = model && model->IsActionPinned(extension->id()),
                                                   .enabled = true});
  }
  return list;
}

// The pinned strip belongs to the Space, not to whatever page is open in it:
// a Space showing its Start Page still has the extensions the person pinned.
// Private profiles derive from the engine root, never a Space, so they have
// no installed Space extensions or pins. The registry belongs to whichever
// original profile owns this off-the-record profile.
engine::ExtensionActionList EngineExtensions::Pinned(Profile* profile, const std::string& profile_id) {
  engine::ExtensionActionList list;
  const bool private_mode = profile->IsOffTheRecord();
  Profile* owner = profile->GetOriginalProfile();
  auto* registry = extensions::ExtensionRegistry::Get(owner);
  auto* actions = extensions::ExtensionActionManager::Get(owner);
  if (!registry || !actions) {
    return list;
  }
  // The pins are read from the preference the toolbar model persists rather
  // than from the model: a profile only just loaded, as every Space on its
  // Start Page is, has no model yet.
  std::set<std::string> pinned;
  for (const base::Value& entry : owner->GetPrefs()->GetList(extensions::pref_names::kPinnedExtensions)) {
    if (const std::string* id = entry.GetIfString()) {
      pinned.insert(*id);
    }
  }
  if (pinned.empty()) {
    return list;
  }
  auto& state = For(profile, profile_id);
  const int tab = extensions::ExtensionAction::kDefaultTabId;
  for (const auto& extension : registry->enabled_extensions()) {
    if (!Listed(*extension) || !pinned.contains(extension->id()) ||
        (private_mode && !extensions::util::IsIncognitoEnabled(extension->id(), owner))) {
      continue;
    }
    auto* action = actions->GetExtensionAction(*extension);
    if (!action || !state.IsAvailable(*extension, action)) {
      continue;
    }
    // A page action acts on a page. With none open its tile still shows —
    // the person pinned it — but it has nothing to act on.
    list.actions.push_back(
        engine::ExtensionAction{.id = extension->id(),
                                .name = extension->name(),
                                .badge = action->GetExplicitlySetBadgeText(tab),
                                .icon = IconPNG(state.IconFor(*extension, action, tab)),
                                .pinned = true,
                                .enabled = action->action_type() != extensions::ActionInfo::Type::kPage});
  }
  return list;
}

engine::InstalledExtensionList EngineExtensions::Installed(Profile* profile, const std::string& profile_id) {
  engine::InstalledExtensionList list;
  if (profile->IsOffTheRecord()) {
    return list;
  }
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* actions = extensions::ExtensionActionManager::Get(profile);
  auto& state = For(profile, profile_id);
  for (const auto& extension : registry->GenerateInstalledExtensionsSet()) {
    if (!Listed(*extension)) {
      continue;
    }
    auto* action = actions->GetExtensionAction(*extension);
    // An extension with a registry entry but no files is absent, not a row
    // the person could act on.
    if (!state.IsAvailable(*extension, action)) {
      continue;
    }
    engine::InstalledExtension item{.id = extension->id(),
                                    .name = extension->name(),
                                    .version = extension->version().GetString(),
                                    .icon = IconPNG(state.IconFor(*extension, action, -1)),
                                    .enabled = registry->enabled_extensions().Contains(extension->id()),
                                    .from_web_store = extension->from_webstore()};
    if (const std::string* description = extension->manifest()->FindStringPath("description")) {
      item.description = *description;
    }
    for (const auto& permission : extension->permissions_data()->GetPermissionMessages()) {
      item.permissions.push_back(base::UTF16ToUTF8(permission.message()));
    }
    if (const GURL options = extensions::OptionsPageInfo::GetOptionsPage(extension.get()); options.is_valid()) {
      item.options_url = options.spec();
    }
    list.extensions.push_back(std::move(item));
  }
  return list;
}

bool EngineExtensions::Change(Profile* profile, const std::string& extension_id, engine::ExtensionChange change) {
  if (profile->IsOffTheRecord()) {
    return false;
  }
  const auto* extension = extensions::ExtensionRegistry::Get(profile)->GetInstalledExtension(extension_id);
  if (!extension ||
      !extensions::ExtensionSystem::Get(profile)->management_policy()->UserMayModifySettings(extension, nullptr)) {
    return false;
  }
  auto* registrar = extensions::ExtensionRegistrar::Get(profile);
  switch (change) {
    case engine::ExtensionChange::kEnable:
      registrar->EnableExtension(extension_id);
      return true;
    case engine::ExtensionChange::kDisable:
      registrar->DisableExtension(extension_id, {extensions::disable_reason::DISABLE_USER_ACTION});
      return true;
    case engine::ExtensionChange::kRemove: {
      std::u16string error;
      return registrar->UninstallExtension(extension_id, extensions::UNINSTALL_REASON_USER_INITIATED, &error);
    }
    case engine::ExtensionChange::kPin:
    case engine::ExtensionChange::kUnpin: {
      auto* model = ToolbarActionsModel::Get(profile);
      if (!model || !model->HasAction(extension_id) || model->IsActionForcePinned(extension_id)) {
        return false;
      }
      model->SetActionVisibility(extension_id, change == engine::ExtensionChange::kPin);
      return true;
    }
  }
  return false;
}

// Crest resolves the panel itself: the engine's own side panel service drives
// Chrome's Views side-panel UI, which this build never creates. An explicit
// `chrome.sidePanel.open()` needs only an enabled panel for the tab, not the
// open-on-action-click behaviour; whether an action click toggles a panel is
// decided before the request reaches Crest.
// static
const extensions::Extension* EngineExtensions::SidePanelExtension(content::WebContents* contents,
                                                                  const std::string& extension_id) {
  if (!contents) {
    return nullptr;
  }
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  const auto* extension = extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(extension_id);
  if (!extension || (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(extension_id, profile))) {
    return nullptr;
  }
  auto* service = extensions::SidePanelService::Get(profile);
  if (!service) {
    return nullptr;
  }
  const int tab = sessions::SessionTabHelper::IdForTab(contents).id();
  return service->HasSidePanelContextMenuActionForTab(*extension, tab) ? extension : nullptr;
}

// A tab with no panel options of its own shows the extension's default panel,
// which Chromium's side panel keeps open as the person moves between such tabs.
// static
engine::SidePanelScope EngineExtensions::SidePanelScopeFor(content::WebContents* contents,
                                                           const std::string& extension_id) {
  const extensions::Extension* extension = SidePanelExtension(contents, extension_id);
  if (!extension) {
    return engine::SidePanelScope::kUnavailable;
  }
  auto* service = extensions::SidePanelService::Get(Profile::FromBrowserContext(contents->GetBrowserContext()));
  const int tab = sessions::SessionTabHelper::IdForTab(contents).id();
  return service->GetSpecificOptionsForTab(*extension, tab).path ? engine::SidePanelScope::kTab
                                                                 : engine::SidePanelScope::kWindow;
}

// Changes arrive in bursts while the registry and the toolbar model mutate,
// so each profile's are presented once the turn ends.
void EngineExtensions::Changed(const std::string& profile_id) {
  due_.insert(profile_id);
  if (flush_posted_) {
    return;
  }
  flush_posted_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineExtensions::Flush, weak_factory_.GetWeakPtr()));
}

void EngineExtensions::Flush() {
  flush_posted_ = false;
  std::set<std::string> due = std::move(due_);
  due_.clear();
  for (const std::string& profile_id : due) {
    if (auto profile = ParseGuid(profile_id)) {
      present_.Run(engine::ExtensionsChanged{.profile_id = *profile});
    }
  }
  changed_.Run();
}

}  // namespace crest
