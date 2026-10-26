#include "chrome/browser/ui/crest/crest_engine_screen_sharing.h"

#include <CoreGraphics/CoreGraphics.h>

#include <algorithm>
#include <map>
#include <utility>

#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "base/types/expected.h"
#include "chrome/browser/infobars/confirm_infobar_creator.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "chrome/browser/ui/crest/crest_engine_prompts.h"
#include "chrome/grit/generated_resources.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/desktop_capture.h"
#include "content/public/browser/media_stream_request.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_media_capture_id.h"
#include "media/base/media_switches.h"
#include "third_party/blink/public/mojom/mediastream/media_stream.mojom.h"
#include "third_party/webrtc/modules/desktop_capture/desktop_capture_types.h"
#include "ui/base/l10n/l10n_util.h"
#include "url/origin.h"

namespace crest {

namespace {

using blink::mojom::MediaStreamRequestResult;
using content::DesktopMediaID;

// A refusal the page hears as NotAllowedError.
DesktopMediaPicker::DoneCallbackArgumentType Refusal(MediaStreamRequestResult result) {
  return base::unexpected(result);
}

// Closes the system picker's session `session` when no capture holds it.
void CloseSession(DesktopMediaID::Id session) {
  content::GetIOThreadTaskRunner({})->PostTask(
      FROM_HERE, base::BindOnce(&content::desktop_capture::CloseNativeScreenCapturePicker,
                                DesktopMediaID(DesktopMediaID::TYPE_NONE, session)));
}

// The pickers whose offer of tabs waits for the person, by offer.
std::map<engine::Guid, ScreenSharingPicker*>& Offers() {
  static base::NoDestructor<std::map<engine::Guid, ScreenSharingPicker*>> offers;
  return *offers;
}

// An origin as the person reads it, as Chrome's sharing bar names it.
std::u16string SiteName(const url::Origin& origin) {
  return url_formatter::FormatOriginForSecurityDisplay(origin, url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS);
}

// The tab `media_id` names, while it exists.
content::WebContents* SharedTab(const DesktopMediaID& media_id) {
  content::RenderFrameHost* frame = content::RenderFrameHost::FromID(
      media_id.web_contents_id.render_process_id, media_id.web_contents_id.main_render_frame_id);
  return frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
}

// A tab named as its sidebar row names it: its title, or its site when it
// has none.
std::u16string TabName(content::WebContents* tab) {
  const std::u16string title = tab->GetTitle();
  return title.empty() ? SiteName(tab->GetPrimaryMainFrame()->GetLastCommittedOrigin()) : title;
}

}  // namespace

ScreenSharingPicker::ScreenSharingPicker(const content::MediaStreamRequest& request)
    : origin_(request.security_origin),
      requester_(request.render_process_id, request.render_frame_id),
      excludes_own_tab_(request.exclude_self_browser_surface),
      asks_audio_(request.audio_type == blink::mojom::MediaStreamType::DISPLAY_AUDIO_CAPTURE) {}

ScreenSharingPicker::~ScreenSharingPicker() {
  if (question_ && !EngineBinding::Get().disposing()) {
    EngineBinding::Get().Prompts().WithdrawShare(*question_);
  }
  WithdrawOffer();
  if (session_ && !chosen_) {
    CloseSession(*session_);
  }
}

void ScreenSharingPicker::Show(const Params& params,
                               std::vector<std::unique_ptr<DesktopMediaList>> source_lists,
                               DoneCallback done_callback) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  done_ = std::move(done_callback);
  // Only a page Crest shows has a Space whose choices answer it. The refusal
  // is posted, since the caller still holds this picker.
  EnginePage* page = params.web_contents ? EngineBinding::Get().PageFor(params.web_contents) : nullptr;
  if (!page) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&ScreenSharingPicker::Finish, weak_factory_.GetWeakPtr(),
                                  Refusal(MediaStreamRequestResult::PERMISSION_DENIED)));
    return;
  }
  page_ = page->id();
  Observe(params.web_contents);
  question_ = EngineBinding::Get().Prompts().AskToShareScreen(
      page->id(), origin_, params.web_contents->GetLastCommittedURL(),
      base::BindOnce(&ScreenSharingPicker::Answered, weak_factory_.GetWeakPtr()));
}

// The document that asked left its page before the person chose, as a
// navigation that keeps it in the back/forward cache does without ending the
// request. The question goes with the page, as Chrome's picker closes with
// it, so no answer reaches a document the person no longer sees: the core's
// question and the offer of tabs are taken back at once, and the refusal is
// posted, since a navigation is running.
void ScreenSharingPicker::RenderFrameHostStateChanged(content::RenderFrameHost* render_frame_host,
                                                      content::RenderFrameHost::LifecycleState old_state,
                                                      content::RenderFrameHost::LifecycleState new_state) {
  if (chosen_ || render_frame_host->GetGlobalId() != requester_ ||
      old_state != content::RenderFrameHost::LifecycleState::kActive ||
      new_state == content::RenderFrameHost::LifecycleState::kActive) {
    return;
  }
  Observe(nullptr);
  if (question_ && !EngineBinding::Get().disposing()) {
    EngineBinding::Get().Prompts().WithdrawShare(*question_);
  }
  question_.reset();
  WithdrawOffer();
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&ScreenSharingPicker::Finish, weak_factory_.GetWeakPtr(),
                                Refusal(MediaStreamRequestResult::PERMISSION_DENIED)));
}

// The core answered: a Space that blocks the site refuses it, and otherwise
// the person chooses what to share.
void ScreenSharingPicker::Answered(bool proceeds) {
  question_.reset();
  if (!proceeds) {
    Finish(Refusal(MediaStreamRequestResult::PERMISSION_DENIED));
    return;
  }
  Offer();
}

// The platform asks the person first whether to share one of the tabs, which
// the engine captures itself, or a window or a display.
void ScreenSharingPicker::Offer() {
  const std::vector<content::WebContents*> tabs = ShareableTabs();
  if (tabs.empty() || !page_) {
    OpenSystemPicker();
    return;
  }
  engine::ShareSourcesOffered offered{.page_id = *page_,
                                      .share_id = RandomGuid(),
                                      .site = base::UTF16ToUTF8(SiteName(url::Origin::Create(origin_))),
                                      .audio = asks_audio_};
  for (content::WebContents* contents : tabs) {
    EnginePage* tab = EngineBinding::Get().PageFor(contents);
    const GURL& url = contents->GetLastCommittedURL();
    offered.tabs.push_back(engine::ShareableTab{
        .page_id = tab->id(),
        .title = base::UTF16ToUTF8(contents->GetTitle()),
        .url = url.is_valid() ? std::optional<std::string>(PresentedURL(url)) : std::nullopt,
        .icon = tab->icon()});
  }
  offer_ = offered.share_id;
  Offers()[*offer_] = this;
  EngineBinding::Get().Present(std::move(offered));
}

// The system's picker asks the person. It offers a window or a display; what
// it shows and the capture it grants are the system's own.
void ScreenSharingPicker::OpenSystemPicker() {
  auto ui = content::GetUIThreadTaskRunner({});
  content::GetIOThreadTaskRunner({})->PostTask(
      FROM_HERE,
      base::BindOnce(
          &content::desktop_capture::OpenNativeScreenCapturePicker, DesktopMediaID::TYPE_NONE,
          base::BindPostTask(ui, base::BindOnce(&ScreenSharingPicker::Opened, weak_factory_.GetWeakPtr())),
          base::BindPostTask(ui, base::BindOnce(&ScreenSharingPicker::Chosen, weak_factory_.GetWeakPtr())),
          base::BindPostTask(ui, base::BindOnce(&ScreenSharingPicker::Finish, weak_factory_.GetWeakPtr(),
                                                Refusal(MediaStreamRequestResult::PERMISSION_DENIED_BY_USER))),
          base::BindPostTask(ui, base::BindOnce(&ScreenSharingPicker::Finish, weak_factory_.GetWeakPtr(),
                                                Refusal(MediaStreamRequestResult::PERMISSION_DENIED_BY_SYSTEM)))));
}

// The person answered the offer. A tab is captured by the engine, as Chrome
// captures one, with its sound when the page asked for audio and the person
// kept it. The result is posted: the platform's request is still running, and
// the request's handler may let this picker go.
bool ScreenSharingPicker::Choose(const engine::ChooseShareSource& choice) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!offer_ || *offer_ != choice.share_id || !page_ || *page_ != choice.page_id) {
    return false;
  }
  Offers().erase(*offer_);
  offer_.reset();
  switch (choice.choice) {
    case engine::ShareSourceChoice::kCancel:
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(&ScreenSharingPicker::Finish, weak_factory_.GetWeakPtr(),
                                    Refusal(MediaStreamRequestResult::PERMISSION_DENIED_BY_USER)));
      return true;
    case engine::ShareSourceChoice::kWindowOrScreen:
      OpenSystemPicker();
      return true;
    case engine::ShareSourceChoice::kTab:
      break;
  }
  EnginePage* tab = choice.tab_page_id ? EngineBinding::Get().Find(GuidText(*choice.tab_page_id)) : nullptr;
  content::WebContents* contents = tab ? tab->web_contents() : nullptr;
  const std::vector<content::WebContents*> shareable = ShareableTabs();
  if (!contents || std::ranges::find(shareable, contents) == shareable.end()) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&ScreenSharingPicker::Finish, weak_factory_.GetWeakPtr(),
                                  Refusal(MediaStreamRequestResult::INVALID_STATE)));
    return false;
  }
  content::RenderFrameHost* main = contents->GetPrimaryMainFrame();
  DesktopMediaID chosen(DesktopMediaID::TYPE_WEB_CONTENTS, DesktopMediaID::kNullId,
                        content::WebContentsMediaCaptureId(main->GetProcess()->GetDeprecatedID(), main->GetRoutingID()));
  chosen.audio_share = asks_audio_ && choice.audio;
  chosen_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&ScreenSharingPicker::Finish, weak_factory_.GetWeakPtr(), chosen));
  return true;
}

void ScreenSharingPicker::Opened(DesktopMediaID::Id session) {
  session_ = session;
}

// The person chose in the system's picker. A display carries its ID and a
// window none; either is the picker's session, which the engine captures
// with the system's own filter. Audio is not shared: the system's picker
// offers none.
void ScreenSharingPicker::Chosen(webrtc::DesktopCapturer::Source source) {
  chosen_ = true;
  DesktopMediaID chosen(
      source.display_id != webrtc::kInvalidDisplayId ? DesktopMediaID::TYPE_SCREEN : DesktopMediaID::TYPE_WINDOW,
      source.id);
  chosen.id_type = DesktopMediaID::IdType::kNativePickerSession;
  Finish(chosen);
}

void ScreenSharingPicker::Finish(DoneCallbackArgumentType result) {
  if (done_) {
    std::move(done_).Run(std::move(result));
  }
}

void ScreenSharingPicker::WithdrawOffer() {
  if (!offer_) {
    return;
  }
  Offers().erase(*offer_);
  if (page_) {
    EngineBinding::Get().Present(engine::ShareSourcesWithdrawn{.page_id = *page_, .share_id = *offer_});
  }
  offer_.reset();
}

// The live pages of the requesting tab's profile, as Chrome offers the tabs
// of the capturer's profile. The requesting tab is one of them unless the
// document asked to leave it out.
std::vector<content::WebContents*> ScreenSharingPicker::ShareableTabs() const {
  std::vector<content::WebContents*> tabs;
  content::RenderFrameHost* requester = content::RenderFrameHost::FromID(requester_);
  content::WebContents* own = requester ? content::WebContents::FromRenderFrameHost(requester) : nullptr;
  if (!own) {
    return tabs;
  }
  for (EnginePage* page : EngineBinding::Get().LivePages()) {
    content::WebContents* contents = page->web_contents();
    if (page->phase() != EnginePage::Phase::kLive || contents->GetBrowserContext() != own->GetBrowserContext() ||
        (excludes_own_tab_ && contents == own) || contents->IsCrashed() ||
        !contents->GetPrimaryMainFrame()->IsRenderFrameLive()) {
      continue;
    }
    tabs.push_back(contents);
  }
  return tabs;
}

bool AnswerShareChoice(const engine::ChooseShareSource& choice) {
  auto found = Offers().find(choice.share_id);
  return found != Offers().end() && found->second->Choose(choice);
}

bool SharesScreenThroughSystem(const content::MediaStreamRequest& request) {
  return IsEnabled() && request.video_type == blink::mojom::MediaStreamType::DISPLAY_VIDEO_CAPTURE &&
         base::FeatureList::IsEnabled(media::kUseSCContentSharingPicker);
}

std::unique_ptr<DesktopMediaPicker> CreateScreenSharingPicker(const content::MediaStreamRequest& request) {
  return std::make_unique<ScreenSharingPicker>(request);
}

// The bar a shared tab, or the page that captures it, carries. Its one button
// stops the sharing; the bar goes when the sharing ends, not before.
class TabSharingIndicator::SharingBar final : public ConfirmInfoBarDelegate {
 public:
  SharingBar(base::WeakPtr<TabSharingIndicator> indicator, std::u16string message)
      : indicator_(std::move(indicator)), message_(std::move(message)) {}
  SharingBar(const SharingBar&) = delete;
  SharingBar& operator=(const SharingBar&) = delete;
  ~SharingBar() override {
    if (indicator_) {
      indicator_->Removed(this);
    }
  }

  // ConfirmInfoBarDelegate:
  InfoBarIdentifier GetIdentifier() const override { return TAB_SHARING_INFOBAR_DELEGATE; }
  std::u16string GetMessageText() const override { return message_; }
  int GetButtons() const override { return BUTTON_OK; }
  std::u16string GetButtonLabel(InfoBarButton button) const override {
    return l10n_util::GetStringUTF16(IDS_TAB_SHARING_INFOBAR_STOP_BUTTON);
  }
  bool Accept() override {
    if (indicator_) {
      indicator_->Stop();
    }
    return false;
  }
  bool IsCloseable() const override { return false; }
  bool ShouldExpire(const NavigationDetails& details) const override { return false; }
  bool EqualsDelegate(infobars::InfoBarDelegate* delegate) const override { return false; }

 private:
  const base::WeakPtr<TabSharingIndicator> indicator_;
  const std::u16string message_;
};

TabSharingIndicator::TabSharingIndicator(content::WebContents* capturer,
                                         const content::DesktopMediaID& media_id,
                                         std::u16string application_title)
    : capturer_(capturer ? capturer->GetWeakPtr() : base::WeakPtr<content::WebContents>()),
      shared_(SharedTab(media_id) ? SharedTab(media_id)->GetWeakPtr() : base::WeakPtr<content::WebContents>()),
      application_title_(std::move(application_title)) {}

TabSharingIndicator::~TabSharingIndicator() {
  weak_factory_.InvalidateWeakPtrs();
  std::erase_if(Started(), [](const base::WeakPtr<TabSharingIndicator>& indicator) { return !indicator; });
  if (started_) {
    MarkShared(false);
  }
  while (!bars_.empty()) {
    infobars::InfoBar* bar = bars_.back().bar;
    bars_.pop_back();
    bar->RemoveSelf();
  }
}

gfx::NativeViewId TabSharingIndicator::OnStarted(base::OnceClosure stop_callback,
                                                 content::MediaStreamUI::SourceCallback source_callback,
                                                 const std::vector<content::DesktopMediaID>& media_ids) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  stop_ = std::move(stop_callback);
  if (started_ || !shared_) {
    return 0;
  }
  started_ = true;
  Started().push_back(weak_factory_.GetWeakPtr());
  MarkShared(true);
  // The bars say where the tab goes, as Chrome's do: to the site the page
  // that captures it shows, which sends it on to the people it shares with.
  // The shared tab is named by its title, or its site when it has none.
  std::u16string site = application_title_;
  if (site.empty() && capturer_) {
    site = TabName(capturer_.get());
  }
  Add(shared_.get(), l10n_util::GetStringFUTF16(IDS_TAB_SHARING_INFOBAR_SHARING_CURRENT_TAB_LABEL, site));
  if (capturer_ && capturer_.get() != shared_.get()) {
    const std::u16string shared_name = TabName(shared_.get());
    Add(capturer_.get(),
        shared_name.empty()
            ? l10n_util::GetStringFUTF16(IDS_TAB_SHARING_INFOBAR_SHARING_ANOTHER_UNTITLED_TAB_LABEL, site)
            : l10n_util::GetStringFUTF16(IDS_TAB_SHARING_INFOBAR_SHARING_ANOTHER_TAB_LABEL, shared_name, site));
  }
  return 0;
}

void TabSharingIndicator::Add(content::WebContents* contents, std::u16string message) {
  auto* manager = infobars::ContentInfoBarManager::FromWebContents(contents);
  if (!manager) {
    return;
  }
  auto delegate = std::make_unique<SharingBar>(weak_factory_.GetWeakPtr(), std::move(message));
  const SharingBar* identity = delegate.get();
  if (infobars::InfoBar* bar = manager->AddInfoBar(CreateConfirmInfoBar(std::move(delegate)))) {
    bars_.push_back(Shown{.delegate = identity, .bar = bar});
  }
}

void TabSharingIndicator::Removed(const SharingBar* delegate) {
  std::erase_if(bars_, [delegate](const Shown& shown) { return shown.delegate == delegate; });
}

// The core keeps a shared tab's page loaded, as it keeps a page that
// captures, and both tabs show their part in it.
void TabSharingIndicator::MarkShared(bool shared) {
  if (EnginePage* page = shared_ ? EngineBinding::Get().PageFor(shared_.get()) : nullptr) {
    page->SharedChanged(shared);
  }
  if (EnginePage* page = capturer_ ? EngineBinding::Get().PageFor(capturer_.get()) : nullptr) {
    page->SharingChanged(shared);
  }
}

// The indicators whose sharing lasts now.
std::vector<base::WeakPtr<TabSharingIndicator>>& TabSharingIndicator::Started() {
  static base::NoDestructor<std::vector<base::WeakPtr<TabSharingIndicator>>> started;
  return *started;
}

bool StopTabSharing(content::WebContents* contents) {
  if (!contents) {
    return false;
  }
  // Stopping lets an indicator go, so the list is copied first.
  const std::vector<base::WeakPtr<TabSharingIndicator>> started = TabSharingIndicator::Started();
  bool stopped = false;
  for (const auto& indicator : started) {
    if (indicator && indicator->Involves(contents)) {
      indicator->Stop();
      stopped = true;
    }
  }
  return stopped;
}

bool TabSharingIndicator::Involves(content::WebContents* contents) const {
  return (shared_ && shared_.get() == contents) || (capturer_ && capturer_.get() == contents);
}

// Stopping ends the stream, and the stream's end lets this indicator go,
// which takes its bars down.
void TabSharingIndicator::Stop() {
  if (stop_) {
    std::move(stop_).Run();
  }
}

std::unique_ptr<MediaStreamUI> CreateTabSharingIndicator(content::WebContents* capturer,
                                                         const content::DesktopMediaID& media_id,
                                                         const std::u16string& application_title) {
  return std::make_unique<TabSharingIndicator>(capturer, media_id, application_title);
}

// Screen Recording access, for capture that still needs it: a whole display or
// another app's window chosen some other way than through the system's picker,
// as an extension's `chrome.desktopCapture` can. macOS applies a grant only
// after Crest reopens, so the engine asks the system once per launch, which
// raises at most one system prompt, and after a refusal answers from memory
// without asking again. The person hears once where to allow it.
bool AllowsScreenCapture(content::WebContents* contents, const content::DesktopMediaID& source) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  const bool needs_access =
      source.id_type != DesktopMediaID::IdType::kNativePickerSession &&
      (source.type == DesktopMediaID::TYPE_SCREEN ||
       (source.type == DesktopMediaID::TYPE_WINDOW && source.window_id == DesktopMediaID::kNullId));
  if (!needs_access) {
    return true;
  }
  static bool asked = false;
  static bool missing = false;
  if (missing) {
    return false;
  }
  if (CGPreflightScreenCaptureAccess()) {
    return true;
  }
  if (!asked) {
    asked = true;
    if (CGRequestScreenCaptureAccess()) {
      return true;
    }
  }
  missing = true;
  if (EnginePage* page = contents ? EngineBinding::Get().PageFor(contents) : nullptr) {
    EngineBinding::Get().Present(engine::ScreenCaptureAccessMissing{.page_id = page->id()});
  }
  return false;
}

}  // namespace crest
