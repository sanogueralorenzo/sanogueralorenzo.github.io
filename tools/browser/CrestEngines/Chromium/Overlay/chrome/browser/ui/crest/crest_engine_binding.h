#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_BINDING_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_BINDING_H_

#include <array>
#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/callback_forward.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ptr_exclusion.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "chrome/browser/ui/crest/crest_engine.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "components/permissions/permission_prompt.h"

class GURL;
class Profile;

namespace content {
class NavigationHandle;
class NavigationThrottle;
class NavigationThrottleRegistry;
class WebContents;
struct OpenURLParams;
}

namespace crest {

class EngineBrowsers;
class EngineDownloads;
class EngineExtensions;
class EngineNotifications;
class EnginePage;
class EngineProfiles;
class EnginePrompts;
class EngineTabGroups;

// Chromium's engine binding: the portable half of Crest's Chromium host, in
// C++ and Chromium's own types with no Objective-C, so it serves every
// platform. It implements crest_engine.h. The core hands it commands through
// the table's `run` and it reports what the engine does with each page
// straight to the core, through the function `attach` gave it. It keeps
// Chromium's Browsers too (see EngineBrowsers): which Browser each page is
// in, and when each opens and closes. Each platform's shell makes the windows
// they are built on, embeds the pages' views and does what only the operating
// system can.
//
// The platform reaches the binding directly through a second table,
// crest_engine_pages_t: it asks a page's engine for view work with a
// PageRequest, answered at once, and hears what finishes later, such as a
// find's count or an export, as an EnginePresentation.
//
// Everything runs on Chromium's UI thread. The core delivers the commands a
// report causes before the report returns, and a command such as ClosePage
// must never destroy a WebContents inside one of its own observers, so no
// report is made on the stack of a Chromium callback: reports and
// presentations queue, and one task posted to the UI thread sends them in
// order. A page's snapshot is sent last in the turn in which it changed. A
// question, such as what a click on a link does, is asked on the engine's own
// stack, because the engine waits for the answer; the core answers at once
// and changes nothing.
//
// A page the engine opens by itself is offered to the core, which adopts it
// for a tab it opens or refuses it. A link that opens in Peek is presented to
// the platform, and a modified click's link is staged here, keeping the
// referrer, initiator and security Chromium verified, until the Peek's page
// loads it or it is dropped.
class EngineBinding {
 public:
  // Where a Browser the engine created for itself belongs: the Crest window
  // the platform reserved for it and the Space its tabs join.
  struct WindowPlacement {
    std::string window;
    std::string space;
  };

  // What only the platform does for the binding: its windows and the views
  // it hosts. Each Browser the binding keeps is built on the platform's own
  // BrowserWindow, which Chromium's window factory makes for it, since a
  // Browser takes no window from its creator outside tests; the shell makes
  // and opens the Crest windows those BrowserWindows show in.
  class Shell {
   public:
    virtual ~Shell() = default;
    // Reserves the Crest window a Browser the engine created for itself in
    // `profile` belongs in, and names the Space its tabs join. Crest is one
    // window: only a Browser `chrome.windows.create` asked for (`own_window`)
    // gets another, and any other joins the window the person is using. None
    // when no Space can host the profile's tabs.
    virtual std::optional<WindowPlacement> ReserveWindow(const std::string& profile, bool own_window) = 0;
    // Opens the window reserved as `placement`, showing its Space, just before
    // its first tab is offered; in front when `focused`.
    virtual void PresentWindow(const WindowPlacement& placement, bool focused) = 0;
    // Drops the views the shell hosts beside `page`, whose WebContents the
    // binding destroys next.
    virtual void ReleasePage(const std::string& page) = 0;
    // Hosts the view of the inspector docked on `page`, or none when
    // `frontend` is null.
    virtual void DockInspector(const std::string& page, content::WebContents* frontend) = 0;
    // Closes what the shell hosts for `profile`, which is being let go of,
    // apart from its pages.
    virtual void ReleaseProfile(const std::string& profile) = 0;
    // Closes the side panels the shell hosts for `extension` in `profile`'s
    // pages, or only for the tab `tab` names.
    virtual void RetractSidePanels(Profile* profile, const std::string& extension, std::optional<int> tab) = 0;
  };

  static EngineBinding& Get();

  EngineBinding(const EngineBinding&) = delete;
  EngineBinding& operator=(const EngineBinding&) = delete;

  // The function table the platform registers with the core, the engine
  // contract the binding was built against, which the core checks, and the
  // platform's direct path to the binding.
  crest_engine_binding_t Table();
  static const std::array<uint8_t, 32>& Fingerprint();
  crest_engine_pages_t Pages();

  void SetShell(Shell* shell);
  // The platform's shell, or nullptr before it hosts Crest.
  Shell* shell() const { return shell_; }
  // The engine is shutting down: nothing more is reported, every page is let
  // go of without a report, the Browsers close and the profiles go.
  void Dispose();

  // The engine opened `contents` by itself, in the Browser of the Crest
  // window `window`, which the engine created for the Space `space` when
  // that is not empty; `foreground` when the engine brought it to the front.
  // The core hears the offer, and adopts or refuses it.
  void Offer(content::WebContents* contents, const std::string& window, const std::string& space, bool foreground);
  // A person's click on a link with a modifier key or the middle button in
  // `contents`, which Chromium verified: the core decides whether it opens a
  // tab in front or behind, which `params` then asks of the engine, or Peek,
  // for which the link is staged. Answers whether the binding took the link.
  bool FollowModifiedLink(content::WebContents* contents, content::OpenURLParams& params);
  // A person's plain click on the link to `url` in `contents`: answers
  // whether it opens Peek instead, as the core decides for a link leaving a
  // saved tab's site, which the platform then hears.
  bool KeepsLinkForPeek(content::WebContents* contents, const GURL& url);
  // A person's plain click on a link that opens in a window of its own, such
  // as one with target="_blank", whose WebContents the engine made for
  // `navigation`: answers whether it opens Peek instead, as the core decides
  // for the page the link was in. The window is then withheld from the core
  // and closes.
  bool KeepsWindowLinkForPeek(content::NavigationHandle& navigation);
  // Whether `contents` is a window whose link opened in Peek, which the core
  // is never offered.
  bool Withholds(content::WebContents* contents) const;
  // The throttle that asks, for each plain click on a link in a page.
  static std::unique_ptr<content::NavigationThrottle> LinkThrottle(content::NavigationThrottleRegistry& registry);

  // The page that follows `contents`, for the engine's own hooks, or nullptr
  // when no page does.
  EnginePage* PageFor(content::WebContents* contents);
  // The page the platform names `page`, or nullptr.
  EnginePage* Find(const std::string& page);
  // Every page the binding follows that has its WebContents.
  std::vector<EnginePage*> LivePages();
  // Lets `page`'s WebContents go at once, as a closing window does: the shell
  // drops the views beside it and its Browser deletes it, and the page hears
  // it is gone as if the engine had closed it.
  void DestroyPage(const std::string& page);
  // Lets a profile go, as a closing private window does: its Browsers close
  // with every page in them, its extensions are forgotten and the engine
  // releases it, destroying a private one.
  void ReleaseProfile(const std::string& profile);
  // The Browsers the binding keeps.
  EngineBrowsers& Browsers();
  // The tab groups in their tab strips.
  EngineTabGroups& TabGroups();
  // The tab groups an extension changed report once the turn ends.
  void ReportTabGroupsSoon();
  // The engine's extensions changed, which Chrome Web Store listings show.
  void RefreshStoreListings();
  // The shell hosts the view of the inspector docked on `page`, or none.
  void DockInspector(const std::string& page, content::WebContents* frontend);
  // The engine profiles, and every profile's extensions.
  EngineProfiles& Profiles();
  EngineExtensions& Extensions();
  // The engine's downloads in Crest's profiles.
  EngineDownloads& Downloads();
  bool disposing() const { return disposing_; }
  // What the binding's pages ask the person.
  EnginePrompts& Prompts();
  // The notifications the binding's pages post.
  EngineNotifications& Notifications();
  // The prompt for a permission request in the page that shows `contents`,
  // or nullptr when no page shows it or Crest's record does not cover it.
  std::unique_ptr<permissions::PermissionPrompt> PermissionPrompt(
      content::WebContents* contents,
      permissions::PermissionPrompt::Delegate* delegate);
  // The engine asks for an extension's side panel beside `page`.
  void RequestSidePanel(const std::string& page, const std::string& extension, engine::SidePanelRequest request);

  // For the binding's pages.
  void Report(engine::EngineEvent event);
  void Present(engine::EnginePresentation presentation);
  void ReportStateSoon(const std::string& page);
  void PageLost(const std::string& page);
  // Loads the link staged as `token` in `page`, heading to `url`, as the
  // page's first load, while the page the link was followed in still shows
  // the document it was in. False, and the link is gone, when it no longer
  // applies.
  bool LoadStagedLink(const std::string& page, const std::string& token, const GURL& url);
  void DropStagedLink(const std::string& token);

 private:
  friend class base::NoDestructor<EngineBinding>;

  // A page the engine opened by itself, until the core adopts or refuses it.
  struct OfferedPage {
    base::WeakPtr<content::WebContents> contents;
    std::string profile;
  };
  // A link followed in `source`, kept for a Peek's first load.
  struct StagedLink;

  EngineBinding();
  ~EngineBinding();

  // What `engine` answers `question`, or nothing when it could not answer.
  template <typename Question>
  std::optional<typename engine::EngineQuestionAnswer<Question>::Type> Ask(const Question& question);
  static void CREST_CALL Answered(void* context, const uint8_t* answer, size_t length);

  // What the binding sends once the turn ends: a report to the core or a
  // presentation to the platform, encoded.
  struct Outgoing {
    bool to_core;
    std::vector<uint8_t> message;
  };

  static void CREST_CALL Attach(void* context,
                                uint64_t app,
                                uint64_t engine,
                                crest_engine_report_t report,
                                crest_engine_ask_t ask);
  static void CREST_CALL Run(void* context, const uint8_t* command, size_t length);
  static crest_status_t CREST_CALL Request(void* context, const uint8_t* request, size_t length, crest_buffer_t* out);
  static void CREST_CALL Release(void* context, crest_buffer_t* buffer);
  static void CREST_CALL PresentTo(void* context, crest_engine_present_t present, void* ui);

  // Each request, handled where it lands.
  bool Handle(const engine::ReloadPage& request);
  bool Handle(const engine::StopLoading& request);
  bool Handle(const engine::ZoomPage& request);
  bool Handle(const engine::FindInPage& request);
  bool Handle(const engine::CapturePage& request);
  bool Handle(const engine::ExportPage& request);
  engine::InteractionState Handle(const engine::SaveInteractionState& request);
  bool Handle(const engine::RestoreInteractionState& request);
  bool Handle(const engine::MovePageToWindow& request);
  bool Handle(const engine::ShowPage& request);
  bool Handle(const engine::HidePage& request);
  engine::PageIconImage Handle(const engine::PageIcon& request);
  bool Handle(const engine::WatchPage& request);
  engine::PageMediaState Handle(const engine::PageMedia& request);
  bool Handle(const engine::EnterPictureInPicture& request);
  bool Handle(const engine::ActivateMediaSession& request);
  bool Handle(const engine::PerformMediaAction& request);
  bool Handle(const engine::MuteMediaSession& request);
  bool Handle(const engine::ObserveAudioSpectrum& request);
  bool Handle(const engine::AnswerInfoBar& request);
  bool Handle(const engine::RefreshPageIcon& request);
  bool Handle(const engine::ShowBlockedPopups& request);
  bool Handle(const engine::AddContentScript& request);
  bool Handle(const engine::EvaluateContentScript& request);
  bool Handle(const engine::EvaluatePageScript& request);
  bool Handle(const engine::ClickPage& request);
  bool Handle(const engine::HoverPage& request);
  bool Handle(const engine::ScrollPage& request);
  bool Handle(const engine::TypeInPage& request);
  bool Handle(const engine::PressKeyInPage& request);
  bool Handle(const engine::ObservePageActivity& request);
  engine::PageConsoleLog Handle(const engine::ReadPageConsole& request);
  engine::PageNetworkLog Handle(const engine::ReadPageNetwork& request);
  bool Handle(const engine::HoldPageRendering& request);
  bool Handle(const engine::RefreshStoreListing& request);
  bool Handle(const engine::OpenInspector& request);
  bool Handle(const engine::CloseInspector& request);
  bool Handle(const engine::PageInspected& request);
  engine::InspectorLayout Handle(const engine::LayoutInspector& request);
  engine::ExtensionActionList Handle(const engine::PageExtensions& request);
  engine::ExtensionActionList Handle(const engine::PinnedExtensions& request);
  engine::InstalledExtensionList Handle(const engine::InstalledExtensions& request);
  bool Handle(const engine::ChangeExtension& request);
  engine::SidePanelScope Handle(const engine::HasSidePanel& request);
  engine::CertificateChain Handle(const engine::PageCertificates& request);
  bool Handle(const engine::SetSitePermission& request);
  bool Handle(const engine::StopMediaCapture& request);
  bool Handle(const engine::ChooseShareSource& request);
  bool Handle(const engine::StopTabSharing& request);
  bool Handle(const engine::AnswerWebNotification& request);
  bool Handle(const engine::AnswerProfileNotification& request);
  bool Handle(const engine::PrepareProfile& request);

  void Perform(engine::EngineCommand command);
  // Each command, handled where it lands. `Perform` visits a command with
  // these, so a command without one fails to compile.
  void Handle(const engine::CreatePage& command);
  void Handle(const engine::LoadPage& command);
  void Handle(const engine::GoToHistoryEntry& command);
  void Handle(const engine::ClosePage& command);
  void Handle(const engine::RecoverPage& command);
  void Handle(const engine::ExitPictureInPicture& command);
  void Handle(const engine::CheckBeforeUnload& command);
  void Handle(const engine::SettleScriptDialog& command);
  void Handle(const engine::SettleAuthentication& command);
  void Handle(const engine::SettlePermission& command);
  void Handle(const engine::SettleExtensionInstall& command);
  void Handle(const engine::SettleDownloadDestination& command);
  void Handle(const engine::CancelEngineDownload& command);
  void Handle(const engine::PauseEngineDownload& command);
  void Handle(const engine::ResumeEngineDownload& command);
  void Handle(const engine::RemoveEngineDownload& command);
  void Handle(const engine::ApproveEngineDownload& command);
  void Handle(const engine::EraseProfileData& command);
  void Handle(const engine::EraseSiteData& command);
  void Handle(const engine::AdoptOfferedPage& command);
  void Handle(const engine::RejectOfferedPage& command);
  void Handle(const engine::StageNavigation& command);
  void Handle(const engine::DropStagedLink& command);
  void Handle(const engine::GroupPages& command);
  std::vector<uint8_t> Answer(const engine::PageRequest& request);
  void Create(const engine::CreatePage& creation);
  void Load(const std::string& page, const std::string& url);
  void Adopt(const engine::AdoptOfferedPage& adoption);
  void Reject(const engine::RejectOfferedPage& rejection);
  void Stage(const engine::StageNavigation& staging);
  // Stages a link a person followed in `page` for the Peek it opens.
  bool StageForPeek(EnginePage& page, content::OpenURLParams& params);
  // Presents `request` once the turn ends, while `page` still shows the
  // document the link was in; a link staged for it is dropped otherwise.
  void PresentPeekSoon(const EnginePage& page, engine::PeekRequested request);
  void PresentPeek(const std::string& page, uint64_t revision, uint64_t generation, engine::PeekRequested request);
  // Drops the links followed in `page`, which is going.
  void DropStagedLinksFrom(const std::string& page);
  // Closes a withheld window once its Browser holds it; one not in a Browser
  // yet closes when it is offered.
  void CloseWithheld(base::WeakPtr<content::WebContents> contents);
  // Forgets the links modified clicks sent to new tabs this turn.
  void ForgetRoutedTabs();
  void CreateNow(const std::string& page);
  void ProfileLoaded(const std::string& page, Profile* profile);
  void Created(const std::string& page, content::WebContents* contents);
  void Live(EnginePage& page, content::WebContents* contents);
  void Close(const engine::ClosePage& closing);
  // Erases what the engine keeps for a profile the core names, all of it or
  // one site's, whether or not any page shows it, and reports DataErased.
  void Erase(const engine::EraseProfileData& erasing);
  void Erase(const engine::EraseSiteData& erasing);
  void Forget(const std::string& page);
  // Destroys `contents`, the WebContents of `page`, after the shell drops
  // the views beside it.
  void DestroyContents(const std::string& page, content::WebContents* contents);
  void ScheduleFlush();
  void Flush();

  raw_ptr<Shell> shell_ = nullptr;
  uint64_t app_ = 0;
  uint64_t engine_ = 0;
  crest_engine_report_t report_ = nullptr;
  crest_engine_ask_t ask_ = nullptr;
  crest_engine_present_t present_ = nullptr;
  // The platform's own, handed back with each presentation.
  RAW_PTR_EXCLUSION void* ui_ = nullptr;
  bool disposing_ = false;
  std::map<std::string, std::unique_ptr<EnginePage>> pages_;
  // The pages the engine could not create, until the core closes them, so a
  // platform that comes to one late still hears it has no view.
  std::set<std::string> failed_;
  // The pages the engine offered, by offer, and the links staged, by link.
  std::map<std::string, OfferedPage> offers_;
  std::map<std::string, std::unique_ptr<StagedLink>> staged_links_;
  // The windows whose link opened in Peek, until they close.
  std::vector<base::WeakPtr<content::WebContents>> withheld_;
  // The links modified clicks sent to the new tabs the engine opens next,
  // with the pages they were followed in, until the turn ends.
  std::vector<std::pair<std::string, std::string>> routed_tabs_;
  std::unique_ptr<EngineProfiles> profiles_;
  std::unique_ptr<EngineBrowsers> browsers_;
  std::unique_ptr<EngineTabGroups> tab_groups_;
  std::unique_ptr<EngineExtensions> extensions_;
  std::unique_ptr<EngineDownloads> downloads_;
  std::unique_ptr<EnginePrompts> prompts_;
  std::unique_ptr<EngineNotifications> notifications_;
  std::deque<Outgoing> queue_;
  std::vector<std::string> due_;
  bool flush_posted_ = false;
  bool flushing_ = false;
  base::WeakPtrFactory<EngineBinding> weak_factory_{this};
};

// The engine fired `contents`'s beforeunload. Answers whether the core had
// asked the page, which then hears `proceed`. A beforeunload the core did not
// ask for, from a close the engine began itself such as an extension's
// `chrome.tabs.remove`, stays with Chromium's own unload controller; a
// script's `window.close()` asks its own document before the page asks the
// core (see `RequestPageClose`).
bool AnswerBeforeUnload(content::WebContents* contents, bool proceed);

// A GUID as the platform spells it: uppercase hexadecimal in RFC 4122 groups.
std::string GuidText(const engine::Guid& guid);
// The GUID `text` spells in RFC 4122 groups, in either case, or nothing.
std::optional<engine::Guid> ParseGuid(const std::string& text);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_BINDING_H_
