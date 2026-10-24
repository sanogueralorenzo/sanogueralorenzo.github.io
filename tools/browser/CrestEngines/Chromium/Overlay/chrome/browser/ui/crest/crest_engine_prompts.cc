#include "chrome/browser/ui/crest/crest_engine_prompts.h"

#include <optional>
#include <utility>
#include <variant>
#include <vector>

#include "base/functional/bind.h"
#include "base/strings/utf_string_conversions.h"
#include "base/uuid.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_remover_constants.h"
#include "chrome/browser/permissions/system/system_permission_settings.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "chrome/browser/ui/crest/crest_permission_prompt.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/request_type.h"
#include "content/public/browser/browsing_data_filter_builder.h"
#include "content/public/browser/browsing_data_remover.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "net/base/auth.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace crest {

namespace {

// The Crest permission a batch of engine requests amounts to, or nothing when
// any of them is one Crest's record does not cover.
std::optional<engine::SitePermission> PermissionFor(permissions::PermissionPrompt::Delegate* delegate) {
  bool camera = false;
  bool microphone = false;
  std::optional<engine::SitePermission> single;
  bool several = false;
  for (const auto& request : delegate->Requests()) {
    switch (request->request_type()) {
      case permissions::RequestType::kCameraStream:
        camera = true;
        break;
      case permissions::RequestType::kMicStream:
        microphone = true;
        break;
      case permissions::RequestType::kGeolocation:
        several = several || single.has_value();
        single = engine::SitePermission::kLocation;
        break;
      case permissions::RequestType::kNotifications:
        several = several || single.has_value();
        single = engine::SitePermission::kNotifications;
        break;
      default:
        return std::nullopt;
    }
  }
  if (camera || microphone) {
    if (single) {
      return std::nullopt;
    }
    return camera && microphone ? engine::SitePermission::kCameraAndMicrophone
           : camera             ? engine::SitePermission::kCamera
                                : engine::SitePermission::kMicrophone;
  }
  return several ? std::nullopt : single;
}

// The capture devices a batch of engine requests asks for. Chromium keeps the
// system's answer for each, and reads it again only when it asks the system
// itself.
std::vector<ContentSettingsType> CaptureDevicesFor(permissions::PermissionPrompt::Delegate& delegate) {
  std::vector<ContentSettingsType> devices;
  for (const auto& request : delegate.Requests()) {
    switch (request->request_type()) {
      case permissions::RequestType::kCameraStream:
        devices.push_back(ContentSettingsType::MEDIASTREAM_CAMERA);
        break;
      case permissions::RequestType::kMicStream:
        devices.push_back(ContentSettingsType::MEDIASTREAM_MIC);
        break;
      default:
        break;
    }
  }
  return devices;
}

// Removes a site's data, then answers; it owns itself until the remover
// reports back.
class SiteDataClearance final : public content::BrowsingDataRemover::Observer {
 public:
  SiteDataClearance(content::BrowsingDataRemover* remover, base::OnceCallback<void(bool)> done)
      : remover_(remover), done_(std::move(done)) {
    remover_->AddObserver(this);
  }

  void OnBrowsingDataRemoverDone(uint64_t failures) override {
    remover_->RemoveObserver(this);
    std::move(done_).Run(failures == 0);
    delete this;
  }

 private:
  const raw_ptr<content::BrowsingDataRemover> remover_;
  base::OnceCallback<void(bool)> done_;
};

// The origin a permission belongs to, as Crest's choices name it.
engine::SiteOrigin SiteOriginOf(const GURL& url) {
  const url::Origin origin = url::Origin::Create(url);
  return engine::SiteOrigin{.scheme = origin.scheme(), .host = origin.host(), .port = origin.port()};
}

}  // namespace

engine::Guid RandomGuid() {
  return *ParseGuid(base::Uuid::GenerateRandomV4().AsLowercaseString());
}

void ClearSiteData(Profile* profile, const GURL& url, base::OnceCallback<void(bool)> done) {
  std::string domain = net::registry_controlled_domains::GetDomainAndRegistry(
      url, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  if (domain.empty()) {
    domain = url.host();
  }
  if (domain.empty()) {
    std::move(done).Run(false);
    return;
  }
  auto filter = content::BrowsingDataFilterBuilder::Create(content::BrowsingDataFilterBuilder::Mode::kDelete);
  filter->AddRegisterableDomain(domain);
  auto* remover = profile->GetBrowsingDataRemover();
  auto* clearance = new SiteDataClearance(remover, std::move(done));
  remover->RemoveWithFilterAndReply(
      base::Time(), base::Time::Max(),
      chrome_browsing_data_remover::DATA_TYPE_SITE_DATA | content::BrowsingDataRemover::DATA_TYPE_CACHE,
      content::BrowsingDataRemover::ORIGIN_TYPE_UNPROTECTED_WEB, std::move(filter), clearance);
}

// A request Crest's permission record covers, asked through the core so the
// decision is recorded per Space and listed in Privacy. The engine lets go of
// a prompt it no longer needs, such as when the page navigates; one the core
// had not answered is withdrawn.
class EnginePrompts::PermissionPrompt final : public permissions::PermissionPrompt {
 public:
  PermissionPrompt(Delegate* delegate, const engine::Guid& id, base::WeakPtr<EnginePrompts> prompts)
      : delegate_(delegate->GetWeakPtr()), id_(id), prompts_(std::move(prompts)) {}

  ~PermissionPrompt() override {
    if (!answered_ && prompts_) {
      prompts_->Withdrawn(id_);
    }
  }

  base::WeakPtr<PermissionPrompt> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }

  // A grant or block the site's later requests follow, or one for this
  // request alone. A camera or microphone grant waits until Chromium has read
  // the system's answer for each device, asking the system when it has none.
  // Crest's own question has usually asked the system already, which Chromium
  // does not hear; granted before Chromium reads that answer, a page's
  // embedded camera or microphone control waits for a system answer it never
  // sees.
  void Answer(bool grants, bool remembers) {
    answered_ = true;
    if (!delegate_) {
      return;
    }
    std::vector<ContentSettingsType> devices;
    if (grants) {
      devices = CaptureDevicesFor(*delegate_);
    }
    if (devices.empty()) {
      AnswerPermissionRequests(*delegate_, grants, remembers);
      return;
    }
    devices_awaited_ = devices.size();
    for (ContentSettingsType device : devices) {
      system_permission_settings::Request(
          device, base::BindOnce(&PermissionPrompt::DeviceRead, weak_factory_.GetWeakPtr(), remembers));
    }
  }

  // permissions::PermissionPrompt:
  bool UpdateAnchor() override { return true; }
  TabSwitchingBehavior GetTabSwitchingBehavior() override { return kKeepPromptAlive; }
  permissions::PermissionPromptDisposition GetPromptDisposition() const override {
    return permissions::PermissionPromptDisposition::ANCHORED_BUBBLE;
  }
  bool IsAskPrompt() const override { return true; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override { return std::nullopt; }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants() const override { return {}; }
  std::optional<permissions::feature_params::PermissionElementPromptPosition> GetPromptPosition() const override {
    return std::nullopt;
  }

 private:
  // Chromium read the system's answer for one device; the grant follows the
  // last. A prompt Chromium let go of meanwhile answers nothing.
  void DeviceRead(bool remembers) {
    if (--devices_awaited_ > 0 || !delegate_) {
      return;
    }
    AnswerPermissionRequests(*delegate_, /*grants=*/true, remembers);
  }

  base::WeakPtr<Delegate> delegate_;
  const engine::Guid id_;
  const base::WeakPtr<EnginePrompts> prompts_;
  bool answered_ = false;
  size_t devices_awaited_ = 0;
  base::WeakPtrFactory<PermissionPrompt> weak_factory_{this};
};

EnginePrompts::EnginePrompts(Report report) : report_(std::move(report)) {}

// Installs and screen sharing still waiting are declined, so neither waits on
// a binding that is gone.
EnginePrompts::~EnginePrompts() {
  auto installs = std::move(installs_);
  for (auto& [id, reply] : installs) {
    std::move(reply).Run(false, false);
  }
  auto shares = std::move(shares_);
  for (auto& [id, share] : shares) {
    std::move(share.reply).Run(false);
  }
}

// Script dialogs.

void EnginePrompts::RunJavaScriptDialog(content::WebContents* contents,
                                        content::RenderFrameHost* frame,
                                        content::JavaScriptDialogType type,
                                        const std::u16string& message,
                                        const std::u16string& default_text,
                                        DialogClosedCallback callback,
                                        bool* did_suppress_message) {
  *did_suppress_message = false;
  const auto kind = type == content::JAVASCRIPT_DIALOG_TYPE_ALERT     ? engine::JavaScriptDialogKind::kAlert
                    : type == content::JAVASCRIPT_DIALOG_TYPE_CONFIRM ? engine::JavaScriptDialogKind::kConfirm
                                                                      : engine::JavaScriptDialogKind::kPrompt;
  Open(contents, frame, kind, message, default_text, std::move(callback));
}

void EnginePrompts::RunBeforeUnloadDialog(content::WebContents* contents,
                                          content::RenderFrameHost* frame,
                                          bool is_reload,
                                          DialogClosedCallback callback) {
  Open(contents, frame, engine::JavaScriptDialogKind::kBeforeUnload, u"", u"", std::move(callback));
}

bool EnginePrompts::HandleJavaScriptDialog(content::WebContents* contents,
                                           bool accept,
                                           const std::u16string* prompt_override) {
  auto found = dialogs_.find(contents);
  if (found == dialogs_.end()) {
    return false;
  }
  Close(contents, found->second.id, accept, prompt_override ? *prompt_override : std::u16string(), /*settled=*/false);
  return true;
}

void EnginePrompts::CancelDialogs(content::WebContents* contents, bool reset_state) {
  if (auto found = dialogs_.find(contents); found != dialogs_.end()) {
    Close(contents, found->second.id, false, u"", /*settled=*/false);
  }
}

// A page shows one dialog at a time; a new one cancels the one before.
void EnginePrompts::Open(content::WebContents* contents,
                         content::RenderFrameHost* frame,
                         engine::JavaScriptDialogKind kind,
                         const std::u16string& message,
                         const std::u16string& default_text,
                         DialogClosedCallback callback) {
  CancelDialogs(contents, false);
  EnginePage* page = EngineBinding::Get().PageFor(contents);
  if (!page) {
    std::move(callback).Run(false, u"");
    return;
  }
  const engine::Guid id = RandomGuid();
  dialogs_[contents] = Dialog{.page = page->id(), .id = id, .callback = std::move(callback)};
  const GURL source = frame ? frame->GetLastCommittedURL() : contents->GetLastCommittedURL();
  report_.Run(engine::ScriptDialogOpened{.prompt_id = id,
                                         .page_id = page->id(),
                                         .question = {.kind = kind,
                                                      .message = base::UTF16ToUTF8(message),
                                                      .default_text = base::UTF16ToUTF8(default_text),
                                                      .source_url = PresentedURL(source)}});
}

void EnginePrompts::Close(content::WebContents* contents,
                          const engine::Guid& id,
                          bool accepted,
                          const std::u16string& input,
                          bool settled) {
  auto found = dialogs_.find(contents);
  if (found == dialogs_.end() || found->second.id != id) {
    return;
  }
  auto callback = std::move(found->second.callback);
  dialogs_.erase(found);
  if (!settled) {
    report_.Run(engine::PromptWithdrawn{.prompt_id = id});
  }
  std::move(callback).Run(accepted, input);
}

bool EnginePrompts::Settle(const engine::SettleScriptDialog& settlement) {
  for (auto& [contents, dialog] : dialogs_) {
    if (dialog.id == settlement.prompt_id) {
      Close(contents, settlement.prompt_id, settlement.accepted, base::UTF8ToUTF16(settlement.text.value_or("")),
            /*settled=*/true);
      return true;
    }
  }
  return false;
}

// HTTP authentication.

void EnginePrompts::Authenticate(const engine::Guid& page,
                                 const net::AuthChallengeInfo& challenge,
                                 int previous_failures,
                                 AuthenticationReply reply) {
  const engine::Guid id = RandomGuid();
  challenges_[id] = Challenge{.page = page, .reply = std::move(reply)};
  const GURL url = challenge.challenger.GetURL();
  report_.Run(engine::AuthenticationChallenged{
      .prompt_id = id,
      .page_id = page,
      .question = {.url = url.spec(),
                   .host = challenge.challenger.host(),
                   .port = challenge.challenger.port(),
                   .realm = challenge.realm.empty() ? std::nullopt : std::optional<std::string>(challenge.realm),
                   .scheme = challenge.scheme == "digest" ? engine::AuthenticationScheme::kDigest
                                                          : engine::AuthenticationScheme::kBasic,
                   .is_proxy = challenge.is_proxy,
                   .previous_failures = previous_failures}});
}

bool EnginePrompts::Settle(const engine::SettleAuthentication& settlement) {
  auto found = challenges_.find(settlement.prompt_id);
  if (found == challenges_.end()) {
    return false;
  }
  auto reply = std::move(found->second.reply);
  challenges_.erase(found);
  if (settlement.credential) {
    reply(true, base::UTF8ToUTF16(settlement.credential->username), base::UTF8ToUTF16(settlement.credential->password));
  } else {
    reply(false, u"", u"");
  }
  return true;
}

// Permission requests.

std::unique_ptr<permissions::PermissionPrompt> EnginePrompts::Prompt(
    const engine::Guid& page,
    permissions::PermissionPrompt::Delegate* delegate) {
  const auto permission = PermissionFor(delegate);
  if (!permission) {
    return nullptr;
  }
  const engine::Guid id = RandomGuid();
  auto prompt = std::make_unique<PermissionPrompt>(delegate, id, weak_factory_.GetWeakPtr());
  std::erase_if(permissions_, [](const auto& entry) { return !entry.second; });
  permissions_[id] = prompt->GetWeakPtr();
  report_.Run(engine::PermissionRequested{
      .prompt_id = id,
      .page_id = page,
      .question = {.permission = *permission,
                   .origin = SiteOriginOf(delegate->GetRequestingOrigin()),
                   .top_level_origin = SiteOriginOf(delegate->GetEmbeddingOrigin())}});
  return prompt;
}

bool EnginePrompts::Settle(const engine::SettlePermission& settlement) {
  if (auto share = shares_.find(settlement.prompt_id); share != shares_.end()) {
    auto reply = std::move(share->second.reply);
    shares_.erase(share);
    std::move(reply).Run(settlement.grants);
    return true;
  }
  auto found = permissions_.find(settlement.prompt_id);
  if (found == permissions_.end()) {
    return false;
  }
  base::WeakPtr<PermissionPrompt> prompt = found->second;
  permissions_.erase(found);
  if (!prompt) {
    return false;
  }
  prompt->Answer(settlement.grants, settlement.remembers);
  return true;
}

void EnginePrompts::Withdrawn(const engine::Guid& id) {
  if (permissions_.erase(id)) {
    report_.Run(engine::PromptWithdrawn{.prompt_id = id});
  }
}

// Screen sharing.

engine::Guid EnginePrompts::AskToShareScreen(const engine::Guid& page,
                                             const GURL& origin,
                                             const GURL& top_level_origin,
                                             ShareReply reply) {
  const engine::Guid id = RandomGuid();
  shares_[id] = Share{.page = page, .reply = std::move(reply)};
  report_.Run(engine::PermissionRequested{
      .prompt_id = id,
      .page_id = page,
      .question = {.permission = engine::SitePermission::kScreenSharing,
                   .origin = SiteOriginOf(origin),
                   .top_level_origin = SiteOriginOf(top_level_origin)}});
  return id;
}

void EnginePrompts::WithdrawShare(const engine::Guid& id) {
  if (shares_.erase(id)) {
    report_.Run(engine::PromptWithdrawn{.prompt_id = id});
  }
}

// Extension installs.

void EnginePrompts::AskToInstall(const engine::Guid& window,
                                 engine::ExtensionInstallQuestion question,
                                 InstallReply reply) {
  const engine::Guid id = RandomGuid();
  installs_[id] = std::move(reply);
  report_.Run(engine::ExtensionInstallRequested{.prompt_id = id, .window_id = window, .question = std::move(question)});
}

bool EnginePrompts::Settle(const engine::SettleExtensionInstall& settlement) {
  auto found = installs_.find(settlement.prompt_id);
  if (found == installs_.end()) {
    return false;
  }
  auto reply = std::move(found->second);
  installs_.erase(found);
  std::move(reply).Run(settlement.accepted, settlement.withholds_site_access);
  return true;
}

void EnginePrompts::Forget(const engine::Guid& page) {
  std::erase_if(challenges_, [&](const auto& entry) { return entry.second.page == page; });
  std::erase_if(shares_, [&](const auto& entry) { return entry.second.page == page; });
}

}  // namespace crest
