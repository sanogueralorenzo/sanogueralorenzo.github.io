#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_PAGE_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_PAGE_H_

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/find_in_page/find_result_observer.h"
#include "content/public/browser/web_contents_observer.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "url/gurl.h"

namespace crest {

class EngineBinding;
class PageAgent;
class PageContent;
class PageDocuments;
class PageInfoBars;
class PageInspector;
class PageMedia;
class PageStore;

// One page the core asked Chromium to create, from its CreatePage until the
// engine lets it go. It turns the WebContents' own callbacks into the core's
// engine events, as every binding does:
//
// - A navigation to a new document starts, commits, then finishes with the
//   title it settled on, or fails.
// - A move within the document, such as `history.pushState` or a fragment,
//   starts and commits when the address changes, and finishes once the page's
//   title settles (see `kTitleSettleInterval`). A move while a new document is
//   still loading belongs to that load, which finishes it.
// - An icon is reported when the engine finds one for the document, and again
//   when the page's theme changes the colour behind it.
// - What the page shows, its PageSnapshot, is reported once in any turn in
//   which it changed, and only when it differs from the last one reported.
//
// The core decides what each event records; this only decides when the
// engine's callbacks amount to one. Addresses are in Crest's namespace, where
// the engine's own `chrome://` pages are `crest://` pages.
//
// It also answers what the platform asks of the page directly: its history,
// reload, find, zoom, capture, export and whether it is on screen, its media
// session, the engine's bars and Crest's content bridges. It presents what
// the platform shows of the page: whether its view is ready, its navigations
// as they start, commit and fail, its loading, history and theme, the link
// under the pointer, blocked pop-ups, fullscreen and a Chrome Web Store
// listing's requests.
class EnginePage final : public content::WebContentsObserver,
                         public favicon::FaviconDriverObserver,
                         public find_in_page::FindResultObserver {
 public:
  // Where the page stands on the engine.
  enum class Phase {
    // The binding is creating its WebContents.
    kCreating,
    // The page has its WebContents.
    kLive,
    // The engine lost the WebContents on its own.
    kGone,
  };

  // How long a page's title must hold after a move within its document
  // before the move finishes. Sites that route in script change the address
  // first and set the new page's title a moment later.
  static constexpr base::TimeDelta kTitleSettleInterval = base::Milliseconds(500);
  // The longest a move within the document waits for its title, counted from
  // the move, so a page whose title never stops changing still records.
  static constexpr base::TimeDelta kTitleSettleLimit = base::Seconds(2);
  // The person's typing, clicking and scrolling in the page is presented at
  // most this often.
  static constexpr base::TimeDelta kInteractionInterval = base::Seconds(1);

  EnginePage(EngineBinding& binding, const engine::CreatePage& creation);
  EnginePage(const EnginePage&) = delete;
  EnginePage& operator=(const EnginePage&) = delete;
  ~EnginePage() override;

  const engine::Guid& id() const { return id_; }
  // The page's identity as the platform spells it.
  const std::string& key() const { return key_; }
  const std::string& profile() const { return profile_; }
  bool is_private() const { return is_private_; }
  // The Crest window whose Browser holds the page.
  const std::string& window() const { return window_; }
  void set_window(std::string window) { window_ = std::move(window); }
  Phase phase() const { return phase_; }
  // How many documents the page has committed and started, which a link
  // followed in it compares to tell whether the page still shows the document
  // the link was in.
  uint64_t navigation_revision() const { return navigation_revision_; }
  uint64_t navigation_generation() const { return navigation_generation_; }
  void set_phase(Phase phase) { phase_ = phase; }

  // Starts following `contents`, which is now the page.
  void Start(content::WebContents* contents);
  // Stops following the page, which the binding is letting go of.
  void Stop();

  // The app asked the page to load `url`: the core's LoadPage, or the
  // platform's own load. The page shows it is heading there at once; a page
  // still being created loads it once it exists.
  void Load(const std::string& url);
  // Keeps the link the core staged for the page's first load, which a load of
  // the same address then runs. False once the page loads.
  bool Stage(const std::string& token, const std::string& url);
  // The entry the next load the app asks for commits takes `entry_id`, the
  // core's identity for an entry it asked the page to load again; none
  // forgets the identity an earlier load expected.
  void ExpectEntry(const std::optional<engine::Guid>& entry_id);
  // Restores navigation history saved by `SaveInteractionState` in place of a
  // load of `expected_url`; a page still being created restores once it
  // exists. False when the state does not restore this page.
  bool Restore(std::vector<uint8_t> state, const std::string& expected_url);
  // The page's navigation history, or nothing before its first commit.
  std::optional<std::vector<uint8_t>> SaveInteractionState();
  // The navigation history with the address it restores, for a page closing
  // so the core can bring it back later; nothing before its first commit.
  std::optional<engine::PageRestoreState> RestoreState();
  // Runs what the app asked for before the page existed: the restore, the
  // staged link or the load.
  void LoadPending();
  // The token of the link staged for the page, which a closing page drops.
  std::optional<std::string> TakeStagedToken();

  // The icon the engine found for the page's document.
  std::optional<std::vector<uint8_t>> icon() const;

  // The platform shows the page from now on. A live page presents that its
  // view is ready and everything its view shows again.
  void Watch();

  // Shows the history entry `entry_id` names, the core's GoToHistoryEntry.
  // An entry the page no longer keeps starts nothing, and the page reports
  // its history again.
  void GoToEntry(const engine::Guid& entry_id);

  // What the platform asks of the page directly. Each answers whether the
  // page took it; what finishes later is presented.
  bool Reload(bool bypasses_cache);
  // Brings the page back after its renderer stopped, as the core decided.
  bool Recover();
  // Asks the page whether it may go, for a close the core prepares; the
  // answer is reported as BeforeUnloadAnswered.
  void CheckBeforeUnload();
  // The engine fired the page's beforeunload. Answers whether the core had
  // asked, which then hears `proceed`.
  bool AnswerBeforeUnload(bool proceed);
  // The page's own script asked to close its window, once its document
  // agreed to go; the core decides whether the page closes.
  void RequestClose();
  bool StopLoading();
  bool Zoom(double factor);
  bool Find(const std::string& query, bool backwards, bool case_sensitive);
  bool Capture(const engine::Guid& capture_id, const std::optional<engine::PageArea>& area, double width);
  bool Export(const engine::Guid& export_id, engine::PageExportFormat format, double width);
  bool Show();
  bool Hide();
  engine::PageMediaActivity MediaActivity() const;
  // Another page began or stopped sharing this one as a tab.
  void SharedChanged(bool shared);
  // This page began or stopped sharing another tab.
  void SharingChanged(bool sharing);
  bool EnterPictureInPicture();
  // Ends the page's own Picture in Picture, as the core asks once a window
  // shows the page again, returning the video to its place in the page.
  bool ExitPictureInPicture();
  // A Picture in Picture window's return control asks for the page. Answers
  // whether the page returns from Picture in Picture, which it then reports
  // so the core shows the page's tab; false for any other ask.
  bool ReturnFromPictureInPicture();
  bool ActivateMediaSession(const std::string& document);
  bool PerformMediaAction(const std::string& document, engine::MediaSessionAction action);
  bool MuteMediaSession(const std::string& document, bool muted);
  // Starts or stops measuring the sound the page plays for its tab.
  bool ObserveAudioSpectrum(bool observed);
  bool AnswerInfoBar(int id, engine::InfoBarAnswer answer);
  bool RefreshIcon();
  bool ShowBlockedPopups();
  bool AddContentScript(std::string source, bool main_frame_only);
  bool EvaluateContentScript(const engine::Guid& evaluation, const std::string& source, const std::string& frame);
  // The page's agent session, made the first time an agent uses the page; null
  // while the page has no WebContents.
  PageAgent* Agent();
  // Keeps the page's console and network for an agent: at once on a live page,
  // and on one still being made from the moment it goes live, before its first
  // load.
  bool ObserveActivity(bool observing);
  bool OpenInspector(std::optional<engine::InspectorPanel> panel);
  bool CloseInspector();
  bool Inspected() const;
  engine::InspectorLayout LayoutInspector(double width, double height) const;
  engine::CertificateChain CertificateChain() const;
  bool SetSitePermission(engine::SitePermission permission, std::optional<bool> allowed);
  // How often the same server and realm asked in this document before now.
  int AuthenticationAttempt(const std::string& challenge);
  // The review a Chrome Web Store listing's request began finished.
  bool FinishStoreRequest();
  // The engine's extensions changed, which a store listing's button shows.
  void RefreshStore();

  // What the engine's own hooks say about the page.
  void FullscreenChanged(bool active);
  void HoverChanged(const GURL& url);
  void SiteIndicatorsChanged();
  // The engine offered, relaid or withdrew the docked inspector, or the
  // inspector is going away.
  void InspectorChanged();
  void InspectorClosing();

  // What the page shows changed; it reports once this turn ends.
  void StateChanged();
  // Reports what the page shows, when it differs from the last report. The
  // binding calls it once the turn in which it changed ends.
  void ReportState();

 private:
  struct StagedNavigation {
    std::string token;
    std::string url;
  };
  struct FoundIcon {
    std::vector<uint8_t> png;
    std::string url;
    // The icon file the image shows, the engine's own image of that file
    // when it reported it, and the image's longest edge in pixels.
    GURL source;
    SkBitmap artwork;
    int pixels = 0;
  };

  // content::WebContentsObserver:
  void DidStartNavigation(content::NavigationHandle* navigation) override;
  void DidRedirectNavigation(content::NavigationHandle* navigation) override;
  void DidFinishNavigation(content::NavigationHandle* navigation) override;
  void DidStartLoading() override;
  void DidStopLoading() override;
  void TitleWasSet(content::NavigationEntry* entry) override;
  void NavigationEntriesDeleted() override;
  void DidChangeVisibleSecurityState() override;
  void DidChangeThemeColor() override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) override;
  void DidGetUserInteraction(const blink::WebInputEvent& event) override;
  void PrimaryMainDocumentElementAvailable() override;
  void DOMContentLoaded(content::RenderFrameHost* frame) override;
  void CrestKeySystemUnavailable(content::RenderFrameHost* frame, const std::string& key_system) override;
  void OnAudioStateChanged(bool audible) override;
  void DidUpdateAudioMutingState(bool muted) override;
  void MediaStartedPlaying(const MediaPlayerInfo& info, const content::MediaPlayerId& id) override;
  void MediaStoppedPlaying(const MediaPlayerInfo& info,
                           const content::MediaPlayerId& id,
                           content::WebContentsObserver::MediaStoppedReason reason) override;
  void MediaPictureInPictureChanged(bool is_picture_in_picture) override;
  void WebContentsDestroyed() override;

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver* driver,
                        NotificationIconType type,
                        const GURL& icon_url,
                        bool icon_url_changed,
                        const gfx::Image& image) override;

  // find_in_page::FindResultObserver:
  void OnFindResultAvailable(content::WebContents* contents) override;
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper* helper) override;

  void ApplyZoom();
  void Present(engine::EnginePresentation presentation);
  // Presents the page's part in tab sharing.
  void PresentSharing();
  // Presents what the page's view shows that changed since it last did.
  void PresentView();
  // The page's committed history, oldest first, with each entry's identity,
  // as the core keeps it; empty before the page committed a document.
  engine::PageHistoryReported History();
  // Reports the page's history when it differs from the last report.
  void ReportHistory();
  // The identity of `entry`, made when the page first reports it.
  engine::Guid EntryId(content::NavigationEntry* entry);

  // The engine's own callbacks, as navigation events.
  void Navigate(const std::string& url);
  bool RestoreNow(const std::vector<uint8_t>& state, const std::string& expected_url);
  void Started(const std::string& url);
  void Committed(const std::string& url);
  void Finished(const std::string& url);
  void Failed(engine::PageFailure failure);
  void Interrupted();
  void MovedWithinDocument(const std::string& url);
  void TitleChanged();
  void NoteTitle();
  void FinishIfLoaded();
  void Settle();
  void CancelSettling();
  void PublishIcon(const gfx::Image& image, const GURL& icon_url);
  void FetchSharperIcon(const GURL& icon_url, const SkBitmap& artwork);
  void SetIcon(const SkBitmap& bitmap, const GURL& icon_url, const SkBitmap& artwork);
  void UpdateTheme();
  void ReportIcon();
  void Report(engine::EngineEvent event);
  engine::PageSnapshot Snapshot() const;
  std::string Title() const;
  engine::PageSecurity Security() const;
  // The engine is about to load the address a page was asked for and shows
  // its initial blank document meanwhile, which is nothing the page shows.
  bool ShowsInitialBlank(const GURL& url) const;

  const raw_ref<EngineBinding> binding_;
  const engine::Guid id_;
  const std::string key_;
  const std::string profile_;
  const bool is_private_;
  std::string window_;
  Phase phase_ = Phase::kCreating;
  // Primary main-frame navigations to a new document started, and main-frame
  // commits, since the page began.
  uint64_t navigation_generation_ = 0;
  uint64_t navigation_revision_ = 0;

  // What the app asked for before the page existed.
  std::optional<std::string> pending_load_;
  std::optional<StagedNavigation> staged_;
  std::optional<std::vector<uint8_t>> pending_state_;

  // Where a navigation that has not committed is heading.
  std::optional<std::string> pending_url_;
  // The document's address as last reported.
  std::optional<std::string> document_url_;
  // The navigation to a new document the engine is running, by its ID.
  std::optional<int64_t> loading_navigation_;
  // A new document committed and has not finished loading.
  bool awaits_finish_ = false;
  // The core asked whether the page may go and waits for the answer.
  bool checks_before_unload_ = false;
  // The title last reported.
  std::string reported_title_;
  // The move within the document waiting for its title, and the latest
  // moment it may finish.
  std::optional<std::string> settling_url_;
  base::TimeTicks settle_deadline_;
  base::OneShotTimer settle_timer_;
  // The image the engine found for the document, and the colour the page's
  // theme puts behind it.
  std::optional<FoundIcon> icon_;
  std::optional<engine::TabIconAccent> accent_;
  // The latest icon or document, which a sharper copy of an earlier icon no
  // longer stands for.
  uint64_t icon_generation_ = 0;
  // The page changed since its last snapshot, which is due when the turn ends.
  bool report_due_ = false;
  std::optional<engine::PageSnapshot> reported_;
  std::optional<engine::PageHistoryReported> reported_history_;
  // The core's identity of each entry the page keeps, by the entry's unique
  // id, which lasts as long as the entry does.
  std::map<int, engine::Guid> entry_ids_;
  // The identity the entry the core's load commits takes, and that load once
  // it starts. The load gives the identity up however it ends, and any other
  // navigation that starts first, or a load that never starts, drops it.
  std::optional<engine::Guid> expected_entry_id_;
  std::optional<int64_t> expected_entry_navigation_;

  // The zoom the platform asked for, which a page still being created takes
  // once it exists.
  std::optional<double> zoom_;
  // The engine's find, and whether a find waits for its count.
  raw_ptr<find_in_page::FindTabHelper> find_helper_ = nullptr;
  bool find_pending_ = false;
  std::unique_ptr<PageDocuments> documents_;
  std::unique_ptr<PageMedia> media_;
  std::unique_ptr<PageInfoBars> infobars_;
  std::unique_ptr<PageInspector> inspector_;
  std::unique_ptr<PageContent> content_;
  std::unique_ptr<PageAgent> agent_;
  bool observes_activity_ = false;
  std::unique_ptr<PageStore> store_;

  // What the page's view showed when it was last presented.
  std::optional<bool> presented_loading_;
  std::optional<std::optional<engine::BrandColor>> presented_theme_;
  // How many pop-ups the engine blocked in the document when last presented.
  size_t presented_blocked_popups_ = 0;
  // How often each server and realm asked for a password in this document.
  std::map<std::string, int> authentication_attempts_;
  base::TimeTicks last_interaction_;
  base::WeakPtrFactory<EnginePage> weak_factory_{this};
};

// An engine address in Crest's namespace, where `chrome://` is `crest://`.
std::string PresentedURL(const GURL& url);
// A Crest address as the engine loads it.
GURL EngineURL(const std::string& url);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_PAGE_H_
