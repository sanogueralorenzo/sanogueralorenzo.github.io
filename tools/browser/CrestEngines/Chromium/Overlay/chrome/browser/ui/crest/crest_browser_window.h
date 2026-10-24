// Adapted from Mori (MIT), commit b5b29c2e29061f9b2009e8cc0b2756c6ad62bb20.
// Copyright (c) 2026 Mori contributors. See CrestEngines/Chromium/ThirdParty/Mori-LICENSE.
// Crest: presents the Crest SwiftUI chrome behind Chrome's BrowserWindow
// interface so Chrome's Browser/TabStripModel — and the real extension
// system — drive Crest's UI instead of Chrome's views UI.

#ifndef CHROME_BROWSER_UI_CREST_CREST_BROWSER_WINDOW_H_
#define CHROME_BROWSER_UI_CREST_CREST_BROWSER_WINDOW_H_

#include <memory>

#include "base/memory/weak_ptr.h"
#include "base/observer_list.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include <string>
#include <vector>

#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/download_close_type.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "components/sharing_message/sharing_dialog_data.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"

class Browser;

namespace qrcode_generator {
class QRCodeGeneratorBubbleView;
}  // namespace qrcode_generator

namespace send_tab_to_self {
class SendTabToSelfBubbleView;
}  // namespace send_tab_to_self

namespace share {
struct ShareAttempt;
}  // namespace share

namespace sharing_hub {
class ScreenshotCapturedBubble;
class SharingHubBubbleView;
}  // namespace sharing_hub

// No-op FindBar: FindBarController derefs the FindBar unconditionally; the
// real find UI is Crest's SwiftUI FindBar driving FindTabHelper directly.
class CrestFindBar : public FindBar {
 public:
  CrestFindBar() = default;
  ~CrestFindBar() override = default;

  FindBarController* GetFindBarController() const override;
  void SetFindBarController(FindBarController* find_bar_controller) override;
  void Show(bool animate, bool focus) override;
  void Hide(bool animate) override;
  void SetFocusAndSelection() override;
  void ClearResults( const find_in_page::FindNotificationDetails& results) override;
  void StopAnimation() override;
  void MoveWindowIfNecessary() override;
  void SetFindTextAndSelectedRange( const std::u16string& find_text, const gfx::Range& selected_range) override;
  std::u16string_view GetFindText() const override;
  gfx::Range GetSelectedRange() const override;
  void UpdateUIForFindResult( const find_in_page::FindNotificationDetails& result, const std::u16string& find_text) override;
  void AudibleAlert() override;
  bool IsFindBarVisible() const override;
  void RestoreSavedFocus() override;
  bool HasGlobalFindPasteboard() const override;
  void UpdateFindBarForChangedWebContents() override;
  bool CanPopulateFromSelectedText() override;
  const FindBarTesting* GetFindBarTesting() const override;
  bool HasFocus() const override;
  void CloseOverlappingBubbles() override;
  views::Widget* GetHostWidget() override;
 private:
  FindBarController* controller_ = nullptr;
};

// No-op LocationBar: Browser dereferences GetLocationBar() unconditionally on
// tab switches (SaveStateToContents etc.); Crest's omnibox lives in SwiftUI.
class CrestLocationBar : public LocationBar {
 public:
  explicit CrestLocationBar(Browser* browser)
      : LocationBar(nullptr), browser_(browser) {}
  ~CrestLocationBar() override = default;

  void FocusLocation(bool is_user_initiated, bool clear_focus_if_failed) override;
  void FocusSearch() override;
  void AnnounceAlert(const std::u16string& announcement) override;
  void UpdateFocusBehavior(bool toolbar_visible) override;
  void UpdateContentSettingsIcons() override;
  void SaveStateToContents(content::WebContents* contents) override;
  void Revert() override;
  OmniboxView* GetOmniboxView() override;
  OmniboxPopupView* GetOmniboxPopupView() override;
  OmniboxController* GetOmniboxController() override;
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override;
  content::WebContents* GetWebContents() override;
  LocationBarModel* GetLocationBarModel() override;
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor() override;
  ChipController* GetChipController() override;
  void OnChanged() override;
  void UpdateWithoutTabRestore() override;
  ui::TrackedElement* GetAnchorOrNull() override;
  Browser* GetBrowser() override;
  Profile* GetProfile() override;
  bool IsInitialized() const override;
  bool IsVisible() const override;
  bool IsDrawn() const override;
  bool IsFullscreen() const override;
  bool IsEditingOrEmpty() const override;
  bool IsMouseHovered() const override;
  bool IsFocusWithin() const override;
  void InvalidateLayout() override;
  gfx::Rect Bounds() const override;
  gfx::Rect BoundsInScreen() const override;
  gfx::Size MinimumSize() const override;
  gfx::Size PreferredSize() const override;
  void Update(content::WebContents* contents) override;
  void ResetTabState(content::WebContents* contents) override;
  bool HasSecurityStateChanged() override;
  LocationBarTesting* GetLocationBarForTesting() override;

 private:
  Browser* browser_;  // Weak; the Browser owns the window.
};

// Fullscreen / exclusive-access context for the Crest window. Every mouse and
// key event over web contents routes through ExclusiveAccessManager, which
// dereferences this — it must exist.
//
// A page's fullscreen shows the page alone in the window's native fullscreen.
// Chromium hears each of the window's fullscreen transitions, whoever asked
// for them, as it does from its own windows, so a window that leaves
// fullscreen from its own button or the Window menu ends the page's
// fullscreen too.
class CrestExclusiveAccessContext : public ExclusiveAccessContext {
 public:
  explicit CrestExclusiveAccessContext(Browser* browser);
  ~CrestExclusiveAccessContext() override;

  Profile* GetProfile() override;
  bool IsFullscreen() const override;
  void EnterFullscreen(const url::Origin& origin,
                       ExclusiveAccessBubbleType bubble_type,
                       FullscreenTabParams fullscreen_tab_params) override;
  void ExitFullscreen() override;
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback first_hide_callback) override;
  bool IsExclusiveAccessBubbleDisplayed() const override;
  void OnExclusiveAccessUserInput() override;
  content::WebContents* GetWebContentsForExclusiveAccess() override;
  bool CanUserEnterFullscreen() const override;
  bool CanUserExitFullscreen() const override;
  void UpdateUIForTabFullscreen() override;

 private:
  // The Browser's window finished entering (`entered`) or leaving fullscreen.
  void WindowFullscreenChanged(bool entered);
  // The page shown fullscreen goes back to its place among Crest's chrome.
  void EndContentFullscreen();
  void ShowFullscreenDisclosure(
      const url::Origin& origin,
      ExclusiveAccessBubbleHideCallback first_hide_callback = {});
  void HideFullscreenDisclosure(ExclusiveAccessBubbleHideReason reason);

  Browser* browser_;
  // The page shown fullscreen, from its request until its fullscreen ends.
  base::WeakPtr<content::WebContents> content_fullscreen_;
  // When a page last stopped showing alone in a window that stays fullscreen.
  base::TimeTicks page_left_fullscreen_window_;
  // The observers of the window's fullscreen transitions.
  void* window_fullscreen_observers_ = nullptr;
  void* fullscreen_disclosure_ = nullptr;
  ExclusiveAccessBubbleHideCallback fullscreen_disclosure_hide_callback_;
  // Hides the disclosure after the time Chromium's own bubble shows for.
  base::OneShotTimer fullscreen_disclosure_timer_;
  bool exclusive_access_bubble_visible_ = false;
};

// Hosts Chrome's constrained (tab-modal) dialogs — JS alerts, HTTP auth,
// payment/print sheets — over the shared Crest window. This single host is
// what makes Chrome's real dialog widgets work without a BrowserView.
class CrestModalDialogHost : public web_modal::WebContentsModalDialogHost {
 public:
  explicit CrestModalDialogHost(Browser* browser) : browser_(browser) {}
  ~CrestModalDialogHost() override;

  gfx::NativeView GetHostView() const override;
  gfx::Point GetDialogPosition(const gfx::Size& size) override;
  gfx::Size GetMaximumDialogSize() override;
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override;
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override;

 private:
  Browser* browser_;
  base::ObserverList<web_modal::ModalDialogHostObserver> observers_;
};

class CrestBrowserWindow : public BrowserWindow {
 public:
  explicit CrestBrowserWindow(Browser* browser);
  ~CrestBrowserWindow() override;

  Browser* browser() { return browser_; }

  // BrowserWindow / ui::BaseWindow:
  bool IsActive() const override;
  bool IsMaximized() const override;
  bool IsMinimized() const override;
  bool IsFullscreen() const override;
  gfx::NativeWindow GetNativeWindow() const override;
  gfx::Rect GetRestoredBounds() const override;
  ui::mojom::WindowShowState GetRestoredState() const override;
  gfx::Rect GetBounds() const override;
  void Show() override;
  void Hide() override;
  bool IsVisible() const override;
  void ShowInactive() override;
  void Close() override;
  void Activate() override;
  void Deactivate() override;
  void Maximize() override;
  void Minimize() override;
  void Restore() override;
  void SetBounds(const gfx::Rect& bounds) override;
  void FlashFrame(bool flash) override;
  ui::ZOrderLevel GetZOrderLevel() const override;
  void SetZOrderLevel(ui::ZOrderLevel order) override;
  bool IsOnCurrentWorkspace() const override;
  bool IsVisibleOnScreen() const override;
  void SetTopControlsShownRatio(content::WebContents* web_contents, float ratio) override;
  bool DoBrowserControlsShrinkRendererSize( const content::WebContents* contents) const override;
  ui::NativeTheme* GetNativeTheme() override;
  const ui::ThemeProvider* GetThemeProvider() const override;
  const ui::ColorProvider* GetColorProvider() const override;
  int GetTopControlsHeight() const override;
  void SetTopControlsGestureScrollInProgress(bool in_progress) override;
  std::vector<StatusBubble*> GetStatusBubbles() override;
  void UpdateTitleBar() override;
  void UpdateLoadingAnimations(bool is_visible) override;
  void OnActiveTabChanged(content::WebContents* old_contents, content::WebContents* new_contents, int index, int reason) override;
  void OnTabDetached(content::WebContents* contents, bool was_active) override;
  gfx::Size GetContentsSize() const override;
  void SetContentsSize(const gfx::Size& size) override;
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override;
  LocationBar* GetLocationBar() const override;
  ui::AcceleratorProvider* GetAcceleratorProvider() override;
  void SetFocusToLocationBar(bool is_user_initiated) override;
  void UpdateReloadStopState(bool is_loading, bool force) override;
  void UpdateToolbar(content::WebContents* contents) override;
  bool UpdateToolbarSecurityState() override;
  void UpdateCustomTabBarVisibility(bool visible, bool animate) override;
  void ResetToolbarTabState(content::WebContents* contents) override;
  void FocusToolbar() override;
  void ToolbarSizeChanged(bool is_animating) override;
  void TabDraggingStatusChanged(bool is_dragging) override;
  void LinkOpeningFromGesture(WindowOpenDisposition disposition) override;
  void FocusAppMenu() override;
  bool IsTabStripEditable() const override;
  void DisableTabStripEditingForTesting() override;
  bool IsToolbarVisible() const override;
  bool IsToolbarShowing() const override;
  bool IsLocationBarVisible() const override;
  void ShowUpdateChromeDialog() override;
  void ShowIntentPickerBubble( std::vector<apps::IntentPickerAppInfo> app_info, bool show_stay_in_chrome, bool show_remember_selection, apps::IntentPickerBubbleType bubble_type, const std::optional<url::Origin>& initiating_origin, IntentPickerResponse callback) override;
  void ShowBookmarkBubble(const GURL& url, bool already_bookmarked) override;
  ShowTranslateBubbleResult ShowTranslateBubble( content::WebContents* contents, translate::TranslateStep step, const std::string& source_language, const std::string& target_language, translate::TranslateErrors error_type, bool is_user_gesture) override;
  DownloadBubbleUIController* GetDownloadBubbleUIController() override;
  void ConfirmBrowserCloseWithPendingDownloads( int download_count, DownloadCloseType dialog_type, base::OnceCallback<void(bool)> callback) override;
  void ShowAppMenu() override;
  void PreHandleDragUpdate(const content::DropData& drop_data, const gfx::PointF& point) override;
  void PreHandleDragExit() override;
  void HandleDragEnded() override;
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent( const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent( const input::NativeWebKeyboardEvent& event) override;
  std::unique_ptr<FindBar> CreateFindBar() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHostFor(content::WebContents* web_contents) override;
  void ShowAvatarBubbleFromAvatarButton(bool is_source_accelerator) override;
  void MaybeShowProfileSwitchIPH() override;
  void MaybeShowSupervisedUserProfileSignInIPH() override;
  void ShowHatsDialog( const std::string& site_id, const std::optional<std::string>& hats_histogram_name, const std::optional<uint64_t> hats_survey_ukm_id, base::OnceClosure success_callback, base::OnceClosure failure_callback, const SurveyBitsData& product_specific_bits_data, const SurveyStringData& product_specific_string_data) override;
  ExclusiveAccessContext* GetExclusiveAccessContext() override;
  std::string GetWorkspace() const override;
  bool IsVisibleOnAllWorkspaces() const override;
  void ShowEmojiPanel() override;
  std::unique_ptr<content::EyeDropper> OpenEyeDropper( content::RenderFrameHost* frame, content::EyeDropperListener* listener) override;
  void ShowCaretBrowsingDialog() override;
  void CreateTabSearchBubble() override;
  void CloseTabSearchBubble() override;
  void ShowIncognitoClearBrowsingDataDialog() override;
  void ShowIncognitoHistoryDisclaimerDialog() override;
  bool IsUnframedModeEnabled() const override;
  bool GetCanResize() override;
  ui::mojom::WindowShowState GetWindowShowState() const override;
  void ShowChromeLabs() override;
  BrowserView* AsBrowserView() override;
  void DeleteBrowserWindow() override;

 private:
  Browser* browser_;  // Weak; the Browser owns this window.
  CrestModalDialogHost modal_dialog_host_;
  CrestExclusiveAccessContext exclusive_access_context_;
  CrestLocationBar location_bar_;
};

#endif  // CHROME_BROWSER_UI_CREST_CREST_BROWSER_WINDOW_H_
