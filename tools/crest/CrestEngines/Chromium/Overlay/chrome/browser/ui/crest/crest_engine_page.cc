#include "chrome/browser/ui/crest/crest_engine_page.h"

#include <os/log.h>
#include <os/signpost.h>

#include <algorithm>
#include <cmath>
#include <set>
#include <utility>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/memory/ref_counted_memory.h"
#include "base/pickle.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/uuid.h"
#include "chrome/browser/ui/crest/crest_engine_agent.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_content.h"
#include "chrome/browser/ui/crest/crest_engine_documents.h"
#include "chrome/browser/ui/crest/crest_engine_infobars.h"
#include "chrome/browser/ui/crest/crest_engine_inspector.h"
#include "chrome/browser/ui/crest/crest_engine_media.h"
#include "chrome/browser/ui/crest/crest_engine_prompts.h"
#include "chrome/browser/ui/crest/crest_engine_store.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"
#include "components/blocked_content/popup_blocker_tab_helper.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "content/public/browser/ssl_status.h"
#include "net/cert/x509_certificate.h"
#include "net/cert/x509_util.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/security_state/core/security_state.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/favicon_status.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "components/zoom/zoom_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/page.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/restore_type.h"
#include "content/public/browser/web_contents.h"
#include "net/base/net_errors.h"
#include "net/base/schemeful_site.h"
#include "net/cert/cert_status_flags.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/page_transition_types.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/gfx/skia_util.h"
#include "url/gurl.h"

namespace crest {

namespace {

constexpr char kEngineScheme[] = "chrome://";
constexpr char kCrestScheme[] = "crest://";

// The saved navigation history's own spelling, and its limits: the entries a
// page may keep, the bytes one entry may take and the bytes of the whole.
// The second spelling keeps each entry's identity after it; the first, which
// pages saved before entries had one, still restores, and its entries take
// new identities.
constexpr char kInteractionStateMagic[] = "crest.navigation.v2";
constexpr char kInteractionStateMagicWithoutIds[] = "crest.navigation.v1";
constexpr int kInteractionStateEntries = 100;
constexpr size_t kInteractionStateEntryBytes = 64 * 1024;
constexpr size_t kInteractionStateBytes = 2 * 1024 * 1024;
// The largest icon image the page reports.
constexpr size_t kIconBytes = 512 * 1024;
// The scale the page reports its icon at. Crest draws tab icons at 18 points
// or more, so Chromium's 1x favicon, 16 pixels, blurs on a Retina display.
constexpr float kIconScale = 2.0f;
// The longest edge, in pixels, the page fetches its icon again at. Larger
// sidebars draw tab icons at up to 27 points, more than the 2x favicon's 32
// pixels fill on a Retina display.
constexpr int kIconPixels = 64;
// The key systems a page asks for by name that another engine plays through
// the platform: Widevine and every PlayReady variant.
constexpr std::string_view kWidevinePrefix = "com.widevine.alpha";
constexpr std::string_view kPlayReadyPrefix = "com.microsoft.playready";
// The zoom factors a page takes.
constexpr double kMinimumZoom = 0.25;
constexpr double kMaximumZoom = 5;
// The widest capture, in points, and how long the compositor has to answer.
constexpr double kMaximumCaptureWidth = 16384;
constexpr base::TimeDelta kCaptureTimeout = base::Seconds(2);

// Where reading and reporting a page's history shows in Instruments.
os_log_t HistoryLog() {
  static os_log_t log = os_log_create("com.pauldavis.crest", "PageHistory");
  return log;
}

engine::Guid NewEntryId() {
  return *ParseGuid(base::Uuid::GenerateRandomV4().AsLowercaseString());
}

std::string ReplacingScheme(std::string_view value, std::string_view from, std::string_view to) {
  if (value.size() < from.size() ||
      !base::EqualsCaseInsensitiveASCII(value.substr(0, from.size()), from)) {
    return std::string(value);
  }
  // Escaped paths, queries and fragments stay as they are, byte for byte.
  return std::string(to) + std::string(value.substr(from.size()));
}

// Why a navigation failed, by Chromium's `net::Error` code, in the terms both
// engines report.
engine::NavigationError NavigationErrorFor(int code) {
  if (code <= net::ERR_CERT_COMMON_NAME_INVALID && code >= -299) {
    return engine::NavigationError::kSecureConnectionFailed;
  }
  switch (code) {
    case net::ERR_INTERNET_DISCONNECTED:
      return engine::NavigationError::kOffline;
    case net::ERR_TIMED_OUT:
    case net::ERR_CONNECTION_TIMED_OUT:
      return engine::NavigationError::kTimedOut;
    case net::ERR_NAME_NOT_RESOLVED:
    case net::ERR_NAME_RESOLUTION_FAILED:
      return engine::NavigationError::kCannotFindServer;
    case net::ERR_CONNECTION_REFUSED:
    case net::ERR_CONNECTION_FAILED:
    case net::ERR_ADDRESS_UNREACHABLE:
      return engine::NavigationError::kCannotConnect;
    case net::ERR_CONNECTION_CLOSED:
    case net::ERR_CONNECTION_RESET:
    case net::ERR_CONNECTION_ABORTED:
    case net::ERR_NETWORK_CHANGED:
      return engine::NavigationError::kConnectionLost;
    case net::ERR_SSL_PROTOCOL_ERROR:
    case net::ERR_SSL_VERSION_OR_CIPHER_MISMATCH:
      return engine::NavigationError::kSecureConnectionFailed;
    case net::ERR_TOO_MANY_REDIRECTS:
      return engine::NavigationError::kTooManyRedirects;
    case net::ERR_INVALID_URL:
    case net::ERR_DISALLOWED_URL_SCHEME:
    case net::ERR_UNKNOWN_URL_SCHEME:
      return engine::NavigationError::kUnsupportedAddress;
    case net::ERR_BLOCKED_BY_CLIENT:
    case net::ERR_BLOCKED_BY_ADMINISTRATOR:
    case net::ERR_BLOCKED_BY_RESPONSE:
      return engine::NavigationError::kBlocked;
    default:
      return engine::NavigationError::kUnknown;
  }
}

// Whether two addresses name the same document: they are equal, or differ
// only in their fragments.
bool SameDocument(const GURL& lhs, const GURL& rhs) {
  return lhs == rhs || (lhs.is_valid() && rhs.is_valid() && lhs.GetWithoutRef() == rhs.GetWithoutRef());
}

// An icon image's longest edge, in pixels.
int IconPixels(const SkBitmap& bitmap) {
  return std::max(bitmap.width(), bitmap.height());
}

}  // namespace

std::string PresentedURL(const GURL& url) {
  return ReplacingScheme(url.possibly_invalid_spec(), kEngineScheme, kCrestScheme);
}

GURL EngineURL(const std::string& url) {
  return GURL(ReplacingScheme(url, kCrestScheme, kEngineScheme));
}

EnginePage::EnginePage(EngineBinding& binding, const engine::CreatePage& creation)
    : binding_(binding),
      id_(creation.page_id),
      key_(GuidText(creation.page_id)),
      profile_(GuidText(creation.profile_id)),
      is_private_(creation.is_private),
      window_(GuidText(creation.window_id)) {}

EnginePage::~EnginePage() {
  Stop();
}

void EnginePage::Start(content::WebContents* contents) {
  Observe(contents);
  phase_ = Phase::kLive;
  if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(contents)) {
    driver->AddObserver(this);
  }
  find_helper_ = find_in_page::FindTabHelper::FromWebContents(contents);
  if (find_helper_) {
    find_helper_->AddObserver(this);
  }
  const auto present = base::BindRepeating(&EnginePage::Present, weak_factory_.GetWeakPtr());
  Present(engine::PageViewReady{.page_id = id_});
  media_ = std::make_unique<PageMedia>(contents, id_, present,
                                       base::BindRepeating(&EnginePage::StateChanged, weak_factory_.GetWeakPtr()));
  infobars_ = std::make_unique<PageInfoBars>(contents, id_, present);
  inspector_ = std::make_unique<PageInspector>(
      contents, id_, present, base::BindRepeating(&EngineBinding::DockInspector, base::Unretained(&*binding_), key_));
  content_ = std::make_unique<PageContent>(contents, id_, present);
  store_ = std::make_unique<PageStore>(contents, id_, present);
  ApplyZoom();
  UpdateTheme();
  // An agent that asked while the page was being made sees its first load.
  if (observes_activity_) {
    Agent()->ObserveActivity(true);
  }
  StateChanged();
}

void EnginePage::Stop() {
  settle_timer_.Stop();
  agent_.reset();
  documents_.reset();
  store_.reset();
  content_.reset();
  inspector_.reset();
  infobars_.reset();
  media_.reset();
  if (find_helper_) {
    find_helper_->RemoveObserver(this);
    find_helper_ = nullptr;
  }
  if (web_contents()) {
    if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents())) {
      driver->RemoveObserver(this);
    }
  }
  Observe(nullptr);
}

// Loads the app asks for.

void EnginePage::Load(const std::string& url) {
  if (staged_ && staged_->url != url) {
    binding_->DropStagedLink(staged_->token);
    staged_.reset();
  }
  // A load of its own replaces history the page was about to restore.
  pending_state_.reset();
  pending_url_ = url;
  StateChanged();
  pending_load_ = url;
  if (phase_ == Phase::kLive) {
    LoadPending();
  }
}

bool EnginePage::Stage(const std::string& token, const std::string& url) {
  if (phase_ != Phase::kCreating || staged_) {
    return false;
  }
  staged_ = StagedNavigation{token, url};
  return true;
}

bool EnginePage::Restore(std::vector<uint8_t> state, const std::string& expected_url) {
  if (phase_ == Phase::kLive) {
    return RestoreNow(state, expected_url);
  }
  if (phase_ != Phase::kCreating) {
    return false;
  }
  pending_load_ = expected_url;
  pending_state_ = std::move(state);
  return true;
}

void EnginePage::LoadPending() {
  if (!pending_load_) {
    return;
  }
  const std::string url = std::move(*pending_load_);
  pending_load_.reset();
  if (staged_) {
    StagedNavigation staged = std::move(*staged_);
    staged_.reset();
    pending_state_.reset();
    // A stale link is never retried as a bare address, which would lose the
    // initiating frame's security and referrer.
    if (!binding_->LoadStagedLink(key_, staged.token, EngineURL(url))) {
      expected_entry_id_.reset();
      Interrupted();
      Report(engine::StagedLinkUnavailable{.page_id = id_});
    }
    return;
  }
  if (pending_state_) {
    std::vector<uint8_t> state = std::move(*pending_state_);
    pending_state_.reset();
    if (RestoreNow(state, url)) {
      return;
    }
  }
  Navigate(url);
}

std::optional<std::string> EnginePage::TakeStagedToken() {
  if (!staged_) {
    return std::nullopt;
  }
  std::string token = std::move(staged_->token);
  staged_.reset();
  return token;
}

void EnginePage::Navigate(const std::string& url) {
  const GURL target = EngineURL(url);
  if (!web_contents() || !target.is_valid()) {
    // No navigation starts to take the identity the load expected.
    expected_entry_id_.reset();
    return;
  }
  web_contents()->GetController().LoadURL(target, content::Referrer(), ui::PAGE_TRANSITION_TYPED,
                                          std::string());
}

// Navigation history.

std::optional<std::vector<uint8_t>> EnginePage::SaveInteractionState() {
  if (!web_contents()) {
    return std::nullopt;
  }
  auto& controller = web_contents()->GetController();
  if (controller.IsInitialNavigation() || !controller.GetLastCommittedEntry() ||
      controller.GetEntryCount() > kInteractionStateEntries || controller.GetLastCommittedEntryIndex() < 0) {
    return std::nullopt;
  }
  base::Pickle pickle;
  pickle.WriteString(kInteractionStateMagic);
  pickle.WriteString(profile_);
  pickle.WriteInt(controller.GetLastCommittedEntryIndex());
  pickle.WriteInt(controller.GetEntryCount());
  for (int index = 0; index < controller.GetEntryCount(); ++index) {
    auto navigation =
        sessions::ContentSerializedNavigationBuilder::FromNavigationEntry(index, controller.GetEntryAtIndex(index));
    base::Pickle entry;
    // Chromium's session serializer leaves out password data.
    navigation.WriteToPickle(kInteractionStateEntryBytes, &entry);
    pickle.WriteData(entry.AsBytes());
    const engine::Guid id = EntryId(controller.GetEntryAtIndex(index));
    pickle.WriteData(base::span(id));
    if (pickle.AsBytes().size() > kInteractionStateBytes) {
      return std::nullopt;
    }
  }
  const auto bytes = pickle.AsBytes();
  return std::vector<uint8_t>(bytes.begin(), bytes.end());
}

std::optional<engine::PageRestoreState> EnginePage::RestoreState() {
  std::optional<std::vector<uint8_t>> state = SaveInteractionState();
  if (!state) {
    return std::nullopt;
  }
  // `RestoreNow` checks the selected entry against this address.
  const content::NavigationEntry* entry = web_contents()->GetController().GetLastCommittedEntry();
  return engine::PageRestoreState{.url = PresentedURL(entry->GetVirtualURL()), .state = std::move(*state)};
}

bool EnginePage::RestoreNow(const std::vector<uint8_t>& state, const std::string& expected_url) {
  if (!web_contents() || state.empty() || state.size() > kInteractionStateBytes) {
    return false;
  }
  auto& controller = web_contents()->GetController();
  // Restoration is only for a new page, never a replacement of live work.
  if (!controller.IsInitialNavigation()) {
    return false;
  }
  auto iterator = base::PickleIterator::WithData(base::span(state));
  std::string magic;
  std::string profile;
  int selected = 0;
  int count = 0;
  if (!iterator.ReadString(&magic) ||
      (magic != kInteractionStateMagic && magic != kInteractionStateMagicWithoutIds)) {
    return false;
  }
  const bool keeps_ids = magic == kInteractionStateMagic;
  if (!iterator.ReadString(&profile) ||
      profile != profile_ || !iterator.ReadInt(&selected) || !iterator.ReadInt(&count) || count < 1 ||
      count > kInteractionStateEntries || selected < 0 || selected >= count) {
    return false;
  }
  std::vector<sessions::SerializedNavigationEntry> saved;
  std::vector<engine::Guid> ids;
  for (int index = 0; index < count; ++index) {
    auto bytes = iterator.ReadData();
    if (!bytes || bytes->size() > kInteractionStateEntryBytes + 4 * 1024) {
      return false;
    }
    auto entry = base::PickleIterator::WithData(*bytes);
    sessions::SerializedNavigationEntry navigation;
    if (!navigation.ReadFromPickle(&entry) || !navigation.virtual_url().is_valid()) {
      return false;
    }
    saved.push_back(std::move(navigation));
    engine::Guid id = NewEntryId();
    if (keeps_ids) {
      auto id_bytes = iterator.ReadData();
      if (!id_bytes || id_bytes->size() != id.size()) {
        return false;
      }
      std::copy(id_bytes->begin(), id_bytes->end(), id.begin());
    }
    ids.push_back(id);
  }
  if (std::set<engine::Guid>(ids.begin(), ids.end()).size() != ids.size()) {
    return false;
  }
  const GURL expected = EngineURL(expected_url);
  if (!iterator.ReachedEnd() || !expected.is_valid() ||
      saved[static_cast<size_t>(selected)].virtual_url().GetWithoutRef() != expected.GetWithoutRef()) {
    return false;
  }
  auto entries =
      sessions::ContentSerializedNavigationBuilder::ToNavigationEntries(saved, web_contents()->GetBrowserContext());
  if (entries.size() != saved.size() ||
      std::any_of(entries.begin(), entries.end(), [](const auto& entry) { return !entry; })) {
    return false;
  }
  web_contents()->Stop();
  controller.DiscardNonCommittedEntries();
  controller.Restore(selected, content::RestoreType::kRestored, &entries);
  entry_ids_.clear();
  for (int index = 0; index < controller.GetEntryCount(); ++index) {
    entry_ids_[controller.GetEntryAtIndex(index)->GetUniqueID()] = ids[static_cast<size_t>(index)];
  }
  controller.LoadIfNecessary();
  StateChanged();
  return true;
}

// The engine's callbacks.

void EnginePage::DidStartNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument()) {
    return;
  }
  ++navigation_generation_;
  loading_navigation_ = navigation->GetNavigationId();
  // Only the app's own load of a new entry carries the core's identity. A
  // page's own navigation, a step through history or a reload that starts
  // first means that load never came, so the identity is dropped.
  if (expected_entry_id_ && !expected_entry_navigation_) {
    if (!navigation->IsRendererInitiated() && navigation->GetReloadType() == content::ReloadType::NONE &&
        !(navigation->GetPageTransition() & ui::PAGE_TRANSITION_FORWARD_BACK)) {
      expected_entry_navigation_ = navigation->GetNavigationId();
    } else {
      expected_entry_id_.reset();
    }
  }
  Present(engine::PageNavigationStarted{.page_id = id_});
  Started(PresentedURL(navigation->GetURL()));
}

void EnginePage::DidRedirectNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument() ||
      loading_navigation_ != navigation->GetNavigationId()) {
    return;
  }
  pending_url_ = PresentedURL(navigation->GetURL());
  StateChanged();
}

void EnginePage::DidFinishNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame()) {
    return;
  }
  if (navigation->HasCommitted()) {
    ++navigation_revision_;
  }
  // The core's load takes its identity with it, whether it commits, fails or
  // never loads, so no later entry inherits it.
  std::optional<engine::Guid> expected_entry_id;
  if (expected_entry_navigation_ == navigation->GetNavigationId()) {
    expected_entry_id = std::exchange(expected_entry_id_, std::nullopt);
    expected_entry_navigation_.reset();
  }
  // A store listing's own fragment carries the request its script made. It is
  // Crest's message, not a page anyone records.
  if (store_ && navigation->HasCommitted() && navigation->IsSameDocument() &&
      store_->Committed(navigation->GetURL())) {
    return;
  }
  const bool loading = loading_navigation_ == navigation->GetNavigationId();
  if (loading) {
    loading_navigation_.reset();
  }
  // A certificate error commits the engine's own interstitial, which explains
  // the problem and offers to proceed. It is the page, not a failure.
  const bool certificate_error =
      navigation->IsErrorPage() && net::IsCertificateError(navigation->GetNetErrorCode());
  if (navigation->IsErrorPage() && !certificate_error) {
    awaits_finish_ = false;
    Failed(engine::PageFailure{.error = NavigationErrorFor(navigation->GetNetErrorCode()),
                               .url = PresentedURL(navigation->GetURL()),
                               .replaced_document = true,
                               .domain = "net",
                               .code = navigation->GetNetErrorCode()});
    Present(engine::PageNavigationFailed{.page_id = id_});
    StateChanged();
    return;
  }
  if (!navigation->HasCommitted()) {
    // A navigation that became a download, was answered with no content or
    // was cancelled loads no document.
    if (loading && !navigation->IsSameDocument()) {
      Interrupted();
    }
    StateChanged();
    return;
  }
  const GURL committed = web_contents()->GetLastCommittedURL();
  if (ShowsInitialBlank(committed)) {
    return;
  }
  // A load the core asked for in place of an entry it keeps takes that
  // entry's identity; a step through history keeps the entry's own.
  if (expected_entry_id && !(navigation->GetPageTransition() & ui::PAGE_TRANSITION_FORWARD_BACK)) {
    if (content::NavigationEntry* entry = web_contents()->GetController().GetLastCommittedEntry()) {
      std::erase_if(entry_ids_, [&](const auto& kept) { return kept.second == *expected_entry_id; });
      entry_ids_[entry->GetUniqueID()] = *expected_entry_id;
    }
  }
  UpdateTheme();
  if (navigation->IsSameDocument()) {
    MovedWithinDocument(PresentedURL(committed));
  } else {
    awaits_finish_ = true;
    authentication_attempts_.clear();
    if (media_) {
      media_->DocumentChanged();
    }
    Committed(PresentedURL(committed));
  }
  Present(engine::PageNavigationCommitted{
      .page_id = id_, .url = PresentedURL(committed), .is_loading = web_contents()->IsLoading()});
  NoteTitle();
  FinishIfLoaded();
  StateChanged();
}

void EnginePage::DidStartLoading() {
  StateChanged();
}

void EnginePage::DidStopLoading() {
  NoteTitle();
  FinishIfLoaded();
  StateChanged();
  // The icon the engine found before the document committed, which no update
  // reported. A document that has one keeps it, and its sharper copy.
  if (!icon_) {
    if (auto* entry = web_contents()->GetController().GetLastCommittedEntry()) {
      PublishIcon(entry->GetFavicon().image, entry->GetFavicon().url);
    }
  }
}

void EnginePage::TitleWasSet(content::NavigationEntry* entry) {
  NoteTitle();
  StateChanged();
}

void EnginePage::NavigationEntriesDeleted() {
  StateChanged();
}

void EnginePage::DidChangeVisibleSecurityState() {
  StateChanged();
}

void EnginePage::DidChangeThemeColor() {
  UpdateTheme();
  StateChanged();
}

// The core decides whether the page comes back; the platform's page services
// hear it too, so they drop what belonged to the document that is gone.
void EnginePage::PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) {
  // A page whose document is gone has nothing to keep.
  AnswerBeforeUnload(true);
  awaits_finish_ = false;
  loading_navigation_.reset();
  Interrupted();
  Report(engine::PageCrashed{
      .page_id = id_, .domain = "ChromiumTerminationStatus", .code = static_cast<int64_t>(status)});
  Present(engine::PageRendererGone{.page_id = id_});
}

void EnginePage::DidGetUserInteraction(const blink::WebInputEvent& event) {
  const auto now = base::TimeTicks::Now();
  if (!last_interaction_.is_null() && now - last_interaction_ < kInteractionInterval) {
    return;
  }
  last_interaction_ = now;
  Present(engine::PageInteracted{.page_id = id_});
}

// The main frame takes the bridges as soon as its document element exists;
// frames below it once their document is parsed. The bridges' world guards
// itself against a second setup in the same document.
void EnginePage::PrimaryMainDocumentElementAvailable() {
  if (store_) {
    store_->DocumentAvailable();
  }
  if (content_) {
    content_->DocumentAvailable(web_contents()->GetPrimaryMainFrame());
  }
}

void EnginePage::DOMContentLoaded(content::RenderFrameHost* frame) {
  if (content_ && frame && !frame->IsInPrimaryMainFrame()) {
    content_->DocumentAvailable(frame);
  }
}

// A frame of the page's own site asked for a key system this engine does not
// carry, so the core may move the page to an engine that plays it. A frame of
// another site, such as an advertisement's, moves nothing.
void EnginePage::CrestKeySystemUnavailable(content::RenderFrameHost* frame, const std::string& key_system) {
  engine::KeySystem system;
  if (key_system.starts_with(kWidevinePrefix)) {
    system = engine::KeySystem::kWidevine;
  } else if (key_system.starts_with(kPlayReadyPrefix)) {
    system = engine::KeySystem::kPlayReady;
  } else {
    return;
  }
  auto* main = web_contents()->GetPrimaryMainFrame();
  if (!frame || !frame->GetPage().IsPrimary() ||
      (frame != main && net::SchemefulSite(frame->GetLastCommittedOrigin()) !=
                            net::SchemefulSite(main->GetLastCommittedOrigin()))) {
    return;
  }
  Report(engine::ProtectedMediaUnavailable{.page_id = id_, .key_system = system});
}

void EnginePage::OnAudioStateChanged(bool audible) {
  if (media_) {
    media_->AudioChanged();
  }
}

void EnginePage::DidUpdateAudioMutingState(bool muted) {
  if (media_) {
    media_->AudioChanged();
  }
}

void EnginePage::MediaStartedPlaying(const MediaPlayerInfo& info, const content::MediaPlayerId& id) {
  if (media_) {
    media_->PlayerStarted(id, info.has_video);
  }
  StateChanged();
}

void EnginePage::MediaStoppedPlaying(const MediaPlayerInfo& info,
                                     const content::MediaPlayerId& id,
                                     content::WebContentsObserver::MediaStoppedReason reason) {
  if (media_) {
    media_->PlayerStopped(id);
  }
  StateChanged();
}

void EnginePage::MediaPictureInPictureChanged(bool is_picture_in_picture) {
  if (media_) {
    media_->PictureInPictureChanged(is_picture_in_picture);
  }
  StateChanged();
}

// The engine closed the page on its own authority, as an extension's
// `chrome.tabs.remove` does; a page the binding lets go of stops following its
// WebContents first.
void EnginePage::WebContentsDestroyed() {
  settle_timer_.Stop();
  documents_.reset();
  store_.reset();
  content_.reset();
  inspector_.reset();
  infobars_.reset();
  media_.reset();
  Present(engine::PageViewClosed{.page_id = id_});
  if (find_helper_) {
    find_helper_->RemoveObserver(this);
    find_helper_ = nullptr;
  }
  if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents())) {
    driver->RemoveObserver(this);
  }
  Observe(nullptr);
  phase_ = Phase::kGone;
  binding_->PageLost(key_);
}

void EnginePage::OnFaviconUpdated(favicon::FaviconDriver* driver,
                                  NotificationIconType type,
                                  const GURL& icon_url,
                                  bool icon_url_changed,
                                  const gfx::Image& image) {
  // The tab's icon. Touch and largest icons are home-screen artwork, which
  // Chromium only looks for on phones.
  if (type == NON_TOUCH_16_DIP) {
    PublishIcon(image, icon_url);
  }
}

// Navigation events.

void EnginePage::Started(const std::string& url) {
  CancelSettling();
  pending_url_ = url;
  StateChanged();
  Report(engine::NavigationStarted{.page_id = id_, .url = url, .same_document = false});
}

void EnginePage::Committed(const std::string& url) {
  CancelSettling();
  document_url_ = url;
  pending_url_.reset();
  icon_.reset();
  ++icon_generation_;
  StateChanged();
  Report(engine::NavigationCommitted{.page_id = id_, .url = url, .same_document = false});
}

void EnginePage::Finished(const std::string& url) {
  CancelSettling();
  document_url_ = url;
  pending_url_.reset();
  StateChanged();
  Report(engine::NavigationFinished{.page_id = id_, .url = url, .title = Title()});
}

void EnginePage::Failed(engine::PageFailure failure) {
  CancelSettling();
  pending_url_.reset();
  StateChanged();
  Report(engine::NavigationFailed{.page_id = id_, .failure = std::move(failure)});
}

void EnginePage::Interrupted() {
  pending_url_.reset();
  StateChanged();
}

void EnginePage::MovedWithinDocument(const std::string& url) {
  if (document_url_ == url) {
    return;
  }
  document_url_ = url;
  StateChanged();
  Report(engine::NavigationStarted{.page_id = id_, .url = url, .same_document = true});
  Report(engine::NavigationCommitted{.page_id = id_, .url = url, .same_document = true});
  // A new document still loading finishes the move with its own finish.
  if (loading_navigation_ || awaits_finish_) {
    return;
  }
  CancelSettling();
  settling_url_ = url;
  settle_deadline_ = base::TimeTicks::Now() + kTitleSettleLimit;
  settle_timer_.Start(FROM_HERE, std::min(kTitleSettleInterval, kTitleSettleLimit),
                      base::BindOnce(&EnginePage::Settle, base::Unretained(this)));
}

void EnginePage::TitleChanged() {
  StateChanged();
  if (!settling_url_) {
    return;
  }
  // The wait restarts, never past its limit.
  const base::TimeDelta remaining = settle_deadline_ - base::TimeTicks::Now();
  settle_timer_.Start(FROM_HERE, std::max(base::TimeDelta(), std::min(kTitleSettleInterval, remaining)),
                      base::BindOnce(&EnginePage::Settle, base::Unretained(this)));
}

void EnginePage::NoteTitle() {
  std::string title = Title();
  if (title == reported_title_) {
    return;
  }
  reported_title_ = std::move(title);
  TitleChanged();
}

void EnginePage::FinishIfLoaded() {
  if (!awaits_finish_ || !web_contents() || web_contents()->IsLoading()) {
    return;
  }
  awaits_finish_ = false;
  Finished(PresentedURL(web_contents()->GetLastCommittedURL()));
}

void EnginePage::Settle() {
  if (!settling_url_) {
    return;
  }
  std::string url = std::move(*settling_url_);
  settling_url_.reset();
  Report(engine::NavigationFinished{.page_id = id_, .url = std::move(url), .title = Title()});
}

void EnginePage::CancelSettling() {
  settle_timer_.Stop();
  settling_url_.reset();
}

// The icon.

void EnginePage::PublishIcon(const gfx::Image& image, const GURL& icon_url) {
  if (image.IsEmpty()) {
    return;
  }
  // The Retina representation, or the closest one the icon has.
  const gfx::ImageSkia skia = image.AsImageSkia();
  const gfx::ImageSkiaRep& rep = skia.GetRepresentation(kIconScale);
  if (rep.is_null()) {
    return;
  }
  const SkBitmap& artwork = rep.GetBitmap();
  // The same artwork again keeps its sharper copy. New artwork shows at once,
  // even from the same file, and its sharper copy follows.
  if (icon_ && icon_->source == icon_url && icon_->pixels > IconPixels(artwork) &&
      gfx::BitmapsAreEqual(icon_->artwork, artwork)) {
    return;
  }
  SetIcon(artwork, icon_url, artwork);
  FetchSharperIcon(icon_url, artwork);
}

// Fetches the icon file again at the size Crest draws it, which an SVG, or an
// ICO or PNG with more pixels, fills better than the engine's favicon. Like the
// engine's own fetch it sends no cookies, and it usually comes from the cache.
void EnginePage::FetchSharperIcon(const GURL& icon_url, const SkBitmap& artwork) {
  const uint64_t generation = ++icon_generation_;
  if (!web_contents() || !icon_url.is_valid()) {
    return;
  }
  web_contents()->DownloadImage(
      icon_url, /*is_favicon=*/true, gfx::Size(kIconPixels, kIconPixels), kIconPixels, /*bypass_cache=*/false,
      base::BindOnce(
          [](base::WeakPtr<EnginePage> page, uint64_t generation, GURL icon_url, SkBitmap artwork, int /*id*/,
             int /*status*/, const GURL& /*image_url*/, const std::vector<SkBitmap>& bitmaps,
             const std::vector<gfx::Size>& /*sizes*/) {
            // A later icon, or a later document, replaced the one this fetched.
            if (!page || generation != page->icon_generation_) {
              return;
            }
            const auto sharpest = std::ranges::max_element(bitmaps, {}, &IconPixels);
            if (sharpest != bitmaps.end() && IconPixels(*sharpest) > IconPixels(artwork)) {
              page->SetIcon(*sharpest, icon_url, artwork);
            }
          },
          weak_factory_.GetWeakPtr(), generation, icon_url, artwork));
}

void EnginePage::SetIcon(const SkBitmap& bitmap, const GURL& icon_url, const SkBitmap& artwork) {
  if (!web_contents()) {
    return;
  }
  auto* driver = favicon::ContentFaviconDriver::FromWebContents(web_contents());
  if (!driver) {
    return;
  }
  // An icon for a document the page no longer shows is not this one's.
  const GURL source = driver->GetActiveURL();
  if (source.is_valid() && !SameDocument(source, web_contents()->GetLastCommittedURL())) {
    return;
  }
  auto png = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, /*discard_transparency=*/false);
  if (!png || png->size() == 0 || png->size() > kIconBytes) {
    return;
  }
  icon_ = FoundIcon{std::move(*png),
                    PresentedURL(source.is_valid() ? source : web_contents()->GetLastCommittedURL()), icon_url,
                    artwork, IconPixels(bitmap)};
  ReportIcon();
}

void EnginePage::UpdateTheme() {
  if (!web_contents()) {
    return;
  }
  std::optional<engine::TabIconAccent> accent;
  if (const auto color = web_contents()->GetThemeColor(); color && SkColorGetA(*color) > 0) {
    accent = engine::TabIconAccent{.red = SkColorGetR(*color) / 255.0,
                                   .green = SkColorGetG(*color) / 255.0,
                                   .blue = SkColorGetB(*color) / 255.0};
  }
  if (accent == accent_) {
    return;
  }
  accent_ = accent;
  ReportIcon();
}

void EnginePage::ReportIcon() {
  if (!icon_) {
    return;
  }
  Report(engine::PageIconChanged{.page_id = id_, .url = icon_->url, .accent = accent_});
}

std::optional<std::vector<uint8_t>> EnginePage::icon() const {
  if (!icon_) {
    return std::nullopt;
  }
  return icon_->png;
}

// What the page shows.

void EnginePage::StateChanged() {
  if (report_due_) {
    return;
  }
  report_due_ = true;
  binding_->ReportStateSoon(key_);
}

void EnginePage::ReportState() {
  report_due_ = false;
  PresentView();
  engine::PageSnapshot snapshot = Snapshot();
  if (snapshot != reported_) {
    reported_ = snapshot;
    Report(engine::PageStateChanged{.page_id = id_, .snapshot = std::move(snapshot)});
  }
  ReportHistory();
}

void EnginePage::ReportHistory() {
  const os_signpost_id_t signpost = os_signpost_id_generate(HistoryLog());
  os_signpost_interval_begin(HistoryLog(), signpost, "Report Page History");
  engine::PageHistoryReported history = History();
  if (history != reported_history_) {
    reported_history_ = history;
    Report(std::move(history));
  }
  os_signpost_interval_end(HistoryLog(), signpost, "Report Page History");
}

engine::PageHistoryReported EnginePage::History() {
  engine::PageHistoryReported history{.page_id = id_, .current = -1};
  if (!web_contents()) {
    return history;
  }
  auto& controller = web_contents()->GetController();
  const content::NavigationEntry* committed = controller.GetLastCommittedEntry();
  if (!committed || committed->IsInitialEntry()) {
    entry_ids_.clear();
    return history;
  }
  std::map<int, engine::Guid> kept;
  for (int index = 0; index < controller.GetEntryCount(); ++index) {
    content::NavigationEntry* entry = controller.GetEntryAtIndex(index);
    const engine::Guid id = EntryId(entry);
    kept[entry->GetUniqueID()] = id;
    history.entries.push_back(engine::PageHistoryEntry{
        .id = id, .url = PresentedURL(entry->GetVirtualURL()), .title = base::UTF16ToUTF8(entry->GetTitle())});
  }
  // Entries the engine dropped take their identities with them.
  entry_ids_ = std::move(kept);
  history.current = controller.GetLastCommittedEntryIndex();
  return history;
}

engine::Guid EnginePage::EntryId(content::NavigationEntry* entry) {
  auto [found, added] = entry_ids_.try_emplace(entry->GetUniqueID());
  if (added) {
    found->second = NewEntryId();
  }
  return found->second;
}

void EnginePage::ExpectEntry(const std::optional<engine::Guid>& entry_id) {
  expected_entry_id_ = entry_id;
  expected_entry_navigation_.reset();
}

void EnginePage::GoToEntry(const engine::Guid& entry_id) {
  os_signpost_event_emit(HistoryLog(), OS_SIGNPOST_ID_EXCLUSIVE, "Go To History Entry");
  if (web_contents()) {
    auto& controller = web_contents()->GetController();
    for (int index = 0; index < controller.GetEntryCount(); ++index) {
      auto found = entry_ids_.find(controller.GetEntryAtIndex(index)->GetUniqueID());
      if (found != entry_ids_.end() && found->second == entry_id) {
        if (index != controller.GetLastCommittedEntryIndex()) {
          controller.GoToIndex(index);
        }
        return;
      }
    }
  }
  reported_history_.reset();
  StateChanged();
}

engine::PageSnapshot EnginePage::Snapshot() const {
  engine::PageSnapshot snapshot{.pending_url = pending_url_};
  if (!web_contents()) {
    return snapshot;
  }
  const GURL visible = web_contents()->GetVisibleURL();
  if (!visible.is_empty() && !ShowsInitialBlank(visible)) {
    snapshot.url = PresentedURL(visible);
  }
  snapshot.title = Title();
  snapshot.is_loading = web_contents()->IsLoading();
  snapshot.security = Security();
  snapshot.media = MediaActivity();
  return snapshot;
}

// The title the page gave itself, or nothing yet. The engine shows a page
// without one by its address, which is no title of the page's, so Crest
// names that page itself and a later title replaces nothing the page said.
std::string EnginePage::Title() const {
  if (!web_contents()) {
    return std::string();
  }
  const std::u16string& title = web_contents()->GetTitle();
  auto& controller = web_contents()->GetController();
  for (content::NavigationEntry* entry : {controller.GetLastCommittedEntry(), controller.GetVisibleEntry()}) {
    if (entry && entry->GetTitle().empty() && title == entry->GetTitleForDisplay()) {
      return std::string();
    }
  }
  return base::UTF16ToUTF8(title);
}

// The engine's own verdict on the visible document's connection. Only a
// secure transport with no mixed content and no certificate problem is
// secure; a page the engine flags as malicious outranks everything else, and
// a certificate error outranks mixed content.
engine::PageSecurity EnginePage::Security() const {
  if (!web_contents()) {
    return engine::PageSecurity::kNone;
  }
  const auto visible = chrome_security_state::GetVisibleSecurityState(web_contents());
  const auto level = chrome_security_state::GetSecurityLevel(web_contents());
  if (!visible) {
    return engine::PageSecurity::kNone;
  }
  if (visible->malicious_content_status != security_state::MALICIOUS_CONTENT_STATUS_NONE) {
    return engine::PageSecurity::kDangerous;
  }
  if (net::IsCertStatusError(visible->cert_status)) {
    return engine::PageSecurity::kCertificateError;
  }
  // Any other failed load shows Crest's own failure view, not a connection.
  if (visible->is_error_page) {
    return engine::PageSecurity::kNone;
  }
  if (!security_state::IsSchemeCryptographic(visible->url)) {
    return level == security_state::WARNING || level == security_state::DANGEROUS
               ? engine::PageSecurity::kInsecure
               : engine::PageSecurity::kNone;
  }
  // An HTTPS entry that has not connected yet has no connection to judge.
  if (!visible->connection_info_initialized) {
    return engine::PageSecurity::kNone;
  }
  if (level == security_state::SECURE) {
    return engine::PageSecurity::kSecure;
  }
  if (visible->ran_mixed_content || visible->displayed_mixed_content || visible->contained_mixed_form ||
      visible->ran_content_with_cert_errors || visible->displayed_content_with_cert_errors) {
    return engine::PageSecurity::kMixedContent;
  }
  if (level == security_state::DANGEROUS) {
    return engine::PageSecurity::kDangerous;
  }
  // A cryptographic scheme the engine still warns about, such as legacy TLS.
  return engine::PageSecurity::kInsecure;
}

bool EnginePage::ShowsInitialBlank(const GURL& url) const {
  return url.IsAboutBlank() && pending_url_ && *pending_url_ != url.spec();
}

void EnginePage::Report(engine::EngineEvent event) {
  binding_->Report(std::move(event));
}

void EnginePage::Present(engine::EnginePresentation presentation) {
  binding_->Present(std::move(presentation));
}

void EnginePage::PresentView() {
  if (!web_contents()) {
    return;
  }
  const bool loading = web_contents()->IsLoading();
  if (presented_loading_ != loading) {
    presented_loading_ = loading;
    Present(engine::PageLoadingChanged{.page_id = id_, .is_loading = loading});
  }
  std::optional<engine::BrandColor> theme;
  if (const auto color = web_contents()->GetThemeColor()) {
    theme = engine::BrandColor{.red = SkColorGetR(*color) / 255.0,
                               .green = SkColorGetG(*color) / 255.0,
                               .blue = SkColorGetB(*color) / 255.0,
                               .alpha = SkColorGetA(*color) / 255.0};
  }
  if (presented_theme_ != theme) {
    presented_theme_ = theme;
    Present(engine::PageThemeChanged{.page_id = id_, .color = theme});
  }
}

void EnginePage::Watch() {
  if (phase_ != Phase::kLive || !web_contents()) {
    return;
  }
  Present(engine::PageViewReady{.page_id = id_});
  presented_loading_.reset();
  presented_theme_.reset();
  if (infobars_) {
    infobars_->PresentAll();
  }
  if (media_ && (media_->shared() || media_->sharing())) {
    PresentSharing();
  }
  StateChanged();
}

// What the platform asks of the page directly.

bool EnginePage::Answer(const engine::ReloadPage& request) {
  if (!web_contents()) {
    return false;
  }
  web_contents()->GetController().Reload(
      request.bypasses_cache ? content::ReloadType::BYPASSING_CACHE : content::ReloadType::NORMAL, true);
  return true;
}

// The core's crash recovery asked for the page back. A document a form posted
// is loaded again by its address, so the form is never posted twice without
// the person asking.
bool EnginePage::Recover() {
  if (!web_contents()) {
    return false;
  }
  auto& controller = web_contents()->GetController();
  content::NavigationEntry* entry = controller.GetLastCommittedEntry();
  if (entry && entry->GetHasPostData()) {
    Load(PresentedURL(entry->GetURL()));
    return true;
  }
  controller.Reload(content::ReloadType::NORMAL, /*check_for_repost=*/false);
  return true;
}

// A document that asks nothing lets the page go at once; one with a
// beforeunload handler may ask the person first.
void EnginePage::CheckBeforeUnload() {
  content::WebContents* contents = web_contents();
  if (!contents || !contents->NeedToFireBeforeUnloadOrUnloadEvents()) {
    Report(engine::BeforeUnloadAnswered{.page_id = id_, .proceeds = true});
    return;
  }
  checks_before_unload_ = true;
  contents->DispatchBeforeUnload(/*auto_cancel=*/false);
}

bool EnginePage::AnswerBeforeUnload(bool proceed) {
  if (!checks_before_unload_) {
    return false;
  }
  checks_before_unload_ = false;
  Report(engine::BeforeUnloadAnswered{.page_id = id_, .proceeds = proceed});
  return true;
}

void EnginePage::RequestClose() {
  Report(engine::PageCloseRequested{.page_id = id_});
}

bool EnginePage::Answer(const engine::StopLoading&) {
  if (!web_contents()) {
    return false;
  }
  web_contents()->Stop();
  return true;
}

bool EnginePage::Answer(const engine::ZoomPage& request) {
  if (!std::isfinite(request.factor) || request.factor < kMinimumZoom || request.factor > kMaximumZoom) {
    return false;
  }
  zoom_ = request.factor;
  ApplyZoom();
  return true;
}

void EnginePage::ApplyZoom() {
  if (!zoom_ || !web_contents()) {
    return;
  }
  auto* zoom = zoom::ZoomController::FromWebContents(web_contents());
  if (!zoom) {
    return;
  }
  zoom->SetZoomMode(zoom::ZoomController::ZOOM_MODE_ISOLATED);
  zoom->SetZoomLevel(blink::ZoomFactorToZoomLevel(*zoom_));
}

bool EnginePage::Answer(const engine::FindInPage& request) {
  if (!find_helper_) {
    return false;
  }
  if (request.query.empty()) {
    find_pending_ = false;
    find_helper_->StopFinding(find_in_page::SelectionAction::kClear);
    Present(engine::FindFinished{.page_id = id_, .matches = 0});
    return true;
  }
  find_pending_ = true;
  find_helper_->StartFinding(base::UTF8ToUTF16(request.query), !request.backwards, request.case_sensitive, true);
  return true;
}

// The final update of a search carries its total and the ordinal of the
// match it selected; earlier updates are still counting.
void EnginePage::OnFindResultAvailable(content::WebContents*) {
  if (!find_helper_ || !find_pending_ || !find_helper_->find_result().final_update()) {
    return;
  }
  find_pending_ = false;
  const auto& result = find_helper_->find_result();
  Present(engine::FindFinished{.page_id = id_,
                               .matches = std::max(0, result.number_of_matches()),
                               .active_match = std::max(0, result.active_match_ordinal())});
}

void EnginePage::OnFindTabHelperDestroyed(find_in_page::FindTabHelper*) {
  find_helper_ = nullptr;
  find_pending_ = false;
}

bool EnginePage::Answer(const engine::CapturePage& request) {
  auto* view = web_contents() ? web_contents()->GetRenderWidgetHostView() : nullptr;
  const double width = request.width;
  if (!view || !std::isfinite(width) || width < 0 || width > kMaximumCaptureWidth) {
    return false;
  }
  gfx::Rect bounds;
  if (const auto& area = request.area) {
    if (!std::isfinite(area->x) || !std::isfinite(area->y) || !std::isfinite(area->width) ||
        !std::isfinite(area->height)) {
      return false;
    }
    bounds = gfx::Rect(static_cast<int>(area->x), static_cast<int>(area->y), static_cast<int>(area->width),
                       static_cast<int>(area->height));
    bounds.Intersect(gfx::Rect(view->GetViewBounds().size()));
    if (bounds.IsEmpty()) {
      return false;
    }
  }
  const gfx::Size size = bounds.IsEmpty() ? view->GetViewBounds().size() : bounds.size();
  if (size.IsEmpty()) {
    return false;
  }
  gfx::Size output;
  if (width > 0) {
    output = gfx::Size(std::max(1, static_cast<int>(width)),
                       std::max(1, static_cast<int>(width * size.height() / size.width())));
  }
  view->CopyFromSurface(
      bounds, output, kCaptureTimeout,
      base::BindOnce(
          [](base::WeakPtr<EnginePage> page, engine::Guid capture_id, const content::CopyFromSurfaceResult& result) {
            if (!page) {
              return;
            }
            std::optional<std::vector<uint8_t>> png;
            if (result.has_value() && !result->bitmap.drawsNothing()) {
              png = gfx::PNGCodec::EncodeBGRASkBitmap(result->bitmap, false);
            }
            page->Present(engine::PageCaptured{.page_id = page->id_, .capture_id = capture_id, .png = std::move(png)});
          },
          weak_factory_.GetWeakPtr(), request.capture_id));
  return true;
}

bool EnginePage::Answer(const engine::ExportPage& request) {
  // Chromium keeps its archives as MHTML, never as WebKit's web archives.
  if (!web_contents() || request.format == engine::PageExportFormat::kWebArchive) {
    return false;
  }
  if (!documents_) {
    documents_ = std::make_unique<PageDocuments>(web_contents());
  }
  documents_->Export(
      request.format, request.width,
      base::BindOnce(
          [](base::WeakPtr<EnginePage> page, engine::Guid export_id, std::optional<std::vector<uint8_t>> document,
             std::optional<engine::PageExportFailure> failure) {
            if (!page) {
              return;
            }
            page->Present(engine::PageExported{
                .page_id = page->id_, .export_id = export_id, .document = std::move(document), .failure = failure});
          },
          weak_factory_.GetWeakPtr(), request.export_id));
  return true;
}

bool EnginePage::Answer(const engine::ShowPage&) {
  if (!web_contents()) {
    return false;
  }
  web_contents()->WasShown();
  web_contents()->Focus();
  if (media_) {
    media_->VisibilityChanged(true);
  }
  StateChanged();
  return true;
}

bool EnginePage::Answer(const engine::HidePage&) {
  if (!web_contents()) {
    return false;
  }
  if (media_) {
    media_->VisibilityChanged(false);
  }
  web_contents()->WasHidden();
  StateChanged();
  return true;
}

engine::PageMediaActivity EnginePage::MediaActivity() const {
  return media_ ? media_->Activity() : engine::PageMediaActivity::kNone;
}

// The page's tab shows its part in tab sharing for as long as it lasts.
void EnginePage::SharedChanged(bool shared) {
  if (!media_) {
    return;
  }
  const bool was_shared = media_->shared();
  media_->SharedChanged(shared);
  if (media_->shared() != was_shared) {
    PresentSharing();
  }
}

void EnginePage::SharingChanged(bool sharing) {
  if (!media_) {
    return;
  }
  const bool was_sharing = media_->sharing();
  media_->SharingChanged(sharing);
  if (media_->sharing() != was_sharing) {
    PresentSharing();
  }
}

void EnginePage::PresentSharing() {
  Present(engine::TabSharingChanged{.page_id = id_, .shared = media_->shared(), .sharing = media_->sharing()});
}

bool EnginePage::Answer(const engine::EnterPictureInPicture&) {
  return media_ && media_->EnterPictureInPicture();
}

bool EnginePage::ExitPictureInPicture() {
  return media_ && media_->ExitPictureInPicture();
}

bool EnginePage::ReturnFromPictureInPicture() {
  if (!media_ || !media_->ReturnsFromPictureInPicture()) {
    return false;
  }
  Report(engine::PictureInPictureReturned{.page_id = id_});
  return true;
}

bool EnginePage::Answer(const engine::ActivateMediaSession& request) {
  return media_ && media_->Activate(request.document);
}

bool EnginePage::Answer(const engine::PerformMediaAction& request) {
  return media_ && media_->Perform(request.document, request.action);
}

bool EnginePage::Answer(const engine::MuteMediaSession& request) {
  return media_ && media_->Mute(request.document, request.muted);
}

bool EnginePage::Answer(const engine::ObserveAudioSpectrum& request) {
  return media_ && media_->ObserveSpectrum(request.observed);
}

bool EnginePage::Answer(const engine::AnswerInfoBar& request) {
  return infobars_ && infobars_->Answer(request.info_bar_id, request.answer);
}

// Fetches the icon again rather than replay the one the engine has.
bool EnginePage::Answer(const engine::RefreshPageIcon&) {
  auto* driver = web_contents() ? favicon::ContentFaviconDriver::FromWebContents(web_contents()) : nullptr;
  if (!driver) {
    return false;
  }
  driver->FetchFavicon(web_contents()->GetLastCommittedURL(), /*is_same_document=*/false);
  return true;
}

bool EnginePage::Answer(const engine::ShowBlockedPopups&) {
  auto* blocker =
      web_contents() ? blocked_content::PopupBlockerTabHelper::FromWebContents(web_contents()) : nullptr;
  if (!blocker || !blocker->GetBlockedPopupsCount()) {
    return false;
  }
  blocker->ShowAllBlockedPopups();
  presented_blocked_popups_ = 0;
  return true;
}

bool EnginePage::Answer(const engine::AddContentScript& request) {
  if (!content_ || request.source.empty()) {
    return false;
  }
  content_->Add(request.source, request.main_frame_only);
  return true;
}

bool EnginePage::Answer(const engine::EvaluateContentScript& request) {
  return content_ && content_->Evaluate(request.evaluation_id, request.source, request.frame_id);
}

PageAgent* EnginePage::Agent() {
  if (!agent_ && web_contents()) {
    agent_ = std::make_unique<PageAgent>(web_contents(), id_,
                                         base::BindRepeating(&EnginePage::Present, weak_factory_.GetWeakPtr()));
  }
  return agent_.get();
}

bool EnginePage::Answer(const engine::ObservePageActivity& request) {
  if (PageAgent* agent = Agent()) {
    observes_activity_ = request.observing;
    return agent->ObserveActivity(request.observing);
  }
  if (phase_ != Phase::kCreating) {
    return false;
  }
  observes_activity_ = request.observing;
  return true;
}

bool EnginePage::Answer(const engine::OpenInspector& request) {
  return inspector_ && inspector_->Open(request.panel);
}

bool EnginePage::Answer(const engine::CloseInspector&) {
  return inspector_ && inspector_->Close();
}

bool EnginePage::Answer(const engine::PageInspected&) const {
  return inspector_ && inspector_->IsOpen();
}

engine::InspectorLayout EnginePage::Answer(const engine::LayoutInspector& request) const {
  return inspector_ ? inspector_->Layout(request.width, request.height) : engine::InspectorLayout{};
}

// The chain the engine verified for the visible entry, leaf first.
engine::CertificateChain EnginePage::Answer(const engine::PageCertificates&) const {
  engine::CertificateChain chain;
  auto* entry = web_contents() ? web_contents()->GetController().GetVisibleEntry() : nullptr;
  if (!entry || !entry->GetSSL().certificate) {
    return chain;
  }
  const auto& certificate = entry->GetSSL().certificate;
  auto append = [&chain](const CRYPTO_BUFFER* buffer) {
    const auto bytes = net::x509_util::CryptoBufferAsSpan(buffer);
    chain.certificates.emplace_back(bytes.begin(), bytes.end());
  };
  append(certificate->cert_buffer());
  for (const auto& intermediate : certificate->intermediate_buffers()) {
    append(intermediate.get());
  }
  return chain;
}

// The content settings the engine enforces for Crest's record: allowed,
// blocked, or the site's own setting cleared so the engine's default applies.
bool EnginePage::Answer(const engine::SetSitePermission& request) {
  if (!web_contents()) {
    return false;
  }
  const GURL origin = web_contents()->GetLastCommittedURL().DeprecatedGetOriginAsURL();
  if (!origin.SchemeIsHTTPOrHTTPS()) {
    return false;
  }
  ContentSettingsType type;
  switch (request.permission) {
    case engine::SitePermission::kCamera:
      type = ContentSettingsType::MEDIASTREAM_CAMERA;
      break;
    case engine::SitePermission::kMicrophone:
      type = ContentSettingsType::MEDIASTREAM_MIC;
      break;
    case engine::SitePermission::kLocation:
      type = ContentSettingsType::GEOLOCATION;
      break;
    case engine::SitePermission::kNotifications:
      type = ContentSettingsType::NOTIFICATIONS;
      break;
    case engine::SitePermission::kPopups:
      type = ContentSettingsType::POPUPS;
      break;
    case engine::SitePermission::kAutomaticDownloads:
      type = ContentSettingsType::AUTOMATIC_DOWNLOADS;
      break;
    default:
      return false;
  }
  const ContentSetting setting = !request.allowed ? CONTENT_SETTING_DEFAULT
                                 : *request.allowed ? CONTENT_SETTING_ALLOW
                                                    : CONTENT_SETTING_BLOCK;
  HostContentSettingsMapFactory::GetForProfile(Profile::FromBrowserContext(web_contents()->GetBrowserContext()))
      ->SetContentSettingDefaultScope(origin, GURL(), type, setting);
  return true;
}

int EnginePage::AuthenticationAttempt(const std::string& challenge) {
  return authentication_attempts_[challenge]++;
}

bool EnginePage::Answer(const engine::RefreshStoreListing&) {
  if (!store_) {
    return false;
  }
  store_->RequestFinished();
  return true;
}

void EnginePage::RefreshStore() {
  if (store_) {
    store_->Refresh();
  }
}

// The engine's hooks.

void EnginePage::FullscreenChanged(bool active) {
  Present(engine::ContentFullscreenChanged{.page_id = id_, .active = active});
}

void EnginePage::HoverChanged(const GURL& url) {
  Present(engine::LinkHovered{.page_id = id_,
                              .url = url.is_valid() ? std::optional<std::string>(PresentedURL(url)) : std::nullopt});
}

// The engine's blocker forgets its pop-ups when the document changes.
void EnginePage::SiteIndicatorsChanged() {
  auto* blocker =
      web_contents() ? blocked_content::PopupBlockerTabHelper::FromWebContents(web_contents()) : nullptr;
  const size_t count = blocker ? blocker->GetBlockedPopupsCount() : 0;
  if (count < presented_blocked_popups_) {
    presented_blocked_popups_ = count;
  }
  if (count <= presented_blocked_popups_) {
    return;
  }
  presented_blocked_popups_ = count;
  Present(engine::PopupBlocked{.page_id = id_, .page_url = PresentedURL(web_contents()->GetLastCommittedURL())});
}

void EnginePage::InspectorChanged() {
  if (inspector_) {
    inspector_->Update();
  }
}

void EnginePage::InspectorClosing() {
  if (inspector_) {
    inspector_->Closing();
  }
}

}  // namespace crest
