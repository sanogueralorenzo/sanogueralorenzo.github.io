#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_SCREEN_SHARING_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_SCREEN_SHARING_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/media/webrtc/desktop_media_picker.h"
#include "chrome/browser/media/webrtc/media_stream_ui.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "content/public/browser/desktop_media_id.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/media_stream_request.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents_observer.h"
#include "third_party/webrtc/modules/desktop_capture/desktop_capturer.h"
#include "url/gurl.h"

namespace content {
class WebContents;
}

namespace infobars {
class InfoBar;
}

namespace crest {

// A page's getDisplayMedia() in Crest. The core decides first whether the
// page's site may ask, from its Space's choices. The platform then offers the
// person the tabs of the page's profile, and the system's own sharing picker
// for a window or a display. A tab is the engine's own to capture; the
// system's picker asks the person which window or display to share. Either
// choice is the consent, and neither needs Screen Recording access, so nothing
// lists or captures the screen before the person picks, and nothing asks the
// system for access. A window or display reaches the page as the picker's
// session, which the engine captures with the filter the system handed it.
// The question lasts only while the document that asked stays in its page,
// as Chrome's picker closes with the page.
class ScreenSharingPicker final : public DesktopMediaPicker, public content::WebContentsObserver {
 public:
  explicit ScreenSharingPicker(const content::MediaStreamRequest& request);
  ScreenSharingPicker(const ScreenSharingPicker&) = delete;
  ScreenSharingPicker& operator=(const ScreenSharingPicker&) = delete;
  // A request that ends before the person chose takes back what it asked:
  // the core's question, the platform's offer of tabs, or the system's
  // picker.
  ~ScreenSharingPicker() override;

  // DesktopMediaPicker:
  void Show(const Params& params,
            std::vector<std::unique_ptr<DesktopMediaList>> source_lists,
            DoneCallback done_callback) override;

  // The person answered the offer this picker presented. False when the
  // answer cannot be carried out, which refuses the request.
  bool Choose(const engine::ChooseShareSource& choice);

 private:
  // content::WebContentsObserver:
  void RenderFrameHostStateChanged(content::RenderFrameHost* render_frame_host,
                                   content::RenderFrameHost::LifecycleState old_state,
                                   content::RenderFrameHost::LifecycleState new_state) override;

  void Answered(bool proceeds);
  // Offers the tabs the page may share, or goes on to the system's picker
  // when there are none.
  void Offer();
  void OpenSystemPicker();
  void Opened(content::DesktopMediaID::Id session);
  void Chosen(webrtc::DesktopCapturer::Source source);
  void Finish(DoneCallbackArgumentType result);
  // Takes the platform's offer of tabs down, so no answer reaches it.
  void WithdrawOffer();
  // The pages the request may share as a tab.
  std::vector<content::WebContents*> ShareableTabs() const;

  // The document that asked, and what it asked for.
  const GURL origin_;
  const content::GlobalRenderFrameHostId requester_;
  const bool excludes_own_tab_;
  const bool asks_audio_;
  DoneCallback done_;
  // The page that asked, once a page Crest shows asked.
  std::optional<engine::Guid> page_;
  // The core's question while it waits.
  std::optional<engine::Guid> question_;
  // The platform's offer of tabs while it waits.
  std::optional<engine::Guid> offer_;
  // The system picker's session once it opened.
  std::optional<content::DesktopMediaID::Id> session_;
  bool chosen_ = false;
  base::WeakPtrFactory<ScreenSharingPicker> weak_factory_{this};
};

// Runs the person's answer to a ScreenSharingPicker's offer. False when no
// request waits for it any more.
bool AnswerShareChoice(const engine::ChooseShareSource& choice);

// Stops every tab sharing `contents` takes part in, as the shared tab or as
// the page that shares one. False when it takes part in none.
bool StopTabSharing(content::WebContents* contents);

// A tab one of Crest's pages shares, while the capture lasts. The shared tab
// and the page that captures it each carry a bar that says so and stops the
// sharing, which the platform shows as it shows the engine's other bars, and
// the shared tab's page stays loaded however long nobody looks at it.
class TabSharingIndicator final : public MediaStreamUI {
 public:
  TabSharingIndicator(content::WebContents* capturer,
                      const content::DesktopMediaID& media_id,
                      std::u16string application_title);
  TabSharingIndicator(const TabSharingIndicator&) = delete;
  TabSharingIndicator& operator=(const TabSharingIndicator&) = delete;
  ~TabSharingIndicator() override;

  // MediaStreamUI:
  gfx::NativeViewId OnStarted(base::OnceClosure stop_callback,
                              content::MediaStreamUI::SourceCallback source_callback,
                              const std::vector<content::DesktopMediaID>& media_ids) override;

  // The indicators whose sharing lasts now.
  static std::vector<base::WeakPtr<TabSharingIndicator>>& Started();
  // Whether `contents` is the shared tab or the page that shares it.
  bool Involves(content::WebContents* contents) const;
  // Stops the sharing: the stream ends, which lets this indicator go.
  void Stop();

 private:
  class SharingBar;
  // A bar the indicator shows, and the delegate that tells it the bar went.
  struct Shown {
    raw_ptr<const SharingBar> delegate;
    raw_ptr<infobars::InfoBar> bar;
  };

  void Add(content::WebContents* contents, std::u16string message);
  // The bar `delegate` belongs to went, with its page or on its own.
  void Removed(const SharingBar* delegate);
  // Tells the shared tab's page and the page that shares it that the
  // sharing began or ended.
  void MarkShared(bool shared);

  const base::WeakPtr<content::WebContents> capturer_;
  const base::WeakPtr<content::WebContents> shared_;
  const std::u16string application_title_;
  base::OnceClosure stop_;
  std::vector<Shown> bars_;
  bool started_ = false;
  base::WeakPtrFactory<TabSharingIndicator> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_SCREEN_SHARING_H_
