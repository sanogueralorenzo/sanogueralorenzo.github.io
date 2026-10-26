#include "chrome/browser/ui/crest/crest_engine_binding.h"

#include <algorithm>
#include <cstring>
#include <optional>
#include <type_traits>
#include <utility>
#include <variant>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/crest/crest_download_hooks.h"
#include "chrome/browser/ui/crest/crest_engine_agent.h"
#include "chrome/browser/download/download_confirmation_result.h"
#include "ui/shell_dialogs/selected_file_info.h"
#include "chrome/browser/ui/crest/crest_engine_browsers.h"
#include "chrome/browser/ui/crest/crest_engine_downloads.h"
#include "chrome/browser/ui/crest/crest_engine_extensions.h"
#include "chrome/browser/ui/crest/crest_engine_notifications.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "chrome/browser/ui/crest/crest_engine_profiles.h"
#include "chrome/browser/ui/crest/crest_engine_prompts.h"
#include "chrome/browser/ui/crest/crest_engine_screen_sharing.h"
#include "chrome/browser/ui/crest/crest_engine_tab_groups.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "components/prefs/pref_service.h"
#include "net/base/auth.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace crest {

namespace {

// Seconds from the Unix epoch to 1 January 2001, where the wire counts dates from.
constexpr double kReferenceDateOffset = 978307200;
// The longest link address the binding asks the core about or stages.
constexpr size_t kLinkBytes = 8192;
// The most links staged at once, and how long one waits for its Peek.
constexpr size_t kStagedLinks = 32;
constexpr base::TimeDelta kStagedLinkLifetime = base::Seconds(30);
// The modifier bits Blink records for a trusted click on a link, and those of
// them that make it a modified click: Command, Option or the middle button.
constexpr uint32_t kLinkCommand = 1;
constexpr uint32_t kLinkOption = 2;
constexpr uint32_t kLinkShift = 4;
constexpr uint32_t kLinkMiddleButton = 8;
constexpr uint32_t kLinkModified = kLinkCommand | kLinkOption | kLinkMiddleButton;
constexpr uint32_t kLinkModifiers = kLinkModified | kLinkShift;

// How a person followed a link: a trusted top-level click, with the keys and
// button Blink recorded.
engine::LinkGesture Clicked(uint32_t modifiers) {
  engine::ShortcutModifiers held = engine::ShortcutModifiers::kNone;
  if (modifiers & kLinkCommand) {
    held |= engine::ShortcutModifiers::kCommand;
  }
  if (modifiers & kLinkOption) {
    held |= engine::ShortcutModifiers::kOption;
  }
  if (modifiers & kLinkShift) {
    held |= engine::ShortcutModifiers::kShift;
  }
  return engine::LinkGesture{
      .user_activated = true, .top_level = true, .modifiers = held, .middle_click = (modifiers & kLinkMiddleButton) != 0};
}

// Whether the core's decision opens the link in Peek.
bool OpensPeek(engine::LinkNavigationDecision decision) {
  return decision == engine::LinkNavigationDecision::kPeekModifier ||
         decision == engine::LinkNavigationDecision::kPeekSavedSite;
}

// Crest's vault owns credentials in every window, so the engine's own password
// manager never saves, offers fills or shows its bubbles, in a private window
// as much as in a Space, whether or not a credential bridge is installed. A
// private profile keeps its preferences in memory and a private password
// store reads its original profile's settings, so both are turned off.
void DisableEnginePasswordManager(content::WebContents* contents) {
  auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  if (!profile) {
    return;
  }
  for (Profile* target : {profile, profile->GetOriginalProfile()}) {
    PrefService* prefs = target ? target->GetPrefs() : nullptr;
    if (prefs && prefs->GetBoolean(password_manager::prefs::kCredentialsEnableService)) {
      prefs->SetBoolean(password_manager::prefs::kCredentialsEnableService, false);
    }
  }
}

// Stops a person's plain click on a link in one of Crest's pages from loading
// when the core opens it in Peek instead, whether the link loads in its page
// or in a window of its own. Only an actual link can: forms, scripts,
// browser commands, subframes and redirects keep the engine's own handling.
class PeekLinkThrottle final : public content::NavigationThrottle {
 public:
  explicit PeekLinkThrottle(content::NavigationThrottleRegistry& registry) : NavigationThrottle(registry) {}
  const char* GetNameForLogging() override { return "CrestLinkNavigationThrottle"; }
  ThrottleCheckResult WillStartRequest() override {
    auto* navigation = navigation_handle();
    if (!navigation->IsInPrimaryMainFrame() || !navigation->IsRendererInitiated() || !navigation->HasUserGesture() ||
        navigation->IsFormSubmission() || navigation->WasStartedFromContextMenu() || navigation->IsPost() ||
        !navigation->GetURL().SchemeIsHTTPOrHTTPS() || navigation->GetURL().spec().size() > kLinkBytes) {
      return PROCEED;
    }
    EngineBinding& binding = EngineBinding::Get();
    if (navigation->WasInitiatedByLinkClick() &&
        binding.KeepsLinkForPeek(navigation->GetWebContents(), navigation->GetURL())) {
      return CANCEL_AND_IGNORE;
    }
    return binding.KeepsWindowLinkForPeek(*navigation) ? CANCEL_AND_IGNORE : PROCEED;
  }
};

}  // namespace

// The verified request of a link a person followed in `source`, and the
// document `source` showed then.
struct EngineBinding::StagedLink {
  content::OpenURLParams request;
  std::string source;
  uint64_t revision = 0;
  uint64_t generation = 0;
};

std::string GuidText(const engine::Guid& guid) {
  static constexpr char kDigits[] = "0123456789ABCDEF";
  std::string text;
  text.reserve(36);
  for (size_t index = 0; index < guid.size(); ++index) {
    if (index == 4 || index == 6 || index == 8 || index == 10) {
      text.push_back('-');
    }
    text.push_back(kDigits[guid[index] >> 4]);
    text.push_back(kDigits[guid[index] & 0x0f]);
  }
  return text;
}

std::optional<engine::Guid> ParseGuid(const std::string& text) {
  engine::Guid guid{};
  size_t digits = 0;
  for (size_t index = 0; index < text.size(); ++index) {
    const char character = text[index];
    if (index == 8 || index == 13 || index == 18 || index == 23) {
      if (character != '-') {
        return std::nullopt;
      }
      continue;
    }
    int value;
    if (character >= '0' && character <= '9') {
      value = character - '0';
    } else if (character >= 'a' && character <= 'f') {
      value = character - 'a' + 10;
    } else if (character >= 'A' && character <= 'F') {
      value = character - 'A' + 10;
    } else {
      return std::nullopt;
    }
    if (digits >= 32) {
      return std::nullopt;
    }
    guid[digits / 2] = static_cast<uint8_t>(guid[digits / 2] | (digits % 2 ? value : value << 4));
    ++digits;
  }
  if (digits != 32 || text.size() != 36) {
    return std::nullopt;
  }
  return guid;
}

// static
EngineBinding& EngineBinding::Get() {
  static base::NoDestructor<EngineBinding> binding;
  return *binding;
}

EngineBinding::EngineBinding() = default;
EngineBinding::~EngineBinding() = default;

crest_engine_binding_t EngineBinding::Table() {
  return crest_engine_binding_t{this, &EngineBinding::Attach, &EngineBinding::Run};
}

// static
const std::array<uint8_t, 32>& EngineBinding::Fingerprint() {
  return engine::kFingerprint;
}

crest_engine_pages_t EngineBinding::Pages() {
  return crest_engine_pages_t{this, &EngineBinding::Request, &EngineBinding::Release, &EngineBinding::PresentTo};
}

void EngineBinding::SetShell(Shell* shell) {
  shell_ = shell;
}

void EngineBinding::Dispose() {
  disposing_ = true;
  queue_.clear();
  due_.clear();
  if (tab_groups_) {
    tab_groups_->Clear();
  }
  offers_.clear();
  staged_links_.clear();
  extensions_.reset();
  prompts_.reset();
  notifications_.reset();
  downloads_.reset();
  Profiles().Dispose();
  for (auto& [key, page] : pages_) {
    page->Stop();
  }
  pages_.clear();
  // The profiles go once the Browsers, and every tab in them, are gone.
  Browsers().CloseAll();
  Profiles().ReleaseAll();
}

// The core's side.

// static
void CREST_CALL EngineBinding::Attach(void* context,
                                      uint64_t app,
                                      uint64_t engine,
                                      crest_engine_report_t report,
                                      crest_engine_ask_t ask) {
  auto* binding = static_cast<EngineBinding*>(context);
  binding->app_ = app;
  binding->engine_ = engine;
  binding->report_ = report;
  binding->ask_ = ask;
}

template <typename Question>
std::optional<typename engine::EngineQuestionAnswer<Question>::Type> EngineBinding::Ask(const Question& question) {
  using Answer = typename engine::EngineQuestionAnswer<Question>::Type;
  if (disposing_ || !ask_) {
    return std::nullopt;
  }
  const std::vector<uint8_t> asked = engine::Encode(engine::EngineQuestion{question});
  std::vector<uint8_t> answer;
  if (ask_(app_, engine_, asked.data(), asked.size(), &EngineBinding::Answered, &answer) != CREST_OK) {
    return std::nullopt;
  }
  return engine::Decode<Answer>(answer.data(), answer.size());
}

// static
void CREST_CALL EngineBinding::Answered(void* context, const uint8_t* answer, size_t length) {
  static_cast<std::vector<uint8_t>*>(context)->assign(answer, answer + length);
}

// static
void CREST_CALL EngineBinding::Run(void* context, const uint8_t* command, size_t length) {
  auto decoded = engine::Decode<engine::EngineCommand>(command, length);
  // The core and this binding registered against one engine contract, so a
  // command that does not decode is a build bug.
  CHECK(decoded) << "The core's engine command does not decode. Rebuild the engine.";
  auto* binding = static_cast<EngineBinding*>(context);
  // The core delivers on the thread that sent the intent or report that
  // caused a command, which is the UI thread; anything else waits for it.
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI)) {
    content::GetUIThreadTaskRunner({})->PostTask(
        FROM_HERE, base::BindOnce(&EngineBinding::Perform, binding->weak_factory_.GetWeakPtr(), std::move(*decoded)));
    return;
  }
  binding->Perform(std::move(*decoded));
}

void EngineBinding::Perform(engine::EngineCommand command) {
  if (disposing_) {
    return;
  }
  std::visit([this](const auto& message) { Handle(message); }, command);
}

void EngineBinding::Handle(const engine::CreatePage& command) {
  Create(command);
}

void EngineBinding::Handle(const engine::LoadPage& command) {
  // Every load replaces the identity an earlier one expected, so a load that
  // names no entry never commits one the core asked for before.
  if (EnginePage* page = Find(GuidText(command.page_id))) {
    page->ExpectEntry(command.entry_id);
  }
  Load(GuidText(command.page_id), command.url);
}

void EngineBinding::Handle(const engine::GoToHistoryEntry& command) {
  if (EnginePage* page = Find(GuidText(command.page_id))) {
    page->GoToEntry(command.entry_id);
  }
}

void EngineBinding::Handle(const engine::ClosePage& command) {
  Close(command);
}

void EngineBinding::Handle(const engine::RecoverPage& command) {
  if (EnginePage* page = Find(GuidText(command.page_id))) {
    page->Recover();
  }
}

void EngineBinding::Handle(const engine::ExitPictureInPicture& command) {
  if (EnginePage* page = Find(GuidText(command.page_id))) {
    page->ExitPictureInPicture();
  }
}

void EngineBinding::Handle(const engine::CheckBeforeUnload& command) {
  if (EnginePage* page = Find(GuidText(command.page_id))) {
    page->CheckBeforeUnload();
  } else {
    // A page the binding no longer holds has nothing to keep.
    Report(engine::BeforeUnloadAnswered{.page_id = command.page_id, .proceeds = true});
  }
}

void EngineBinding::Handle(const engine::SettleScriptDialog& command) {
  Prompts().Settle(command);
}

void EngineBinding::Handle(const engine::SettleAuthentication& command) {
  Prompts().Settle(command);
}

void EngineBinding::Handle(const engine::SettlePermission& command) {
  Prompts().Settle(command);
}

void EngineBinding::Handle(const engine::SettleExtensionInstall& command) {
  Prompts().Settle(command);
}

void EngineBinding::Handle(const engine::SettleDownloadDestination& command) {
  Downloads().Settle(command);
}

void EngineBinding::Handle(const engine::CancelEngineDownload& command) {
  Downloads().Cancel(command);
}

void EngineBinding::Handle(const engine::PauseEngineDownload& command) {
  Downloads().Pause(command);
}

void EngineBinding::Handle(const engine::ResumeEngineDownload& command) {
  Downloads().Resume(command);
}

void EngineBinding::Handle(const engine::RemoveEngineDownload& command) {
  Downloads().Remove(command);
}

void EngineBinding::Handle(const engine::ApproveEngineDownload& command) {
  Downloads().Approve(command);
}

void EngineBinding::Handle(const engine::EraseProfileData& command) {
  Erase(command);
}

void EngineBinding::Handle(const engine::EraseSiteData& command) {
  Erase(command);
}

void EngineBinding::Handle(const engine::EraseBrowsingData& command) {
  Erase(command);
}

void EngineBinding::Handle(const engine::ReadSiteData& command) {
  Read(command);
}

void EngineBinding::Handle(const engine::AdoptOfferedPage& command) {
  Adopt(command);
}

void EngineBinding::Handle(const engine::RejectOfferedPage& command) {
  Reject(command);
}

void EngineBinding::Handle(const engine::StageNavigation& command) {
  Stage(command);
}

void EngineBinding::Handle(const engine::GroupPages& command) {
  TabGroups().Apply(command);
}

void EngineBinding::Handle(const engine::DropStagedLink& command) {
  DropStagedLink(GuidText(command.staged_link_id));
}

// Creates the page's WebContents on a task of its own: the command arrives
// on the stack of whatever opened the page, and a page the engine offered
// may still claim it as its own first.
void EngineBinding::Create(const engine::CreatePage& creation) {
  const std::string key = GuidText(creation.page_id);
  if (pages_.contains(key)) {
    Report(engine::PageCreationFailed{.page_id = creation.page_id});
    return;
  }
  EnginePage& page = *pages_.emplace(key, std::make_unique<EnginePage>(*this, creation)).first->second;
  // A tab's page the core unloaded comes back with the history it had,
  // restored once the page exists.
  if (creation.restore_state) {
    page.Restore(creation.restore_state->state, creation.restore_state->url);
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineBinding::CreateNow, weak_factory_.GetWeakPtr(), key));
}

void EngineBinding::CreateNow(const std::string& key) {
  EnginePage* page = Find(key);
  if (!page || page->phase() != EnginePage::Phase::kCreating || !shell_ || disposing_) {
    return;
  }
  Profiles().Load(page->profile(), page->is_private(),
                  base::BindOnce(&EngineBinding::ProfileLoaded, weak_factory_.GetWeakPtr(), key));
}

// The page's profile loaded, or could not: a page that closed meanwhile gets
// nothing.
void EngineBinding::ProfileLoaded(const std::string& key, Profile* profile) {
  EnginePage* page = Find(key);
  if (!page || page->phase() != EnginePage::Phase::kCreating || !shell_ || disposing_) {
    return;
  }
  Created(key, profile ? Browsers().CreateContents(profile, page->profile(), page->window()) : nullptr);
}

void EngineBinding::Created(const std::string& key, content::WebContents* contents) {
  EnginePage* page = Find(key);
  if (!page || page->phase() != EnginePage::Phase::kCreating) {
    // The page closed while its profile loaded.
    if (contents) {
      DestroyContents(key, contents);
    }
    return;
  }
  if (!contents) {
    const engine::Guid id = page->id();
    pages_.erase(key);
    failed_.insert(key);
    Present(engine::PageViewUnavailable{.page_id = id});
    Report(engine::PageCreationFailed{.page_id = id});
    return;
  }
  Live(*page, contents);
}

// The page the core adopted is the WebContents the engine offered, in the
// profile it opened in, which stays in the Browser the engine opened it in
// until its view attaches in its own window. One that is gone, of another
// profile or in no Browser the binding keeps fails, and the WebContents,
// which no page follows, closes.
void EngineBinding::Adopt(const engine::AdoptOfferedPage& adoption) {
  const std::string key = GuidText(adoption.page_id);
  if (pages_.contains(key)) {
    Report(engine::PageCreationFailed{.page_id = adoption.page_id});
    return;
  }
  const std::string profile = GuidText(adoption.profile_id);
  auto offer = offers_.extract(GuidText(adoption.offer_id));
  content::WebContents* contents = offer ? offer.mapped().contents.get() : nullptr;
  if (!contents || offer.mapped().profile != profile || !Browsers().Holding(contents)) {
    if (contents) {
      Browsers().Destroy(contents);
    }
    failed_.insert(key);
    Present(engine::PageViewUnavailable{.page_id = adoption.page_id});
    Report(engine::PageCreationFailed{.page_id = adoption.page_id});
    return;
  }
  EnginePage& page = *pages_
                          .emplace(key, std::make_unique<EnginePage>(
                                            *this, engine::CreatePage{.page_id = adoption.page_id,
                                                                      .profile_id = adoption.profile_id,
                                                                      .is_private = adoption.is_private,
                                                                      .window_id = adoption.window_id,
                                                                      .restore_state = std::nullopt}))
                          .first->second;
  Live(page, contents);
}

// The page the core refused closes.
void EngineBinding::Reject(const engine::RejectOfferedPage& rejection) {
  auto offer = offers_.extract(GuidText(rejection.offer_id));
  if (offer && offer.mapped().contents) {
    Browsers().Destroy(offer.mapped().contents.get());
  }
}

// The link the core staged for the page's first load; one the page cannot
// take is dropped, and the page loads the address afresh.
void EngineBinding::Stage(const engine::StageNavigation& staging) {
  const std::string token = GuidText(staging.staged_link_id);
  EnginePage* page = Find(GuidText(staging.page_id));
  if (!page || !staged_links_.contains(token) || !page->Stage(token, staging.url)) {
    DropStagedLink(token);
  }
}

// The page has its WebContents: the platform hears its view is ready, the
// core hears the page is live, and then it loads what it was asked to.
void EngineBinding::Live(EnginePage& page, content::WebContents* contents) {
  DisableEnginePasswordManager(contents);
  page.Start(contents);
  Report(engine::PageCreated{.page_id = page.id()});
  page.LoadPending();
}

// A page closed keeping its state hands the core what brings it back.
void EngineBinding::Close(const engine::ClosePage& closing) {
  const std::string key = GuidText(closing.page_id);
  std::optional<engine::PageRestoreState> restore_state;
  content::WebContents* contents = nullptr;
  if (auto page = pages_.extract(key)) {
    contents = page.mapped()->web_contents();
    if (closing.keeps_state) {
      restore_state = page.mapped()->RestoreState();
    }
    if (auto token = page.mapped()->TakeStagedToken()) {
      DropStagedLink(*token);
    }
    page.mapped()->Stop();
  }
  DropStagedLinksFrom(key);
  failed_.erase(key);
  std::erase(due_, key);
  if (prompts_) {
    prompts_->Forget(closing.page_id);
  }
  if (notifications_) {
    notifications_->Forget(closing.page_id);
  }
  DestroyContents(key, contents);
  Report(engine::PageClosed{.page_id = closing.page_id, .restore_state = std::move(restore_state)});
}

void EngineBinding::PageLost(const std::string& key) {
  EnginePage* page = Find(key);
  if (!page) {
    return;
  }
  // The engine closed the page on its own authority, as an extension's
  // `chrome.tabs.remove` does; the core closes what owned it. The page is
  // still inside its own teardown, so it is let go of afterwards.
  Report(engine::PageClosed{.page_id = page->id(), .restore_state = std::nullopt});
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineBinding::Forget, weak_factory_.GetWeakPtr(), key));
}

void EngineBinding::Forget(const std::string& key) {
  EnginePage* page = Find(key);
  if (!page || page->phase() != EnginePage::Phase::kGone) {
    return;
  }
  if (auto token = page->TakeStagedToken()) {
    DropStagedLink(*token);
  }
  DropStagedLinksFrom(key);
  std::erase(due_, key);
  if (notifications_) {
    notifications_->Forget(page->id());
  }
  pages_.erase(key);
}

// Offered pages and links.

void EngineBinding::Offer(content::WebContents* contents,
                          const std::string& window,
                          const std::string& space,
                          bool foreground) {
  if (!contents || disposing_ || PageFor(contents)) {
    return;
  }
  std::erase_if(offers_, [](const auto& entry) { return !entry.second.contents; });
  for (const auto& [id, offered] : offers_) {
    if (offered.contents.get() == contents) {
      return;
    }
  }
  const std::string profile = Profiles().IdFor(contents->GetBrowserContext());
  const std::optional<engine::Guid> profile_id = ParseGuid(profile);
  if (!profile_id) {
    return;
  }
  std::optional<engine::Guid> source;
  if (content::RenderFrameHost* opener = contents->GetOpener()) {
    if (EnginePage* page = PageFor(content::WebContents::FromRenderFrameHost(opener))) {
      source = page->id();
    }
  }
  const engine::Guid offer = RandomGuid();
  offers_.emplace(GuidText(offer), OfferedPage{.contents = contents->GetWeakPtr(), .profile = profile});
  const GURL url = contents->GetVisibleURL();
  Report(engine::PageOffered{.offer_id = offer,
                             .profile_id = *profile_id,
                             .source_page_id = source,
                             .window_id = ParseGuid(window),
                             .space_id = space.empty() ? std::nullopt : ParseGuid(space),
                             .url = url.is_empty() ? std::string("about:blank") : PresentedURL(url),
                             .foreground = foreground});
}

bool EngineBinding::FollowModifiedLink(content::WebContents* contents, content::OpenURLParams& params) {
  EnginePage* page = PageFor(contents);
  if (!page || params.crest_link_modifiers > kLinkModifiers ||
      !(params.crest_link_modifiers & kLinkModified) || !params.is_renderer_initiated || !params.user_gesture ||
      params.triggering_event_info != blink::mojom::TriggeringEventInfo::kFromTrustedEvent ||
      params.started_from_context_menu || params.post_data || !params.url.SchemeIsHTTPOrHTTPS() ||
      params.url.spec().size() > kLinkBytes) {
    return false;
  }
  const auto answer = Ask(engine::LinkActivation{
      .page_id = page->id(), .url = PresentedURL(params.url), .gesture = Clicked(params.crest_link_modifiers)});
  if (!answer) {
    return false;
  }
  switch (answer->decision) {
    case engine::LinkNavigationDecision::kForegroundTab:
    case engine::LinkNavigationDecision::kBackgroundTab:
      // The engine opens the tab, which it offers to the core. Its first
      // load is no plain click's, so it never turns into a Peek.
      params.disposition = answer->decision == engine::LinkNavigationDecision::kForegroundTab
                               ? WindowOpenDisposition::NEW_FOREGROUND_TAB
                               : WindowOpenDisposition::NEW_BACKGROUND_TAB;
      params.crest_download_fallback = nullptr;
      if (routed_tabs_.empty()) {
        base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
            FROM_HERE, base::BindOnce(&EngineBinding::ForgetRoutedTabs, weak_factory_.GetWeakPtr()));
      }
      routed_tabs_.emplace_back(page->key(), params.url.spec());
      return false;
    case engine::LinkNavigationDecision::kPeekModifier:
      return StageForPeek(*page, params);
    case engine::LinkNavigationDecision::kNavigate:
    case engine::LinkNavigationDecision::kPeekSavedSite:
      return false;
  }
  return false;
}

bool EngineBinding::StageForPeek(EnginePage& page, content::OpenURLParams& params) {
  if (staged_links_.size() >= kStagedLinks) {
    return false;
  }
  params.crest_download_fallback = nullptr;
  const engine::Guid link = RandomGuid();
  const std::string token = GuidText(link);
  staged_links_.emplace(token, std::make_unique<StagedLink>(StagedLink{.request = params,
                                                                        .source = page.key(),
                                                                        .revision = page.navigation_revision(),
                                                                        .generation = page.navigation_generation()}));
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE, base::BindOnce(&EngineBinding::DropStagedLink, weak_factory_.GetWeakPtr(), token),
      kStagedLinkLifetime);
  PresentPeekSoon(page, engine::PeekRequested{.page_id = page.id(),
                                              .url = PresentedURL(params.url),
                                              .decision = engine::LinkNavigationDecision::kPeekModifier,
                                              .staged_link_id = link});
  return true;
}

bool EngineBinding::KeepsLinkForPeek(content::WebContents* contents, const GURL& url) {
  EnginePage* page = PageFor(contents);
  if (!page) {
    return false;
  }
  const auto answer = Ask(engine::LinkActivation{
      .page_id = page->id(), .url = PresentedURL(url), .gesture = {.user_activated = true, .top_level = true}});
  if (!answer || !OpensPeek(answer->decision)) {
    return false;
  }
  // Nothing is mounted or moved while Chromium's navigation stack is live.
  PresentPeekSoon(*page, engine::PeekRequested{
                             .page_id = page->id(), .url = PresentedURL(url), .decision = answer->decision});
  return true;
}

// The link opens a window of its own, as target="_blank" does: the engine
// made the window's WebContents and loads the link there first, before the
// core is offered the window. The page the link was in is the window's
// opener, or for a window opened without one, the navigation's initiator. A
// window that keeps its opener counts only for a link click, so a script's
// window.open keeps its window, as it does on WebKit.
bool EngineBinding::KeepsWindowLinkForPeek(content::NavigationHandle& navigation) {
  content::WebContents* contents = navigation.GetWebContents();
  if (!contents || disposing_ || PageFor(contents) || !contents->GetController().IsInitialNavigation() ||
      !ui::PageTransitionCoreTypeIs(navigation.GetPageTransition(), ui::PAGE_TRANSITION_LINK) ||
      std::any_of(offers_.begin(), offers_.end(),
                  [contents](const auto& entry) { return entry.second.contents.get() == contents; })) {
    return false;
  }
  content::RenderFrameHost* source_frame = contents->GetOpener();
  if (source_frame && !navigation.WasInitiatedByLinkClick()) {
    return false;
  }
  if (!source_frame && navigation.GetInitiatorFrameToken()) {
    source_frame = content::RenderFrameHost::FromFrameToken(
        content::GlobalRenderFrameHostToken(navigation.GetInitiatorProcessId(), *navigation.GetInitiatorFrameToken()));
  }
  content::WebContents* source_contents =
      source_frame ? content::WebContents::FromRenderFrameHost(source_frame) : nullptr;
  EnginePage* source = source_contents && source_contents != contents ? PageFor(source_contents) : nullptr;
  if (!source) {
    return false;
  }
  // A new tab a modified click asked for stays a tab.
  const auto routed = std::find(routed_tabs_.begin(), routed_tabs_.end(),
                                std::make_pair(source->key(), navigation.GetURL().spec()));
  if (routed != routed_tabs_.end()) {
    routed_tabs_.erase(routed);
    return false;
  }
  const std::string url = PresentedURL(navigation.GetURL());
  const auto answer = Ask(engine::LinkActivation{
      .page_id = source->id(), .url = url, .gesture = {.user_activated = true, .top_level = true}});
  if (!answer || !OpensPeek(answer->decision)) {
    return false;
  }
  // The window closes once Chromium's navigation stack has unwound.
  withheld_.push_back(contents->GetWeakPtr());
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineBinding::CloseWithheld, weak_factory_.GetWeakPtr(), contents->GetWeakPtr()));
  PresentPeekSoon(*source, engine::PeekRequested{.page_id = source->id(), .url = url, .decision = answer->decision});
  return true;
}

bool EngineBinding::Withholds(content::WebContents* contents) const {
  return contents && std::any_of(withheld_.begin(), withheld_.end(),
                                 [contents](const auto& held) { return held.get() == contents; });
}

void EngineBinding::CloseWithheld(base::WeakPtr<content::WebContents> contents) {
  std::erase_if(withheld_, [](const auto& held) { return !held; });
  if (contents && Browsers().Holding(contents.get())) {
    Browsers().Destroy(contents.get());
  }
}

void EngineBinding::ForgetRoutedTabs() {
  routed_tabs_.clear();
}

void EngineBinding::PresentPeekSoon(const EnginePage& page, engine::PeekRequested request) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineBinding::PresentPeek, weak_factory_.GetWeakPtr(), page.key(),
                                page.navigation_revision(), page.navigation_generation(), std::move(request)));
}

void EngineBinding::PresentPeek(const std::string& key,
                                uint64_t revision,
                                uint64_t generation,
                                engine::PeekRequested request) {
  EnginePage* page = Find(key);
  if (!disposing_ && page && page->web_contents() && page->navigation_revision() == revision &&
      page->navigation_generation() == generation) {
    Present(std::move(request));
    return;
  }
  if (request.staged_link_id) {
    DropStagedLink(GuidText(*request.staged_link_id));
  }
}

bool EngineBinding::LoadStagedLink(const std::string& key, const std::string& token, const GURL& url) {
  auto staged = staged_links_.extract(token);
  EnginePage* page = Find(key);
  if (!staged || !page || !page->web_contents() || disposing_) {
    return false;
  }
  const StagedLink& link = *staged.mapped();
  const EnginePage* source = Find(link.source);
  if (!source || !source->web_contents() || source->profile() != page->profile() ||
      source->window() != page->window() || source->navigation_revision() != link.revision ||
      source->navigation_generation() != link.generation || link.request.url != url ||
      !page->web_contents()->GetController().IsInitialNavigation()) {
    return false;
  }
  // Keeps Chromium's verified referrer, initiator, headers and SiteInstance.
  content::NavigationController::LoadURLParams load(link.request);
  page->web_contents()->GetController().LoadURLWithParams(load);
  return true;
}

void EngineBinding::DropStagedLink(const std::string& token) {
  staged_links_.erase(token);
}

void EngineBinding::DropStagedLinksFrom(const std::string& key) {
  std::erase_if(staged_links_, [&](const auto& entry) { return entry.second->source == key; });
}

// static
std::unique_ptr<content::NavigationThrottle> EngineBinding::LinkThrottle(
    content::NavigationThrottleRegistry& registry) {
  return std::make_unique<PeekLinkThrottle>(registry);
}

// The platform's side.

void EngineBinding::Load(const std::string& key, const std::string& url) {
  if (EnginePage* page = Find(key)) {
    page->Load(url);
  }
}

EnginePage* EngineBinding::PageFor(content::WebContents* contents) {
  if (!contents || disposing_) {
    return nullptr;
  }
  for (auto& [key, page] : pages_) {
    if (page->web_contents() == contents) {
      return page.get();
    }
  }
  return nullptr;
}

std::vector<EnginePage*> EngineBinding::LivePages() {
  std::vector<EnginePage*> live;
  if (disposing_) {
    return live;
  }
  for (auto& [key, page] : pages_) {
    if (page->web_contents()) {
      live.push_back(page.get());
    }
  }
  return live;
}

void EngineBinding::RefreshStoreListings() {
  if (disposing_) {
    return;
  }
  for (auto& [key, page] : pages_) {
    page->RefreshStore();
  }
}

void EngineBinding::DockInspector(const std::string& key, content::WebContents* frontend) {
  if (shell_ && !disposing_) {
    shell_->DockInspector(key, frontend);
  }
}

EngineDownloads& EngineBinding::Downloads() {
  if (!downloads_) {
    downloads_ = std::make_unique<EngineDownloads>(
        Profiles(), base::BindRepeating(&EngineBinding::Report, base::Unretained(this)),
        base::BindRepeating(
            [](EngineBinding* binding, download::DownloadItem* item) -> std::optional<engine::Guid> {
              EnginePage* page = binding->PageFor(content::DownloadItemUtils::GetWebContents(item));
              return page ? std::optional<engine::Guid>(page->id()) : std::nullopt;
            },
            base::Unretained(this)));
  }
  return *downloads_;
}

EngineProfiles& EngineBinding::Profiles() {
  if (!profiles_) {
    profiles_ = std::make_unique<EngineProfiles>();
  }
  return *profiles_;
}

EngineExtensions& EngineBinding::Extensions() {
  if (!extensions_) {
    extensions_ = std::make_unique<EngineExtensions>(
        base::BindRepeating(&EngineBinding::Present, base::Unretained(this)),
        base::BindRepeating(
            [](EngineBinding* binding, Profile* profile, const std::string& extension, std::optional<int> tab) {
              if (binding->shell_ && !binding->disposing_) {
                binding->shell_->RetractSidePanels(profile, extension, tab);
              }
            },
            base::Unretained(this)),
        base::BindRepeating(&EngineBinding::RefreshStoreListings, base::Unretained(this)));
  }
  return *extensions_;
}

EnginePrompts& EngineBinding::Prompts() {
  if (!prompts_) {
    prompts_ = std::make_unique<EnginePrompts>(base::BindRepeating(&EngineBinding::Report, base::Unretained(this)));
  }
  return *prompts_;
}

EngineNotifications& EngineBinding::Notifications() {
  if (!notifications_) {
    notifications_ =
        std::make_unique<EngineNotifications>(base::BindRepeating(&EngineBinding::Present, base::Unretained(this)));
  }
  return *notifications_;
}

std::unique_ptr<permissions::PermissionPrompt> EngineBinding::PermissionPrompt(
    content::WebContents* contents,
    permissions::PermissionPrompt::Delegate* delegate) {
  EnginePage* page = PageFor(contents);
  return page ? Prompts().Prompt(page->id(), delegate) : nullptr;
}

void EngineBinding::RequestSidePanel(const std::string& key,
                                     const std::string& extension,
                                     engine::SidePanelRequest request) {
  if (EnginePage* page = Find(key)) {
    Present(engine::SidePanelRequested{.page_id = page->id(), .extension_id = extension, .request = request});
  }
}

// The platform's direct path.

// static
crest_status_t CREST_CALL EngineBinding::Request(void* context, const uint8_t* request, size_t length,
                                                 crest_buffer_t* out) {
  if (!out) {
    return CREST_INVALID_ARGUMENT;
  }
  *out = crest_buffer_t{nullptr, 0};
  auto decoded = engine::Decode<engine::PageRequest>(request, length);
  if (!decoded) {
    return CREST_INVALID_MESSAGE;
  }
  const std::vector<uint8_t> answer = static_cast<EngineBinding*>(context)->Answer(*decoded);
  out->bytes = new uint8_t[answer.size()];
  out->length = answer.size();
  std::memcpy(out->bytes, answer.data(), answer.size());
  return CREST_OK;
}

// static
void CREST_CALL EngineBinding::Release(void*, crest_buffer_t* buffer) {
  if (!buffer) {
    return;
  }
  delete[] buffer->bytes;
  *buffer = crest_buffer_t{nullptr, 0};
}

// static
void CREST_CALL EngineBinding::PresentTo(void* context, crest_engine_present_t present, void* ui) {
  auto* binding = static_cast<EngineBinding*>(context);
  binding->present_ = present;
  binding->ui_ = ui;
}

// The page answers a request about it, or its agent what an agent asks. An
// agent's requests reach only pages of the persistent profiles the core let
// it use; the core and the platform decide which, never the page.
template <typename Request>
typename engine::PageRequestAnswer<Request>::Type EngineBinding::Handle(const Request& request) {
  using Nothing = typename engine::PageRequestAnswer<Request>::Type;
  EnginePage* page = Find(GuidText(request.page_id));
  if constexpr (requires(PageAgent& agent) { agent.Answer(request); }) {
    PageAgent* agent = page ? page->Agent() : nullptr;
    return agent ? agent->Answer(request) : Nothing{};
  } else {
    return page ? page->Answer(request) : Nothing{};
  }
}

// Hands each request to its own handler, which answers with the type the
// contract names for it.
std::vector<uint8_t> EngineBinding::Answer(const engine::PageRequest& request) {
  return std::visit(
      [this](const auto& message) {
        using Message = std::decay_t<decltype(message)>;
        auto answer = Handle(message);
        static_assert(std::is_same_v<decltype(answer), typename engine::PageRequestAnswer<Message>::Type>,
                      "A request answers with the type its contract names.");
        return engine::Encode(answer);
      },
      request);
}

bool EngineBinding::Handle(const engine::MovePageToWindow& request) {
  const std::string key = GuidText(request.page_id);
  EnginePage* page = Find(key);
  const std::string window = GuidText(request.window_id);
  if (!page || page->phase() != EnginePage::Phase::kLive ||
      !Browsers().MoveToWindow(page->web_contents(), page->profile(), window)) {
    return false;
  }
  page->set_window(window);
  return true;
}

// A page the platform comes to after the engine made it, or failed to,
// hears where it stands.
bool EngineBinding::Handle(const engine::WatchPage& request) {
  const std::string key = GuidText(request.page_id);
  if (EnginePage* page = Find(key)) {
    page->Watch();
    return true;
  }
  if (failed_.contains(key)) {
    Present(engine::PageViewUnavailable{.page_id = request.page_id});
    return true;
  }
  return false;
}

// The toolbar's actions for a page's own tab, and a Space's pinned ones with
// no page open.
engine::ExtensionActionList EngineBinding::Handle(const engine::PageExtensions& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  if (!page || !page->web_contents() || disposing_) {
    return engine::ExtensionActionList{};
  }
  return Extensions().PageActions(page->web_contents(), page->profile());
}

engine::ExtensionActionList EngineBinding::Handle(const engine::PinnedExtensions& request) {
  const std::string profile_id = GuidText(request.profile_id);
  Profile* profile = disposing_ ? nullptr : Profiles().Find(profile_id);
  return profile ? Extensions().Pinned(profile, profile_id) : engine::ExtensionActionList{};
}

engine::InstalledExtensionList EngineBinding::Handle(const engine::InstalledExtensions& request) {
  const std::string profile_id = GuidText(request.profile_id);
  Profile* profile = disposing_ ? nullptr : Profiles().Find(profile_id);
  return profile ? Extensions().Installed(profile, profile_id) : engine::InstalledExtensionList{};
}

bool EngineBinding::Handle(const engine::ChangeExtension& request) {
  Profile* profile = disposing_ ? nullptr : Profiles().Find(GuidText(request.profile_id));
  return profile && Extensions().Change(profile, request.extension_id, request.change);
}

engine::SidePanelScope EngineBinding::Handle(const engine::HasSidePanel& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page ? EngineExtensions::SidePanelScopeFor(page->web_contents(), request.extension_id)
              : engine::SidePanelScope::kUnavailable;
}

// Chromium enforces capture permissions itself: the SetSitePermission that
// withdraws a grant ends the capture it allowed.
bool EngineBinding::Handle(const engine::StopMediaCapture&) {
  return false;
}

bool EngineBinding::Handle(const engine::ChooseShareSource& request) {
  return AnswerShareChoice(request);
}

bool EngineBinding::Handle(const engine::StopTabSharing& request) {
  EnginePage* page = Find(GuidText(request.page_id));
  return page && StopTabSharing(page->web_contents());
}

bool EngineBinding::Handle(const engine::AnswerWebNotification& request) {
  return Notifications().Answer(request);
}

bool EngineBinding::Handle(const engine::AnswerProfileNotification& request) {
  return Notifications().Answer(request);
}

// A Space's profile loads before anything opens in it, so its extensions
// can be listed; its extensions are followed from then on.
bool EngineBinding::Handle(const engine::PrepareProfile& request) {
  if (disposing_) {
    return false;
  }
  const std::string id = GuidText(request.profile_id);
  Profiles().Prepare(id, base::BindOnce(
                             [](base::WeakPtr<EngineBinding> binding, std::string id, engine::Guid preparation,
                                bool ready) {
                               if (!binding) {
                                 return;
                               }
                               if (ready) {
                                 binding->Extensions().For(binding->Profiles().Find(id), id);
                               }
                               binding->Present(engine::ProfilePrepared{.preparation_id = preparation, .ready = ready});
                             },
                             weak_factory_.GetWeakPtr(), id, request.preparation_id));
  return true;
}

// Its pages, Browsers and extensions go at once; its data after, loaded
// from disk when nothing had loaded it.
void EngineBinding::Erase(const engine::EraseProfileData& erasing) {
  const std::string id = GuidText(erasing.profile_id);
  if (!Profiles().BeginDeletion(id, erasing.ephemeral)) {
    Report(engine::DataErased{.erasure_id = erasing.erasure_id, .erased = false});
    return;
  }
  if (shell_) {
    shell_->ReleaseProfile(id);
  }
  // Its pages close first, each with the views beside it, then its Browsers.
  std::vector<std::string> closing;
  for (const auto& [key, page] : pages_) {
    if (page->profile() == id && page->web_contents()) {
      closing.push_back(key);
    }
  }
  for (const std::string& key : closing) {
    DestroyPage(key);
  }
  ReleaseProfile(id);
  Present(engine::ProfileReleased{.profile_id = erasing.profile_id});
  Profiles().Delete(id, erasing.ephemeral,
                    base::BindOnce(
                        [](base::WeakPtr<EngineBinding> binding, engine::Guid erasure, bool erased) {
                          if (binding) {
                            binding->Report(engine::DataErased{.erasure_id = erasure, .erased = erased});
                          }
                        },
                        weak_factory_.GetWeakPtr(), erasing.erasure_id));
}

// A private profile keeps a site's data only while it is open; a regular one
// on disk is loaded to clear it, and one never created has nothing to clear.
void EngineBinding::Erase(const engine::EraseSiteData& erasing) {
  WithStoredData(GuidText(erasing.profile_id), erasing.ephemeral,
                 base::BindOnce(
                     [](std::vector<std::string> hosts, std::vector<engine::BrowsingDataCategory> categories,
                        base::OnceCallback<void(bool)> done, Profile* profile, bool kept) {
                       if (!profile) {
                         std::move(done).Run(!kept);
                         return;
                       }
                       crest::SiteData::Clear(profile, hosts, categories, std::move(done));
                     },
                     erasing.hosts, erasing.categories, ErasureAnswer(erasing.erasure_id)));
}

// What changed in a time range goes the way a site's data does.
void EngineBinding::Erase(const engine::EraseBrowsingData& erasing) {
  std::optional<base::Time> since;
  if (erasing.since) {
    since = base::Time::FromSecondsSinceUnixEpoch(erasing.since->seconds_since_2001 + kReferenceDateOffset);
  }
  WithStoredData(GuidText(erasing.profile_id), erasing.ephemeral,
                 base::BindOnce(
                     [](std::optional<base::Time> since, std::vector<engine::BrowsingDataCategory> categories,
                        base::OnceCallback<void(bool)> done, Profile* profile, bool kept) {
                       if (!profile) {
                         std::move(done).Run(!kept);
                         return;
                       }
                       crest::SiteData::Clear(profile, since, categories, std::move(done));
                     },
                     since, erasing.categories, ErasureAnswer(erasing.erasure_id)));
}

// A profile that keeps nothing lists no site; one that would not load could
// list none of its own.
void EngineBinding::Read(const engine::ReadSiteData& reading) {
  auto answer = base::BindOnce(
      [](base::WeakPtr<EngineBinding> binding, engine::Guid id, bool read, std::vector<engine::StoredSite> sites) {
        if (binding) {
          binding->Report(engine::SiteDataRead{.reading_id = id, .sites = std::move(sites), .read = read});
        }
      },
      weak_factory_.GetWeakPtr(), reading.reading_id);
  WithStoredData(GuidText(reading.profile_id), reading.ephemeral,
                 base::BindOnce(
                     [](base::OnceCallback<void(bool, std::vector<engine::StoredSite>)> answer, Profile* profile,
                        bool kept) {
                       if (!profile) {
                         std::move(answer).Run(!kept, {});
                         return;
                       }
                       crest::SiteData::Read(profile, base::BindOnce(std::move(answer), true));
                     },
                     std::move(answer)));
}

void EngineBinding::WithStoredData(const std::string& id,
                                   bool ephemeral,
                                   base::OnceCallback<void(Profile*, bool)> use) {
  if (Profile* loaded = Profiles().Find(id)) {
    std::move(use).Run(loaded, true);
    return;
  }
  if (ephemeral || !Profiles().HasStore(id)) {
    std::move(use).Run(nullptr, false);
    return;
  }
  Profiles().Load(id, /*is_private=*/false,
                  base::BindOnce([](base::OnceCallback<void(Profile*, bool)> use,
                                    Profile* profile) { std::move(use).Run(profile, true); },
                                 std::move(use)));
}

base::OnceCallback<void(bool)> EngineBinding::ErasureAnswer(const engine::Guid& erasure) {
  return base::BindOnce(
      [](base::WeakPtr<EngineBinding> binding, engine::Guid erasure, bool erased) {
        if (binding) {
          binding->Report(engine::DataErased{.erasure_id = erasure, .erased = erased});
        }
      },
      weak_factory_.GetWeakPtr(), erasure);
}

// Reports and presentations.

void EngineBinding::Report(engine::EngineEvent event) {
  if (disposing_ || !report_) {
    return;
  }
  queue_.push_back(Outgoing{.to_core = true, .message = engine::Encode(event)});
  ScheduleFlush();
}

void EngineBinding::Present(engine::EnginePresentation presentation) {
  if (disposing_ || !present_) {
    return;
  }
  queue_.push_back(Outgoing{.to_core = false, .message = engine::Encode(presentation)});
  ScheduleFlush();
}

void EngineBinding::ReportTabGroupsSoon() {
  if (!disposing_) {
    ScheduleFlush();
  }
}

void EngineBinding::ReportStateSoon(const std::string& key) {
  if (disposing_) {
    return;
  }
  if (std::find(due_.begin(), due_.end(), key) == due_.end()) {
    due_.push_back(key);
  }
  ScheduleFlush();
}

void EngineBinding::ScheduleFlush() {
  if (flush_posted_ || flushing_) {
    return;
  }
  flush_posted_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&EngineBinding::Flush, weak_factory_.GetWeakPtr()));
}

// Sends what is queued, oldest first, then the tab groups an extension
// changed, then the snapshots due this turn. A report can make the core
// deliver a command, which can queue more; those go out in the same pass. A
// group is reported after its pages, so the core knows the pages it names.
void EngineBinding::Flush() {
  flush_posted_ = false;
  flushing_ = true;
  while (!disposing_ && (!queue_.empty() || (tab_groups_ && tab_groups_->HasDue()) || !due_.empty())) {
    if (queue_.empty() && tab_groups_ && tab_groups_->HasDue()) {
      tab_groups_->ReportDue();
      continue;
    }
    if (queue_.empty()) {
      std::vector<std::string> due = std::move(due_);
      due_.clear();
      for (const std::string& key : due) {
        if (EnginePage* page = Find(key)) {
          page->ReportState();
        }
      }
      continue;
    }
    Outgoing next = std::move(queue_.front());
    queue_.pop_front();
    if (!next.to_core) {
      if (present_) {
        present_(ui_, next.message.data(), next.message.size());
      }
      continue;
    }
    const crest_status_t status = report_(app_, engine_, next.message.data(), next.message.size());
    // A report is never refused; any other answer is a build bug.
    DCHECK(status == CREST_OK || status == CREST_INVALID_HANDLE) << "The core refused an engine report: " << status;
  }
  flushing_ = false;
}

EnginePage* EngineBinding::Find(const std::string& key) {
  auto found = pages_.find(key);
  return found == pages_.end() ? nullptr : found->second.get();
}

void EngineBinding::DestroyPage(const std::string& key) {
  EnginePage* page = Find(key);
  if (content::WebContents* contents = page ? page->web_contents() : nullptr) {
    DestroyContents(key, contents);
  }
}

void EngineBinding::DestroyContents(const std::string& key, content::WebContents* contents) {
  if (shell_) {
    shell_->ReleasePage(key);
  }
  Browsers().Destroy(contents);
}

void EngineBinding::ReleaseProfile(const std::string& id) {
  if (disposing_) {
    return;
  }
  // Pages still offered to the core close with their Browsers.
  if (Profile* profile = Profiles().Find(id)) {
    Browsers().CloseProfile(profile);
  }
  Extensions().Forget(id);
  Profiles().Release(id);
}

EngineBrowsers& EngineBinding::Browsers() {
  if (!browsers_) {
    browsers_ = std::make_unique<EngineBrowsers>(*this);
  }
  return *browsers_;
}

EngineTabGroups& EngineBinding::TabGroups() {
  if (!tab_groups_) {
    tab_groups_ = std::make_unique<EngineTabGroups>(*this);
  }
  return *tab_groups_;
}

// The engine's own hooks, for the pages that follow the WebContents they name.

void ReportContentFullscreen(content::WebContents* contents, bool active) {
  if (EnginePage* page = EngineBinding::Get().PageFor(contents)) {
    page->FullscreenChanged(active);
  }
}

bool ReturnFromPictureInPicture(content::WebContents* contents) {
  EnginePage* page = IsEnabled() && contents ? EngineBinding::Get().PageFor(contents) : nullptr;
  return page && page->ReturnFromPictureInPicture();
}

void UpdateTargetURL(content::WebContents* contents, const GURL& url) {
  if (EnginePage* page = EngineBinding::Get().PageFor(contents)) {
    page->HoverChanged(url);
  }
}

void UpdateSiteIndicators(content::WebContents* contents) {
  if (EnginePage* page = EngineBinding::Get().PageFor(contents)) {
    page->SiteIndicatorsChanged();
  }
}

// Extension side panels are cards beside Crest's pages, so this build never
// creates Chrome's Views side-panel UI: `chrome.sidePanel.open()` and
// `close()` are asked of the page that shows `contents`. False leaves a
// WebContents no Crest page shows to the engine.
bool OpenExtensionSidePanel(content::WebContents* contents, const std::string& extension_id) {
  EnginePage* page = EngineBinding::Get().PageFor(contents);
  if (!page) {
    return false;
  }
  EngineBinding::Get().RequestSidePanel(page->key(), extension_id, engine::SidePanelRequest::kOpen);
  return true;
}

bool CloseExtensionSidePanel(content::WebContents* contents, const std::string& extension_id) {
  EnginePage* page = EngineBinding::Get().PageFor(contents);
  if (!page) {
    return false;
  }
  EngineBinding::Get().RequestSidePanel(page->key(), extension_id, engine::SidePanelRequest::kClose);
  return true;
}

// Crest shows script dialogs for its pages with the same presenter WebKit's
// pages use. Other engine pages keep the engine's dialog manager.
content::JavaScriptDialogManager* JavaScriptDialogManagerFor(content::WebContents* contents) {
  return EngineBinding::Get().PageFor(contents) ? &EngineBinding::Get().Prompts() : nullptr;
}

// Basic and Digest challenges go through Crest's per-Space credentials. False
// leaves a WebContents Crest does not show, a proxy's challenge or another
// scheme to the engine.
bool PresentHTTPAuthentication(content::WebContents* contents,
                               const net::AuthChallengeInfo& challenge,
                               std::function<void(bool, const std::u16string&, const std::u16string&)> reply) {
  EnginePage* page = EngineBinding::Get().PageFor(contents);
  if (!page || challenge.is_proxy || (challenge.scheme != "basic" && challenge.scheme != "digest")) {
    return false;
  }
  const int previous_failures = page->AuthenticationAttempt(challenge.challenger.GetURL().spec() + "\n" +
                                                            challenge.scheme + "\n" + challenge.realm);
  EngineBinding::Get().Prompts().Authenticate(page->id(), challenge, previous_failures, std::move(reply));
  return true;
}

// Downloads in Crest's profiles are Crest's to show; the rest stay the engine's.
bool OwnsDownload(download::DownloadItem* item) {
  auto& binding = EngineBinding::Get();
  return !binding.disposing() && binding.Downloads().Owns(item);
}

void PublishDownload(download::DownloadItem* item) {
  auto& binding = EngineBinding::Get();
  if (!binding.disposing()) {
    binding.Downloads().Changed(item);
  }
}

void ChooseDownloadDestination(download::DownloadItem* item,
                               const base::FilePath& suggested_path,
                               DownloadConfirmationReason reason,
                               DownloadTargetDeterminerDelegate::ConfirmationCallback callback) {
  auto& binding = EngineBinding::Get();
  if (binding.disposing()) {
    std::move(callback).Run(DownloadConfirmationResult::CANCELED, ui::SelectedFileInfo());
    return;
  }
  binding.Downloads().ChooseDestination(item, suggested_path, reason, std::move(callback));
}

bool CanDockDevTools(content::WebContents* inspected) {
  return EngineBinding::Get().PageFor(inspected) != nullptr;
}

bool UpdateDockedDevTools(content::WebContents* inspected) {
  EnginePage* page = EngineBinding::Get().PageFor(inspected);
  if (!page) {
    return false;
  }
  page->InspectorChanged();
  return true;
}

void OnDevToolsClosing(content::WebContents* inspected) {
  if (EnginePage* page = EngineBinding::Get().PageFor(inspected)) {
    page->InspectorClosing();
  }
}

bool AnswerBeforeUnload(content::WebContents* contents, bool proceed) {
  EnginePage* page = EngineBinding::Get().PageFor(contents);
  return page && page->AnswerBeforeUnload(proceed);
}

bool RequestPageClose(content::WebContents* contents) {
  EnginePage* page = IsEnabled() && contents ? EngineBinding::Get().PageFor(contents) : nullptr;
  if (!page) {
    return false;
  }
  page->RequestClose();
  return true;
}

bool KeepsPageResident(content::WebContents* contents) {
  return IsEnabled() && contents && EngineBinding::Get().PageFor(contents);
}

bool KeepsPageLoaded(content::WebContents* contents) {
  EnginePage* page = IsEnabled() && contents ? EngineBinding::Get().PageFor(contents) : nullptr;
  return page && page->MediaActivity() != engine::PageMediaActivity::kNone;
}

// A modified click the core sends to a tab or to Peek. Any other, in a page
// Crest does not show or one the core leaves to the engine, keeps Chromium's
// own path, including an Option-click's original renderer download with
// Chromium's download validation and restrictions.
bool RouteModifiedLink(content::WebContents* source, content::OpenURLParams& params) {
  if (!IsEnabled() || !params.crest_link_modifiers) {
    return false;
  }
  if (EngineBinding::Get().FollowModifiedLink(source, params)) {
    return true;
  }
  if (params.disposition == WindowOpenDisposition::SAVE_TO_DISK && params.crest_download_fallback &&
      params.crest_download_fallback->data) {
    std::move(params.crest_download_fallback->data).Run();
    return true;
  }
  return false;
}

}  // namespace crest
