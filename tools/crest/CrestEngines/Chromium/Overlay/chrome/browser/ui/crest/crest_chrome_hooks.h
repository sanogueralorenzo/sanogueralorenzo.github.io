#ifndef CHROME_BROWSER_UI_CREST_CREST_CHROME_HOOKS_H_
#define CHROME_BROWSER_UI_CREST_CREST_CHROME_HOOKS_H_

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
@class ASWebAuthenticationSessionRequest;
@protocol CrestMacUI;
#endif

#include <string>
#include <functional>
#include <memory>

class Browser;
class DesktopMediaPicker;
class MediaStreamUI;
class GURL;
class Profile;
enum class ToastId;
namespace content { class WebContents; class NavigationThrottleRegistry; class JavaScriptDialogManager; struct DesktopMediaID; struct DropData; struct MediaStreamRequest; struct OpenURLParams; }
namespace net { class AuthChallengeInfo; }
namespace views { class Widget; }

namespace crest {
// The isolated world Crest's content bridges run in. It sits at the top of
// the embedder range, far from the worlds extensions allocate upward, and the
// patched evaluator awaits promises in this world only.
inline constexpr int kContentWorldID = (1 << 29) - 1;
// The isolated world an agent's scripts run in, just below Crest's own: the
// page and Crest's content bridges never see it.
inline constexpr int kAgentWorldID = (1 << 29) - 2;
// Enabled only by the explicitly selected Crest host command-line switch.
bool IsEnabled();
// The platform's BrowserWindow for `browser` was created or destroyed. The
// engine binding keeps the Browser (see EngineBrowsers).
void OnBrowserWindowCreated(Browser* browser);
void OnBrowserWindowDestroyed(Browser* browser);
// A Browser the engine created for itself was shown. Crest opens the window it
// reserved for that Browser when the Browser's first tab is offered, so this
// only records whether `chrome.windows.create` asked for focus.
void OnEngineWindowShown(Browser* browser, bool focused);
// Whether `browser` may move, resize, hide or minimize the Crest window it
// shows in. An extension's popup that shows as a tab of the person's window
// may not.
bool OwnsWindow(const Browser* browser);
// Whether a browsing window the engine wants to create for itself has a Crest
// Space to live in. A window Crest is creating for itself always does.
//
// Answered before the Browser exists, so a request no Space can host is
// refused at the one point Chromium already reports as an error:
// `chrome.windows.create` rejects instead of leaving its promise unsettled, and
// no unowned Browser is left running with tabs to decline.
bool CanCreateEngineBrowser(Profile* profile);
void EnsureCrestUIStarted(Browser* browser);
// Chrome's AppController retains its lifecycle role. A quit waits for core saves.
bool DeferQuit();
// A Dock click or reopen with no windows. Crest activates an existing window
// or opens its initial one; Chromium creates no browser of its own.
bool Reopen();
// Hands the core a page's beforeunload answer when the core asked whether the
// page may close, without destroying the page.
bool CompletePageClosePreparation(content::WebContents* contents, bool proceed);
// A page's own script asked to close its window, as `window.close()` does.
// Crest's core decides whether a page may close itself, the same way on every
// engine, and closes it when it may, so Chromium closes nothing. False leaves
// a WebContents no Crest page follows to Chromium.
bool RequestPageClose(content::WebContents* contents);
// Whether `contents` is a Crest page, which Chromium never discards: the core
// decides when a page unloads, and a discard replaces the tab's WebContents.
bool KeepsPageResident(content::WebContents* contents);
// Whether `contents` is a Crest page running media, which Chromium never
// freezes: a video in Picture in Picture, playing or paused, sound, or a
// camera, microphone or screen capture. The core keeps such a page loaded
// however long nobody looks at it.
bool KeepsPageLoaded(content::WebContents* contents);
// Shares HTTP Basic and Digest prompts with Crest's per-Space credential flow.
// False leaves a WebContents that Crest does not own to Chromium.
bool PresentHTTPAuthentication(content::WebContents* contents, const net::AuthChallengeInfo& challenge,
    std::function<void(bool, const std::u16string&, const std::u16string&)> reply);
// Tells the shared page presentation when web content enters or leaves video
// fullscreen; the renderer still owns Escape and the fullscreen lifecycle.
void ReportContentFullscreen(content::WebContents* contents, bool active);
void SnapPictureInPictureWindow(views::Widget* window);
// Chromium asks for `contents`' window after making it its Browser's active
// tab, as a Picture in Picture window's return control does. Answers whether
// the page returns from Picture in Picture, which the core then shows in its
// own window, Space and tab; false leaves the ask to Chromium.
bool ReturnFromPictureInPicture(content::WebContents* contents);
// Called after Chromium has approved a renderer's drag request.
bool BeginLinkDrag(content::WebContents* contents, const content::DropData& data);
void AddNavigationThrottle(content::NavigationThrottleRegistry& registry);
// Chromium's toasts ("Link copied" and similar) anchor to a Views browser frame
// that this build never creates. Their message is shown as a Crest notice of
// the kind the toast is instead.
void ShowEngineNotice(const std::u16string& message, ToastId toast);
// A selection the person asked to translate. Crest shows the system's
// translation panel rather than Chromium's partial-translate bubble.
void TranslateSelection(const std::u16string& text);
// A page's site state changed — the engine blocked a pop-up, for one. Crest
// relays what its own Site Controls show.
void UpdateSiteIndicators(content::WebContents* contents);
// The link under the pointer changed; an empty URL means it left the link.
void UpdateTargetURL(content::WebContents* contents, const GURL& url);
// Extension side panels are cards in Crest's own page row, so this build never
// creates Chrome's Views side-panel UI. `chrome.sidePanel.open()`, `close()`
// and an action click that toggles a panel are routed to the card that belongs
// to `contents`. Both return false when no Crest page owns `contents`, which
// leaves Chromium's own behavior in place.
bool OpenExtensionSidePanel(content::WebContents* contents, const std::string& extension_id);
bool CloseExtensionSidePanel(content::WebContents* contents, const std::string& extension_id);
// DevTools. Crest is a single-window browser, so a docked inspector belongs
// inside the page card it inspects rather than in a window of its own. This
// build never creates Chrome's Views contents container, so its
// `DevtoolsUIController` — which is what normally answers both of these — does
// not exist; these answer in its place for a WebContents a Crest page owns.
//
// `CanDockDevTools` decides whether the frontend may dock at all.
// `UpdateDockedDevTools` offers, relayouts or withdraws the docked frontend and
// returns true when a Crest page owns `inspected`. `OnDevToolsClosing` reports
// an inspector that is going away by any route — its own close button, an
// undocked window close, or the inspected page closing — so the core's
// developer-panel selection cannot go stale.
bool CanDockDevTools(content::WebContents* inspected);
bool UpdateDockedDevTools(content::WebContents* inspected);
void OnDevToolsClosing(content::WebContents* inspected);
// Applies semantic policy after Chromium validates a renderer's original request.
bool RouteModifiedLink(content::WebContents* source, content::OpenURLParams& params);
// Crest presents script dialogs for its pages with the same native presenter
// WebKit uses. Other Chromium pages keep their engine dialog manager.
content::JavaScriptDialogManager* JavaScriptDialogManagerFor(content::WebContents* contents);
// Screen sharing. Once Crest's core lets the page's site ask, a page's
// getDisplayMedia() offers the person its profile's tabs, then the system's
// own sharing picker for a window or a display, so Chromium's picker, which
// lists and captures every window to show thumbnails, is never made.
// `SharesScreenThroughSystem` says whether Crest takes `request`, and
// `CreateScreenSharingPicker` makes its picker.
bool SharesScreenThroughSystem(const content::MediaStreamRequest& request);
std::unique_ptr<DesktopMediaPicker> CreateScreenSharingPicker(const content::MediaStreamRequest& request);
// Whether capturing `source` for `contents` may go ahead as far as the
// system's Screen Recording access goes. The system's picker needs none; any
// other display or window capture does, and the engine asks the system for it
// at most once per launch.
bool AllowsScreenCapture(content::WebContents* contents, const content::DesktopMediaID& source);
// What shows that `capturer` shares the tab `media_id` names, and stops it:
// a bar in the shared tab and one in `capturer`, which the platform shows as
// it shows the engine's other bars. `application_title` names `capturer` as
// the person reads it.
std::unique_ptr<MediaStreamUI> CreateTabSharingIndicator(content::WebContents* capturer,
                                                         const content::DesktopMediaID& media_id,
                                                         const std::u16string& application_title);
#ifdef __OBJC__
// Crest's own UI, which the UI framework attaches when it starts; nil before.
id<CrestMacUI> MacUI();
// Consumes an external open: a link from another app, a document, or the
// default-browser role. Crest applies its own routing policy.
bool OpenExternalURLs(NSArray<NSURL*>* urls);
// The Dock icon's menu: Crest's window commands and the Spaces a window can
// show. Nil before Crest's UI starts and once it is shutting down, when the
// Dock shows only what macOS adds. Chromium's profiles and incognito window
// are not Crest's, so the Dock never offers them.
NSMenu* DockMenu();
// An app's system sign-in (`ASWebAuthenticationSession`). Crest runs it in a
// Quick Window of the Space the app's links route to, instead of Chromium's
// Views popup in a profile no Space owns. Both return false only when Crest is
// not hosting, which leaves Chromium's own handling in place.
bool BeginAuthenticationSession(ASWebAuthenticationSessionRequest* request);
bool CancelAuthenticationSession(ASWebAuthenticationSessionRequest* request);
NSWindow* WindowForBrowser(Browser* browser);
// Crest's own rows for the link or selection a context menu was opened on.
void AppendLinkMenuItem(NSMenu* menu, content::WebContents* contents, const GURL& url,
                        const std::u16string& selection);
#endif
}  // namespace crest

#endif
