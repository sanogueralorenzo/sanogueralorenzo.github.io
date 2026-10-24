#import <AuthenticationServices/AuthenticationServices.h>
#import <Cocoa/Cocoa.h>
#import "CrestChromiumHost.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <cmath>
#include <memory>
#include <string>
#include <set>
#include <vector>
#include "base/auto_reset.h"
#include "base/check.h"
#include "base/apple/bridging.h"
#include "base/apple/foundation_util.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/pickle.h"
#include "base/json/json_reader.h"
#include "base/timer/timer.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/task/sequenced_task_runner.h"
#include "base/files/file_util.h"
#include "components/prefs/pref_service.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_remover_constants.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/nuke_profile_directory_utils.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_attributes_storage_observer.h"
#include "content/public/browser/browsing_data_remover.h"
#include "content/public/browser/browsing_data_filter_builder.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "content/public/browser/restore_type.h"
#include "chrome/browser/ui/crest/crest_permission_prompt.h"
#import "chrome/browser/app_controller_mac.h"
#include "chrome/browser/ui/crest/crest_engine_extensions.h"
#include "chrome/browser/ui/crest/crest_engine_profiles.h"
#include "chrome/browser/ui/crest/crest_extension_prompt.h"
#include "extensions/browser/crx_installer.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/extension_icon_image.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/common/manifest_handlers/icons_handler.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "extensions/common/permissions/permissions_data.h"
#include "extensions/common/permissions/permission_message.h"

#include "extensions/browser/install/crx_install_error.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/escape.h"
#include "base/task/thread_pool.h"
#include "components/crx_file/id_util.h"
#include "components/update_client/update_query_params.h"
#include "components/version_info/version_info.h"
#include "content/public/browser/storage_partition.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_util.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/extensions/api/side_panel/side_panel_service.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "extensions/browser/event_router.h"
#include "extensions/browser/permissions/active_tab_permission_granter.h"
#include "extensions/common/command.h"
#include "extensions/common/api/extension_action/action_info.h"
#include "extensions/common/mojom/context_type.mojom.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/accelerators/command.h"
#include "ui/events/cocoa/cocoa_event_utils.h"
#include "ui/events/keycodes/keyboard_code_conversion_mac.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_host_observer.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_util.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/render_widget_host_view.h"
#include "ui/gfx/image/image.h"
#include "extensions/browser/pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "base/time/time.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_types.h"
#include "components/zoom/zoom_controller.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "base/functional/bind.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/download/download_item_model.h"
#include "chrome/browser/ui/crest/crest_download_hooks.h"
#include "chrome/browser/download/download_confirmation_result.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/download_manager.h"
#include "ui/shell_dialogs/selected_file_info.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_destroyer.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "base/command_line.h"
#include "base/no_destructor.h"
#include "base/uuid.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_browsers.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "chrome/browser/ui/crest/crest_engine_prompts.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/toasts/api/toast_id.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/javascript_dialog_manager.h"
#include "net/base/auth.h"
#include "ui/views/widget/widget.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/drop_data.h"
#include "net/base/apple/url_conversions.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "components/security_state/core/security_state.h"
#include "content/public/browser/ssl_status.h"
#include "net/base/net_errors.h"
#include "net/cert/cert_status_flags.h"
#include "net/cert/x509_certificate.h"
#include "net/cert/x509_util.h"
#include "content/public/browser/global_routing_id.h"
#include "ui/base/page_transition_types.h"

// What an extension shortcut did, for the platform.
@interface CrestExtensionShortcutResult : NSObject <CrestExtensionShortcut>
@property(nonatomic, nullable) NSString* actionExtensionID;
@end
@implementation CrestExtensionShortcutResult
@end

// The window an extension action's popup is shown in.
//
// Crest does not use `NSPopover` for these. On macOS 27 the popover composites
// a translucent system material with whatever it hosts, so an extension
// painting an opaque `#181A1B` measured `#68555B` on screen — a white haze over
// the extension's own rendering. Neither an opaque page base nor an opaque
// browser surface changes that, and an opaque view behind the web contents
// occludes the renderer's remote layer and leaves the popup blank. This is a
// plain borderless window instead: nothing of Crest's is composited with the
// extension's document, so what the renderer paints is what reaches the screen.
//
// It becomes key so the popup's own fields can be typed into, and is added as a
// child of the Crest window it was anchored in, so it travels and orders with
// it. There is no arrow: the arrow of a system popover is filled with the
// popover's own background colour, and Crest does not know the colour an
// extension's document paints.
@interface CrestExtensionPopupWindow : NSWindow
@end
@implementation CrestExtensionPopupWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

namespace {
// AppKit hosting follows Mori's native ExtensionView bridge (MIT; see
// ThirdParty/Mori-LICENSE). Each instance belongs to one Crest page/profile.
class ExtensionPopup final : public extensions::ExtensionView,
                             public extensions::ExtensionHostObserver {
 public:
  ExtensionPopup(std::unique_ptr<extensions::ExtensionViewHost> host, NSView* anchor_view, NSRect anchor_rect)
      : host_(std::move(host)), anchor_view_(anchor_view), anchor_rect_(anchor_rect) {
    host_->set_view(this);
    host_->AddObserver(this);
    auto weak = weak_factory_.GetWeakPtr();
    host_->SetCloseHandler(base::BindOnce([](base::WeakPtr<ExtensionPopup> popup, extensions::ExtensionHost*) {
      dispatch_async(dispatch_get_main_queue(), ^{ if (popup) popup->Close(); });
    }, weak));
    window_ = [[CrestExtensionPopupWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, kDefaultWidth, kDefaultHeight)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window_.releasedWhenClosed = NO;
    window_.opaque = NO;
    window_.backgroundColor = NSColor.clearColor;
    window_.hasShadow = YES;
    window_.movable = NO;
    window_.animationBehavior = NSWindowAnimationBehaviorNone;
    window_.collectionBehavior =
        NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle;
    // A plain layer-backed container, not a vibrancy view: it contributes only
    // the rounded corners Crest's own controls use. The renderer's view is its
    // one subview, with nothing opaque between them, so the remote layer the
    // renderer draws into is never occluded.
    NSView* container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kDefaultWidth, kDefaultHeight)];
    container.wantsLayer = YES;
    container.layer.backgroundColor = NSColor.clearColor.CGColor;
    container.layer.cornerRadius = kCornerRadius;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    container.layer.masksToBounds = YES;
    container.autoresizesSubviews = YES;
    NSView* view = host_->host_contents()->GetNativeView().GetNativeNSView();
    view.frame = container.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:view];
    window_.contentView = container;
    host_->CreateRendererSoon();
  }
  ~ExtensionPopup() override { Close(); }
  void Close() {
    weak_factory_.InvalidateWeakPtrs();
    for (id monitor in monitors_) [NSEvent removeMonitor:monitor];
    monitors_ = nil;
    for (id observation in observations_) [[NSNotificationCenter defaultCenter] removeObserver:observation];
    observations_ = nil;
    if (window_) {
      if (NSWindow* parent = window_.parentWindow) [parent removeChildWindow:window_];
      [window_ orderOut:nil];
      window_.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
      [window_ close];
      window_ = nil;
    }
    if (host_) { host_->RemoveObserver(this); host_.reset(); }
  }
  gfx::NativeView GetNativeView() override { return host_ ? host_->host_contents()->GetNativeView() : gfx::NativeView(); }
  void ResizeDueToAutoResize(content::WebContents*, const gfx::Size& size) override {
    if (!window_) return;
    content_size_ = NSMakeSize(std::clamp(size.width(), 25, 800), std::clamp(size.height(), 25, 600));
    Position();
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (auto* view = frame->GetView()) view->EnableAutoResize(gfx::Size(25, 25), gfx::Size(800, 600));
  }
  bool HandleKeyboardEvent(content::WebContents*, const input::NativeWebKeyboardEvent&) override { return false; }
  void OnLoaded() override {
    NSWindow* parent = anchor_view_.window;
    if (!parent || !window_ || presented_) { if (!parent) Close(); return; }
    presented_ = true;
    Position();
    [parent addChildWindow:window_ ordered:NSWindowAbove];
    [window_ makeKeyAndOrderFront:nil];
    Observe(parent);
    if (host_) host_->host_contents()->Focus();
  }
  void OnExtensionHostDestroyed(extensions::ExtensionHost* host) override {
    if (host_.get() == host) host_.release();
    Close();
  }
 private:
  static constexpr CGFloat kDefaultWidth = 360;
  static constexpr CGFloat kDefaultHeight = 320;
  // The radius Crest's own controls use.
  static constexpr CGFloat kCornerRadius = 12;
  static constexpr CGFloat kAnchorGap = 6;
  static constexpr CGFloat kScreenMargin = 8;
  static constexpr unsigned short kEscapeKeyCode = 53;

  // Places the popup under the control it was opened from, flipping above it
  // and sliding along the screen when there is not room below or beside it.
  void Position() {
    NSWindow* parent = anchor_view_.window;
    if (!window_ || !parent) return;
    const NSRect anchor = [parent convertRectToScreen:[anchor_view_ convertRect:anchor_rect_ toView:nil]];
    NSRect visible = (parent.screen ?: NSScreen.mainScreen).visibleFrame;
    NSRect frame = NSMakeRect(NSMidX(anchor) - content_size_.width / 2,
                              NSMinY(anchor) - kAnchorGap - content_size_.height,
                              content_size_.width, content_size_.height);
    if (NSMinY(frame) < NSMinY(visible) + kScreenMargin) {
      const CGFloat above = NSMaxY(anchor) + kAnchorGap;
      if (above + content_size_.height <= NSMaxY(visible) - kScreenMargin) frame.origin.y = above;
      else frame.origin.y = NSMinY(visible) + kScreenMargin;
    }
    frame.origin.x = std::clamp(frame.origin.x, NSMinX(visible) + kScreenMargin,
                                std::max(NSMinX(visible) + kScreenMargin,
                                         NSMaxX(visible) - kScreenMargin - content_size_.width));
    [window_ setFrame:frame display:YES];
  }

  // Transient like the popover it replaces: a click outside it, Escape, the
  // window it belongs to moving, resizing or minimising, and Crest going to the
  // background all dismiss it. The extension closing its own popup, the host
  // being destroyed and the extension unloading come through the host.
  void Observe(NSWindow* parent) {
    auto weak = weak_factory_.GetWeakPtr();
    NSWindow* popup = window_;
    const NSEventMask clicks = NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
    monitors_ = @[
      [NSEvent addLocalMonitorForEventsMatchingMask:clicks | NSEventMaskKeyDown
                                            handler:^NSEvent*(NSEvent* event) {
        if (!weak) return event;
        if (event.type == NSEventTypeKeyDown) {
          if (event.keyCode != kEscapeKeyCode) return event;
          weak->Close();
          return nil;
        }
        if (event.window != popup) weak->Close();
        return event;
      }],
      [NSEvent addGlobalMonitorForEventsMatchingMask:clicks handler:^(NSEvent*) {
        if (weak) weak->Close();
      }],
    ];
    NSMutableArray* observations = [NSMutableArray array];
    auto dismiss = ^(NSNotification*) {
      dispatch_async(dispatch_get_main_queue(), ^{ if (weak) weak->Close(); });
    };
    for (NSNotificationName name in @[NSWindowDidResizeNotification, NSWindowDidMoveNotification,
                                      NSWindowDidMiniaturizeNotification, NSWindowWillCloseNotification])
      [observations addObject:[[NSNotificationCenter defaultCenter] addObserverForName:name object:parent
          queue:NSOperationQueue.mainQueue usingBlock:dismiss]];
    [observations addObject:[[NSNotificationCenter defaultCenter]
        addObserverForName:NSApplicationDidResignActiveNotification object:NSApp
                     queue:NSOperationQueue.mainQueue usingBlock:dismiss]];
    observations_ = observations;
  }

  std::unique_ptr<extensions::ExtensionViewHost> host_;
  NSView* __weak anchor_view_;
  NSRect anchor_rect_;
  CrestExtensionPopupWindow* __strong window_ = nil;
  NSArray* __strong monitors_ = nil;
  NSArray* __strong observations_ = nil;
  NSSize content_size_ = NSMakeSize(kDefaultWidth, kDefaultHeight);
  bool presented_ = false;
  base::WeakPtrFactory<ExtensionPopup> weak_factory_{this};
};

// An extension side panel is a Crest split-row card, not a Views
// SidePanelEntry: Crest never instantiates Chrome's SidePanelCoordinator. Only
// the extension host and its view belong to Chromium; placement, sizing and
// dismissal are the core's, and the card owns this object's lifetime.
class ExtensionSidePanel final : public extensions::ExtensionView,
                                 public extensions::ExtensionHostObserver {
 public:
  ExtensionSidePanel(std::unique_ptr<extensions::ExtensionViewHost> host,
                     std::string extension_id, void (^closed)(void))
      : host_(std::move(host)), extension_id_(std::move(extension_id)), closed_([closed copy]) {
    container_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 600)];
    container_.autoresizesSubviews = YES;
    host_->set_view(this);
    host_->AddObserver(this);
    auto weak = weak_factory_.GetWeakPtr();
    // The panel's own document called window.close(), or the extension
    // retracted its entry. Either way the card goes away with it.
    host_->SetCloseHandler(base::BindOnce([](base::WeakPtr<ExtensionSidePanel> panel, extensions::ExtensionHost*) {
      dispatch_async(dispatch_get_main_queue(), ^{ if (panel) panel->Dismiss(); });
    }, weak));
    NSView* view = host_->host_contents()->GetNativeView().GetNativeNSView();
    view.frame = container_.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container_ addSubview:view];
    host_->CreateRendererSoon();
  }
  ~ExtensionSidePanel() override { Close(); }
  NSView* container() { return container_; }
  const std::string& extension_id() const { return extension_id_; }
  // The extension retracted its entry or unloaded. Tell the core to drop the
  // card; the panel document goes away with this object.
  void Retract() { Dismiss(); }
  void Close() {
    weak_factory_.InvalidateWeakPtrs();
    closed_ = nil;
    if (host_) { host_->RemoveObserver(this); host_.reset(); }
  }
  gfx::NativeView GetNativeView() override {
    return host_ ? host_->host_contents()->GetNativeView() : gfx::NativeView();
  }
  // The card is laid out by the row, so the panel document never resizes it.
  void ResizeDueToAutoResize(content::WebContents*, const gfx::Size&) override {}
  void RenderFrameCreated(content::RenderFrameHost*) override {}
  bool HandleKeyboardEvent(content::WebContents*, const input::NativeWebKeyboardEvent&) override { return false; }
  void OnLoaded() override {}
  void OnExtensionHostDestroyed(extensions::ExtensionHost* host) override {
    if (host_.get() == host) host_.release();
    Dismiss();
  }
 private:
  // Hands the dismissal to the core, which removes the card and then releases
  // this object. Nothing may touch `this` afterwards.
  void Dismiss() {
    void (^closed)(void) = closed_;
    Close();
    if (closed) closed();
  }
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  std::string extension_id_;
  void (^__strong closed_)(void);
  NSView* __strong container_ = nil;
  base::WeakPtrFactory<ExtensionSidePanel> weak_factory_{this};
};
// The docked DevTools frontend inside a Crest page card.
//
// Chromium owns the frontend WebContents and everything in it, including the
// undock and close buttons. This owns only the container the core mounts, so a
// dock-side or size change is a relayout of a card that is already on screen
// rather than a new one, and the resizing strategy the frontend publishes is
// kept here beside it.
class DevToolsPanel {
 public:
  explicit DevToolsPanel(content::WebContents* frontend)
      : frontend_(frontend->GetWeakPtr()) {
    container_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    container_.autoresizesSubviews = YES;
    NSView* view = frontend->GetNativeView().GetNativeNSView();
    view.frame = container_.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container_ addSubview:view];
  }
  NSView* container() { return container_; }
  bool hosts(content::WebContents* frontend) const {
    return frontend_ && frontend_.get() == frontend;
  }

 private:
  base::WeakPtr<content::WebContents> frontend_;
  NSView* __strong container_ = nil;
};
class NativePermissionPrompt final : public permissions::PermissionPrompt {
 public:
  NativePermissionPrompt(NSWindow* window, Delegate* delegate)
      : delegate_(delegate->GetWeakPtr()), window_(window) {
    alert_ = [[NSAlert alloc] init];
    alert_.messageText = base::SysUTF8ToNSString(delegate->GetRequestingOrigin().spec());
    NSMutableArray* requests = [NSMutableArray array];
    for (const auto& request : delegate->Requests())
      [requests addObject:base::SysUTF16ToNSString(request->GetMessageTextFragment())];
    alert_.informativeText = [requests componentsJoinedByString:@"\n"];
    [alert_ addButtonWithTitle:@"Allow"];
    [alert_ addButtonWithTitle:@"Block"];
    [alert_ addButtonWithTitle:@"Not Now"];
    auto weak = weak_factory_.GetWeakPtr();
    [alert_ beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
      if (!weak || !weak->delegate_) return;
      weak->responded_ = true;
      auto current_delegate = weak->delegate_;
      if (response == NSAlertFirstButtonReturn) crest::AnswerPermissionRequests(*current_delegate, true, true);
      else if (response == NSAlertSecondButtonReturn) crest::AnswerPermissionRequests(*current_delegate, false, true);
      else crest::AnswerPermissionRequests(*current_delegate, false, false);
    }];
  }
  ~NativePermissionPrompt() override {
    weak_factory_.InvalidateWeakPtrs();
    if (!responded_ && alert_.window.sheetParent) [window_ endSheet:alert_.window returnCode:NSModalResponseCancel];
  }
  bool UpdateAnchor() override { return true; }
  TabSwitchingBehavior GetTabSwitchingBehavior() override { return kDestroyPromptButKeepRequestPending; }
  permissions::PermissionPromptDisposition GetPromptDisposition() const override { return permissions::PermissionPromptDisposition::ANCHORED_BUBBLE; }
  bool IsAskPrompt() const override { return true; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override { return std::nullopt; }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants() const override { return {}; }
  std::optional<permissions::feature_params::PermissionElementPromptPosition> GetPromptPosition() const override { return std::nullopt; }
 private:
  base::WeakPtr<Delegate> delegate_;
  NSWindow* __weak window_;
  NSAlert* __strong alert_;
  bool responded_ = false;
  base::WeakPtrFactory<NativePermissionPrompt> weak_factory_{this};
};
struct PageViews;
struct HostState {
  const base::Time started_at = base::Time::Now();
  // Crest's own UI, which the framework attaches when it starts.
  id<CrestMacUI> ui = nil;
  bool started = false;
  bool disposing = false;
  bool quitting = false;
  // The views the shell hosts beside each page, by page.
  std::map<std::string, std::unique_ptr<PageViews>> views;
  // The action popup opened from a Space that has no page. A page's own popup
  // lives on the page; this one has no page to live on and only one can be
  // open at a time, because an action popup is transient.
  std::unique_ptr<ExtensionPopup> space_extension_popup;
  // System sign-in requests from other apps, by the Quick Window running each.
  // Requests that arrive before the native root starts wait in `pending_*`.
  std::map<std::string, ASWebAuthenticationSessionRequest*> authentication_sessions;
  std::vector<ASWebAuthenticationSessionRequest*> pending_authentication_sessions;
  // The permission requests taking a Crest prompt's answer, while they do.
  raw_ptr<const permissions::PermissionPrompt::Delegate> answering_permission = nullptr;
};
HostState& State() { static base::NoDestructor<HostState> state; return *state; }

// Crest's own UI, or nil before the framework starts.
id<CrestMacUI> UI() { return State().ui; }

// The text the shell keeps a Crest identifier as.
std::string KeyFor(NSUUID* identifier) {
  return identifier ? base::SysNSStringToUTF8(identifier.UUIDString) : std::string();
}

// A Crest identifier the shell keeps as text, or nil for none.
NSUUID* UUIDFor(const std::string& identifier) {
  return identifier.empty() ? nil : [[NSUUID alloc] initWithUUIDString:base::SysUTF8ToNSString(identifier)];
}

// System sign-in (`ASWebAuthenticationSession`). Chromium's own handler opens a
// Views popup Browser in the last-used engine profile; that profile belongs to
// no Space and the popup never appears, so the sign-in page loads where nobody
// can see it. Crest runs the session in a Quick Window of the Space an external
// link from the requesting app routes to, and completes it when that page
// reaches the requester's callback. The window shows the page's address and
// has no editable location, which is what the system API requires.
//
// An ephemeral-session request still uses the Space's profile: the API leaves
// honoring it to the browser, and a Space is Crest's unit of identity.
void EndAuthenticationSession(const std::string& window, NSURL* callback, bool close_window) {
  auto& sessions = State().authentication_sessions;
  auto found = sessions.find(window);
  if (found == sessions.end()) return;
  ASWebAuthenticationSessionRequest* request = found->second;
  sessions.erase(found);
  if (callback) {
    [request completeWithCallbackURL:callback];
  } else {
    [request cancelWithError:[NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain
                                                 code:ASWebAuthenticationSessionErrorCodeCanceledLogin
                                             userInfo:nil]];
  }
  if (NSUUID* identifier = close_window ? UUIDFor(window) : nil) [UI() closeAuthenticationSession:identifier];
}

// The system's sign-in broker hands out one request at a time and waits for
// the browser to finish it; a request left open when Crest quits would hold
// every later sign-in until the broker restarts.
void CancelAllAuthenticationSessions() {
  auto& state = State();
  std::vector<ASWebAuthenticationSessionRequest*> requests =
      std::move(state.pending_authentication_sessions);
  state.pending_authentication_sessions.clear();
  for (const auto& [window, request] : state.authentication_sessions) requests.push_back(request);
  state.authentication_sessions.clear();
  for (ASWebAuthenticationSessionRequest* request : requests) {
    [request cancelWithError:[NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain
                                                 code:ASWebAuthenticationSessionErrorCodeCanceledLogin
                                             userInfo:nil]];
  }
}

void StartAuthenticationSession(ASWebAuthenticationSessionRequest* request) {
  if (State().disposing || State().quitting) {
    [request cancelWithError:[NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain
                                                 code:ASWebAuthenticationSessionErrorCodePresentationContextInvalid
                                             userInfo:nil]];
    return;
  }
  NSUUID* window = NSUUID.UUID;
  const std::string key = base::SysNSStringToUTF8(window.UUIDString);
  State().authentication_sessions[key] = request;
  if (![UI() openAuthenticationSession:request.URL window:window]) EndAuthenticationSession(key, nil, false);
}

// The views the shell hosts beside a page: an extension action's popup, an
// extension's side panel and a docked inspector. They go with the page's
// WebContents, or before it when the binding lets the page go.
struct PageViews final : content::WebContentsObserver {
  explicit PageViews(content::WebContents* contents) : content::WebContentsObserver(contents) {}
  std::unique_ptr<ExtensionPopup> extension_popup;
  std::unique_ptr<ExtensionSidePanel> side_panel;
  std::unique_ptr<DevToolsPanel> devtools;
  void WebContentsDestroyed() override {
    extension_popup.reset();
    side_panel.reset();
    devtools.reset();
    Observe(nullptr);
  }
};

// The WebContents of the page the platform names `pageID`, or null.
content::WebContents* PageContents(NSUUID* pageID) {
  crest::EnginePage* page = crest::EngineBinding::Get().Find(KeyFor(pageID));
  return page ? page->web_contents() : nullptr;
}

// The views beside `page`, which shows `contents`, made when it has none.
PageViews& ViewsFor(const std::string& page, content::WebContents* contents) {
  auto& views = State().views;
  // Reclaim entries only after their WebContents destruction callback returned.
  std::erase_if(views, [](const auto& entry) { return !entry.second->web_contents(); });
  auto& entry = views[page];
  if (!entry || entry->web_contents() != contents) entry = std::make_unique<PageViews>(contents);
  return *entry;
}

PageViews* FindViews(const std::string& page) {
  auto found = State().views.find(page);
  return found == State().views.end() ? nullptr : found->second.get();
}

// What only AppKit does for the portable binding: the Crest windows its
// Browsers show in, and the views beside each page. The binding keeps the
// Browsers themselves.
class MacShell final : public crest::EngineBinding::Shell {
 public:
  std::optional<crest::EngineBinding::WindowPlacement> ReserveWindow(const std::string& profile,
                                                                      bool own_window) override {
    NSUUID* identifier = UUIDFor(profile);
    id<CrestEngineWindowPlacement> placement =
        identifier ? [UI() reserveEngineWindowForProfile:identifier ownWindow:own_window ? YES : NO] : nil;
    if (!placement) return std::nullopt;
    return crest::EngineBinding::WindowPlacement{.window = KeyFor(placement.window), .space = KeyFor(placement.space)};
  }

  void PresentWindow(const crest::EngineBinding::WindowPlacement& placement, bool focused) override {
    NSUUID* window = UUIDFor(placement.window);
    NSUUID* space = UUIDFor(placement.space);
    if (window && space) [UI() presentEngineWindow:window space:space focused:focused ? YES : NO];
  }

  void ReleasePage(const std::string& page) override { State().views.erase(page); }

  // A Space-scoped popup may be anchored in the profile being let go of.
  void ReleaseProfile(const std::string&) override { State().space_extension_popup.reset(); }

  // Drops any open panel card for `extension_id` in `profile`, for one tab or
  // for all of them. An extension that unloads or turns its entry off has no
  // panel left to show.
  void RetractSidePanels(Profile* profile, const std::string& extension_id, std::optional<int> tab_id) override {
    if (!profile) return;
    std::vector<std::string> retracting;
    for (const auto& [page, views] : State().views) {
      if (!views->side_panel || views->side_panel->extension_id() != extension_id) continue;
      auto* contents = views->web_contents();
      if (!contents) continue;
      // An off-the-record page's extensions are its original profile's.
      if (Profile::FromBrowserContext(contents->GetBrowserContext())->GetOriginalProfile() !=
          profile->GetOriginalProfile()) continue;
      if (tab_id && sessions::SessionTabHelper::IdForTab(contents).id() != *tab_id) continue;
      retracting.push_back(page);
    }
    // A retracted card hands its dismissal to the platform, which may change
    // what the shell hosts, so each is found again.
    for (const std::string& page : retracting) {
      PageViews* views = FindViews(page);
      if (!views || !views->side_panel) continue;
      views->side_panel->Retract();
      views->side_panel.reset();
    }
  }

  void DockInspector(const std::string& page, content::WebContents* frontend) override {
    if (!frontend) {
      if (PageViews* views = FindViews(page)) views->devtools.reset();
      return;
    }
    crest::EnginePage* engine_page = crest::EngineBinding::Get().Find(page);
    content::WebContents* contents = engine_page ? engine_page->web_contents() : nullptr;
    if (!contents) return;
    PageViews& views = ViewsFor(page, contents);
    if (!views.devtools || !views.devtools->hosts(frontend)) views.devtools = std::make_unique<DevToolsPanel>(frontend);
  }
};
// chrome.commands. Crest owns the key-equivalent path, so an event the core
// did not claim is matched against the extension keybindings itself rather
// than through Chrome's Views keybinding registry, which this build never
// creates. Modelled on `ExtensionKeybindingRegistry`: the same command
// service, the same active-tab grant, and the same `commands.onCommand`
// payload, without the accelerator table a Views window would maintain.
ui::Accelerator ShortcutAccelerator(NSEvent* event) {
  const ui::KeyboardCode key = ui::KeyboardCodeFromNSEvent(event);
  if (key == ui::VKEY_UNKNOWN) return ui::Accelerator();
  return ui::Accelerator(key, ui::EventFlagsFromModifiers(event.modifierFlags));
}
// Delivers a named command to its extension, granting the active-tab
// permission first so the extension can act on the page it was invoked over.
void DeliverExtensionCommand(Profile* profile, const extensions::Extension& extension,
                             const std::string& command, content::WebContents* contents) {
  base::ListValue args;
  args.Append(command);
  base::Value tab;
  if (contents) {
    if (auto* granter = extensions::ActiveTabPermissionGranter::FromWebContents(contents))
      granter->GrantIfRequested(&extension);
    // The action APIs are privileged extension contexts by construction.
    const auto scrub = extensions::ExtensionTabUtil::GetScrubTabBehavior(
        &extension, extensions::mojom::ContextType::kPrivilegedExtension, contents);
    tab = base::Value(extensions::ExtensionTabUtil::CreateTabObject(contents, scrub, &extension).ToValue());
  }
  args.Append(std::move(tab));
  auto event = std::make_unique<extensions::Event>(
      extensions::events::COMMANDS_ON_COMMAND, "commands.onCommand", std::move(args), profile);
  event->user_gesture = extensions::EventRouter::UserGestureState::kEnabled;
  extensions::EventRouter::Get(profile)->DispatchEventToExtension(extension.id(), std::move(event));
}

// One Chrome Web Store package download, made by the Space's own profile with
// the request Chromium's Web Store installer sends. The ungoogled baseline
// empties that installer and rewrites Google's hosts in its sources, so the
// update service is named here. Chromium's CrxInstaller judges the package;
// nothing here limits or inspects it. Deletes itself once it has reported.
class WebStoreDownload {
 public:
  WebStoreDownload(void (^progress)(double), void (^completion)(NSString*, NSString*))
      : progress_(progress), completion_(completion) {}

  base::WeakPtr<WebStoreDownload> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }

  // Destroying the loader stops the request and deletes what it received.
  void Cancel() {
    weak_factory_.InvalidateWeakPtrs();
    loader_.reset();
    completion_(nil, base::SysUTF8ToNSString(net::ErrorToString(net::ERR_ABORTED)));
    delete this;
  }

  void Start(Profile* profile, const std::string& extension_id) {
    auto request = std::make_unique<network::ResourceRequest>();
    request->url = GURL("https://clients2.google.com/service/update2/crx?response=redirect&" +
        update_client::UpdateQueryParams::Get(update_client::UpdateQueryParams::CRX) + "&x=" +
        base::EscapeQueryParamValue("id=" + extension_id + "&installsource=ondemand&uc", true));
    request->credentials_mode = network::mojom::CredentialsMode::kOmit;
    // Someone is waiting on this download, as on Chromium's own foreground
    // extension fetches. At the default idle priority the loader writes the
    // package on best-effort tasks, which Chromium holds until it counts
    // startup as complete: up to three minutes when no page has loaded.
    request->priority = net::MEDIUM;
    loader_ = network::SimpleURLLoader::Create(std::move(request), kAnnotation);
    loader_->SetOnResponseStartedCallback(
        base::BindOnce(&WebStoreDownload::Started, base::Unretained(this)));
    loader_->SetOnDownloadProgressCallback(
        base::BindRepeating(&WebStoreDownload::Progressed, base::Unretained(this)));
    loader_->DownloadToTempFile(
        profile->GetDefaultStoragePartition()->GetURLLoaderFactoryForBrowserProcess().get(),
        base::BindOnce(&WebStoreDownload::Finished, base::Unretained(this)));
  }

 private:
  static constexpr net::NetworkTrafficAnnotationTag kAnnotation =
      net::DefineNetworkTrafficAnnotation("crest_web_store_download", R"(
        semantics {
          sender: "Crest Web Store install"
          description: "Downloads a Chrome Web Store extension package for installation."
          trigger: "The person installs an extension from a Chrome Web Store listing."
          data: "The extension's ID and Chromium's version, platform and language."
          destination: GOOGLE_OWNED_SERVICE
        }
        policy {
          cookies_allowed: NO
          setting: "Only runs when the person installs an extension."
        })");

  void Started(const GURL&, const network::mojom::URLResponseHead& head) { length_ = head.content_length; }

  void Progressed(uint64_t received) {
    if (length_ > 0) progress_(std::min(1.0, static_cast<double>(received) / static_cast<double>(length_)));
  }

  void Finished(base::FilePath path) {
    weak_factory_.InvalidateWeakPtrs();
    const network::mojom::URLResponseHead* head = loader_->ResponseInfo();
    const int status = head && head->headers ? head->headers->response_code() : 0;
    if (!path.empty() && status == 200) {
      completion_(base::apple::FilePathToNSString(path), @"");
    } else {
      // A successful status other than 200 carries no package: the service
      // answers 204 for an extension it will not serve to this browser.
      if (!path.empty()) {
        base::ThreadPool::PostTask(FROM_HERE, {base::MayBlock()}, base::GetDeleteFileCallback(path));
      }
      completion_(nil, status && status != 200 ? base::SysUTF8ToNSString("HTTP " + base::NumberToString(status))
                                               : base::SysUTF8ToNSString(net::ErrorToString(loader_->NetError())));
    }
    delete this;
  }

  std::unique_ptr<network::SimpleURLLoader> loader_;
  int64_t length_ = -1;
  void (^progress_)(double);
  void (^completion_)(NSString*, NSString*);
  base::WeakPtrFactory<WebStoreDownload> weak_factory_{this};
};
}  // namespace

// The platform's handle on a Web Store download, which outlives the download.
@interface CrestWebStoreDownloadHandle : NSObject <CrestExtensionDownload>
@end
@implementation CrestWebStoreDownloadHandle {
  base::WeakPtr<WebStoreDownload> _download;
}
- (instancetype)initWithDownload:(base::WeakPtr<WebStoreDownload>)download {
  if ((self = [super init])) _download = download;
  return self;
}
- (void)cancel {
  CHECK(NSThread.isMainThread);
  if (_download) _download->Cancel();
}
@end

@interface CrestChromiumMacShell : NSObject <CrestMacShell>
@end

// The UI framework's entry point: the shell's host, and the engine binding
// the framework registers with its core.
using CrestChromiumUIStart = void (*)(id<CrestMacShell> shell, const crest_engine_binding_t* binding,
                                      const uint8_t* fingerprint, size_t fingerprint_length,
                                      const crest_engine_pages_t* pages);

@implementation CrestChromiumMacShell
- (NSView*)viewForPage:(NSUUID*)pageID {
  CHECK(NSThread.isMainThread);
  content::WebContents* contents = PageContents(pageID);
  return contents ? contents->GetNativeView().GetNativeNSView() : nil;
}
- (BOOL)runExtension:(NSString*)extensionID page:(NSUUID*)pageID
         anchorView:(NSView*)anchorView anchorRect:(NSRect)anchorRect {
  CHECK(NSThread.isMainThread);
  auto& binding = crest::EngineBinding::Get();
  const std::string key = KeyFor(pageID);
  crest::EnginePage* page = binding.Find(key);
  content::WebContents* contents = page ? page->web_contents() : nullptr;
  Browser* browser = binding.Browsers().Holding(contents);
  if (!browser || !anchorView.window || anchorView.window != crest::WindowForBrowser(browser)) return NO;
  Profile* profile = browser->GetProfile();
  const auto id = base::SysNSStringToUTF8(extensionID);
  const auto* extension = extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(id);
  if (!extension || (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(id, profile))) return NO;
  // Declined rather than navigated: an extension whose files are gone would
  // otherwise show Chromium's own ERR_FILE_NOT_FOUND page inside Crest's
  // popup window. The core states this as an unavailable action instead.
  if (!binding.Extensions().For(profile, page->profile()).IsAvailable(*extension,
          extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(*extension))) return NO;
  if (!binding.Browsers().Activate(contents)) return NO;
  auto* runner = extensions::ExtensionActionRunner::GetForWebContents(contents);
  if (!runner) return NO;
  // This path is invoked only by the user's native extension action button.
  const auto result = runner->RunAction(extension, true);
  if (result == extensions::ExtensionAction::ShowAction::kNone) return YES;
  if (result == extensions::ExtensionAction::ShowAction::kToggleSidePanel) {
    // The action opens a panel instead of a popup. The card belongs to the
    // platform, so the click toggles the one this page is already showing.
    binding.RequestSidePanel(key, id, crest::engine::SidePanelRequest::kToggle);
    return YES;
  }
  if (result != extensions::ExtensionAction::ShowAction::kShowPopup) return NO;
  auto* action = extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(*extension);
  if (!action) return NO;
  auto popup = extensions::ExtensionViewHostFactory::CreatePopupHost(*extension,
      action->GetPopupUrl(sessions::SessionTabHelper::IdForTab(contents).id()), browser);
  if (!popup) return NO;
  ViewsFor(key, contents).extension_popup = std::make_unique<ExtensionPopup>(std::move(popup), anchorView, anchorRect);
  return YES;
}
- (BOOL)runExtension:(NSString*)extensionID profile:(NSUUID*)profileID window:(NSUUID*)windowID
          anchorView:(NSView*)anchorView anchorRect:(NSRect)anchorRect {
  CHECK(NSThread.isMainThread);
  // The page-less click. There is no tab to activate, no host permission to
  // grant and nothing to inject, so only an action that carries its own popup
  // document can run: it is opened against the Space's Browser directly rather
  // than through the WebContents-scoped action runner.
  if (!anchorView.window) return NO;
  const auto profile_id = KeyFor(profileID);
  Profile* profile = crest::EngineBinding::Get().Profiles().Find(profile_id);
  if (!profile) return NO;
  Profile* owner = profile->GetOriginalProfile();
  const auto id = base::SysNSStringToUTF8(extensionID);
  const auto* extension = extensions::ExtensionRegistry::Get(owner)->enabled_extensions().GetByID(id);
  if (!extension) return NO;
  if (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(id, owner)) return NO;
  auto* action = extensions::ExtensionActionManager::Get(owner)->GetExtensionAction(*extension);
  if (!action || !crest::EngineBinding::Get().Extensions().For(profile, profile_id).IsAvailable(*extension, action))
    return NO;
  if (action->action_type() == extensions::ActionInfo::Type::kPage) return NO;
  const GURL popup_url = action->GetPopupUrl(extensions::ExtensionAction::kDefaultTabId);
  if (!popup_url.is_valid()) return NO;
  Browser* browser = crest::EngineBinding::Get().Browsers().ForWindow(profile_id, KeyFor(windowID));
  if (!browser || anchorView.window != crest::WindowForBrowser(browser)) return NO;
  auto popup = extensions::ExtensionViewHostFactory::CreatePopupHost(*extension, popup_url, browser);
  if (!popup) return NO;
  State().space_extension_popup = std::make_unique<ExtensionPopup>(std::move(popup), anchorView, anchorRect);
  return YES;
}
- (NSView*)openSidePanel:(NSString*)extensionID page:(NSUUID*)pageID closed:(void (^)(void))closed {
  CHECK(NSThread.isMainThread);
  const std::string key = KeyFor(pageID);
  content::WebContents* contents = PageContents(pageID);
  Browser* browser = crest::EngineBinding::Get().Browsers().Holding(contents);
  const auto* extension = browser ? crest::EngineExtensions::SidePanelExtension(
      contents, base::SysNSStringToUTF8(extensionID)) : nullptr;
  if (!extension) return nil;
  auto* service = extensions::SidePanelService::Get(browser->GetProfile());
  auto options = service->GetOptions(*extension, sessions::SessionTabHelper::IdForTab(contents).id());
  if (!options.path || options.path->empty() || options.enabled == false) return nil;
  const GURL url = extension->ResolveExtensionURL(*options.path);
  if (!url.is_valid()) return nil;
  auto panel = extensions::ExtensionViewHostFactory::CreateSidePanelHost(*extension, url,
      browser, browser->tab_strip_model()->GetTabForWebContents(contents));
  if (!panel) return nil;
  PageViews& views = ViewsFor(key, contents);
  views.side_panel = std::make_unique<ExtensionSidePanel>(std::move(panel), extension->id(), closed);
  return views.side_panel->container();
}
- (void)closeSidePanelForPage:(NSUUID*)pageID {
  CHECK(NSThread.isMainThread);
  if (PageViews* views = FindViews(KeyFor(pageID))) views->side_panel.reset();
}
- (NSView*)devToolsViewForPage:(NSUUID*)pageID {
  CHECK(NSThread.isMainThread);
  PageViews* views = FindViews(KeyFor(pageID));
  return views && views->devtools ? views->devtools->container() : nil;
}
- (id<CrestExtensionShortcut>)dispatchExtensionShortcut:(NSEvent*)event page:(NSUUID*)pageID {
  CHECK(NSThread.isMainThread);
  content::WebContents* contents = PageContents(pageID);
  Browser* browser = crest::EngineBinding::Get().Browsers().Holding(contents);
  if (!browser || State().disposing) return nil;
  const ui::Accelerator accelerator = ShortcutAccelerator(event);
  if (accelerator.key_code() == ui::VKEY_UNKNOWN) return nil;
  Profile* profile = browser->GetProfile();
  auto* commands = extensions::CommandService::Get(profile);
  if (!commands) return nil;
  for (const auto& extension : extensions::ExtensionRegistry::Get(profile)->enabled_extensions()) {
    const auto& id = extension->id();
    if (profile->IsOffTheRecord() && !extensions::util::IsIncognitoEnabled(id, profile)) continue;
    // `_execute_action` is the action itself, so the core runs it through the
    // same path as a click on the extension's own button.
    extensions::Command action;
    bool active = false;
    if (commands->GetExtensionActionCommand(id, extensions::ActionInfo::Type::kAction,
            extensions::CommandService::ACTIVE, &action, &active) &&
        active && action.accelerator() == accelerator) {
      CrestExtensionShortcutResult* result = [[CrestExtensionShortcutResult alloc] init];
      result.actionExtensionID = base::SysUTF8ToNSString(id);
      return result;
    }
    ui::CommandMap named;
    if (!commands->GetNamedCommands(id, extensions::CommandService::ACTIVE,
                                    extensions::CommandService::REGULAR, &named)) continue;
    for (const auto& [name, command] : named) {
      if (command.accelerator() != accelerator) continue;
      DeliverExtensionCommand(profile, *extension, name, contents);
      return [[CrestExtensionShortcutResult alloc] init];
    }
  }
  return nil;
}
- (NSString*)engineVersion { return base::SysUTF8ToNSString(version_info::GetVersionNumber()); }
- (void)attachUI:(id<CrestMacUI>)ui {
  CHECK(NSThread.isMainThread);
  State().ui = ui;
}
- (id<CrestExtensionDownload>)downloadExtension:(NSString*)extensionID profile:(NSUUID*)profileID
                                       progress:(void (^)(double))progress
                                     completion:(void (^)(NSString*, NSString*))completion {
  CHECK(NSThread.isMainThread);
  const std::string id = base::SysNSStringToUTF8(extensionID);
  Profile* profile = crest::EngineBinding::Get().Profiles().Find(KeyFor(profileID));
  if (!profile || profile->IsOffTheRecord() || !crx_file::id_util::IdIsValid(id)) return nil;
  auto* download = new WebStoreDownload(progress, completion);
  CrestWebStoreDownloadHandle* handle = [[CrestWebStoreDownloadHandle alloc] initWithDownload:download->GetWeakPtr()];
  download->Start(profile, id);
  return handle;
}
- (BOOL)installExtension:(NSString*)extensionID package:(NSString*)path profile:(NSUUID*)profileID
                  window:(NSUUID*)windowID completion:(void (^)(BOOL, NSString*))completion {
  CHECK(NSThread.isMainThread);
  const std::string id = base::SysNSStringToUTF8(extensionID);
  Profile* profile = crest::EngineBinding::Get().Profiles().Find(KeyFor(profileID));
  NSWindow* window = [UI() windowWithID:windowID];
  if (!profile || profile->IsOffTheRecord() || !window || !crx_file::id_util::IdIsValid(id)) return NO;
  auto prompt = std::make_unique<ExtensionInstallPrompt>(profile, gfx::NativeWindow(window),
      std::make_unique<extensions::InstallPromptData>(extensions::InstallPromptData::UNSET_PROMPT_TYPE));
  prompt->SetSkipPostInstallUI(true);
  auto installer = extensions::CrxInstaller::Create(profile, std::move(prompt));
  installer->set_expected_id(id);
  installer->set_is_gallery_install(true);
  installer->set_delete_source(true);
  // Each target profile independently verifies CRX3 signature and publisher proof.
  installer->AddInstallerCallback(base::BindOnce(^(const std::optional<extensions::CrxInstallError>& error) {
    completion(!error, error ? base::SysUTF16ToNSString(error->message()) : @"");
  }));
  installer->InstallCrx(base::FilePath(base::SysNSStringToUTF8(path)));
  return YES;
}
- (void)disposePages:(NSArray<NSUUID*>*)pageIDs windows:(NSArray<NSUUID*>*)windowIDs
    releaseProfiles:(NSArray<NSUUID*>*)profileIDs {
  CHECK(NSThread.isMainThread);
  auto& binding = crest::EngineBinding::Get();
  // A Space-scoped popup is anchored in one of the windows or profiles being
  // released, and nothing else would close it.
  if (windowIDs.count || profileIDs.count) State().space_extension_popup.reset();
  for (NSUUID* identifier in pageIDs) binding.DestroyPage(KeyFor(identifier));
  for (NSUUID* identifier in windowIDs) {
    const auto id = KeyFor(identifier);
    // A sign-in window closed before its page reached the callback.
    EndAuthenticationSession(id, nil, false);
    binding.Browsers().CloseWindow(id);
  }
  for (NSUUID* identifier in profileIDs) binding.ReleaseProfile(KeyFor(identifier));
}
- (void)disposePages {
  CHECK(NSThread.isMainThread);
  auto& state = State();
  state.disposing = true;
  CancelAllAuthenticationSessions();
  state.space_extension_popup.reset();
  state.views.clear();
  // The core has stopped accepting work: the binding lets every page go,
  // closes its Browsers and releases the profiles.
  crest::EngineBinding::Get().Dispose();
}
- (void)cancelAuthenticationSessionForWindow:(NSUUID*)windowID {
  CHECK(NSThread.isMainThread);
  EndAuthenticationSession(KeyFor(windowID), nil, false);
}
- (void)completeQuit {
  State().quitting = true;
  if (base::CommandLine::ForCurrentProcess()->HasSwitch("crest-app-owned-host")) {
    [AppController.sharedController tryToTerminateApplication];
  } else {
    [NSApp terminate:nil];
  }
}
@end

namespace crest {
void SnapPictureInPictureWindow(views::Widget* widget) {
  if (!IsEnabled() || !widget) return;
  NSWindow* window = widget->GetNativeWindow().GetNativeNSWindow();
  NSScreen* screen = window.screen;
  if (!screen) return;
  constexpr CGFloat kMargin = 16;
  NSRect frame = window.frame;
  NSRect work = screen.visibleFrame;
  const CGFloat left = NSMinX(work) + kMargin;
  const CGFloat right = std::max(left, NSMaxX(work) - kMargin - NSWidth(frame));
  const CGFloat bottom = NSMinY(work) + kMargin;
  const CGFloat top = std::max(bottom, NSMaxY(work) - kMargin - NSHeight(frame));
  NSRect target = frame;
  target.origin.x = NSMidX(frame) < NSMidX(work) ? left : right;
  target.origin.y = NSMidY(frame) < NSMidY(work) ? bottom : top;
  if (std::abs(target.origin.x - frame.origin.x) < 1 &&
      std::abs(target.origin.y - frame.origin.y) < 1) return;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0.22;
    [[window animator] setFrame:target display:YES];
  } completionHandler:nil];
}

namespace {
bool MatchesAuthenticationCallback(ASWebAuthenticationSessionRequest* request, const GURL& url) {
  NSURL* candidate = net::NSURLWithGURL(url);
  if (!candidate) return false;
  if (@available(macOS 14.4, *)) return [request.callback matchesURL:candidate];
  return request.callbackURLScheme.length &&
      [candidate.scheme caseInsensitiveCompare:request.callbackURLScheme] == NSOrderedSame;
}

class AuthenticationSessionThrottle final : public content::NavigationThrottle {
 public:
  explicit AuthenticationSessionThrottle(content::NavigationThrottleRegistry& registry)
      : NavigationThrottle(registry) {}
  const char* GetNameForLogging() override { return "CrestAuthenticationSessionThrottle"; }
  ThrottleCheckResult WillStartRequest() override { return Check(); }
  ThrottleCheckResult WillRedirectRequest() override { return Check(); }

 private:
  ThrottleCheckResult Check() {
    auto& state = State();
    auto* navigation = navigation_handle();
    if (state.authentication_sessions.empty() || state.disposing || !navigation->IsInPrimaryMainFrame())
      return PROCEED;
    // Only a page of the Quick Window running the sign-in completes it.
    auto& binding = crest::EngineBinding::Get();
    content::WebContents* contents = navigation->GetWebContents();
    if (!binding.PageFor(contents)) return PROCEED;
    const std::string window = binding.Browsers().WindowOf(binding.Browsers().Holding(contents));
    auto session = state.authentication_sessions.find(window);
    if (window.empty() || session == state.authentication_sessions.end() ||
        !MatchesAuthenticationCallback(session->second, navigation->GetURL())) return PROCEED;
    // Completing closes the window and destroys this navigation's page, so
    // it happens after the navigation stack has unwound.
    NSURL* callback = net::NSURLWithGURL(navigation->GetURL());
    dispatch_async(dispatch_get_main_queue(), ^{ EndAuthenticationSession(window, callback, true); });
    return CANCEL_AND_IGNORE;
  }
};
}  // namespace

void AddNavigationThrottle(content::NavigationThrottleRegistry& registry) {
  if (!IsEnabled()) return;
  registry.AddThrottle(crest::EngineBinding::LinkThrottle(registry));
  registry.AddThrottle(std::make_unique<AuthenticationSessionThrottle>(registry));
}

bool BeginLinkDrag(content::WebContents* contents, const content::DropData& data) {
  // File, image, selection and custom payload drags retain Chromium's native path.
  // Chromium adds its own drag ID to every payload, including ordinary links.
  if (!IsEnabled() || State().disposing || data.url_infos.size() != 1 ||
      !data.url_infos[0].url.SchemeIsHTTPOrHTTPS() || data.url_infos[0].url.spec().size() > 8192 ||
      data.download_metadata || !data.filenames.empty() || !data.file_system_files.empty() ||
      !data.file_contents.empty() || data.file_contents_source_url.is_valid() ||
      std::any_of(data.custom_data.begin(), data.custom_data.end(),
          [](const auto& entry) { return entry.first != u"chromium/x-drag-id"; }) || !data.text ||
      *data.text != base::UTF8ToUTF16(data.url_infos[0].url.spec())) return false;
  auto* focused_frame = contents->GetFocusedFrame();
  if (!focused_frame || !focused_frame->GetView() ||
      !focused_frame->GetView()->GetSelectedText().empty()) return false;
  crest::EnginePage* page = crest::EngineBinding::Get().PageFor(contents);
  NSURL* url = net::NSURLWithGURL(data.url_infos[0].url);
  if (!page || !url) return false;
  return [UI() beginLinkDrag:url title:base::SysUTF16ToNSString(data.url_infos[0].title)
                        page:UUIDFor(page->key())];
}


void AppendLinkMenuItem(NSMenu* menu, content::WebContents* contents, const GURL& url,
                        const std::u16string& selection) {
  if (!IsEnabled() || State().disposing) return;
  crest::EnginePage* page = crest::EngineBinding::Get().PageFor(contents);
  if (!page) return;
  NSURL* link = url.SchemeIsHTTPOrHTTPS() ? net::NSURLWithGURL(url) : nil;
  NSString* const selected = base::SysUTF16ToNSString(
      std::u16string(base::TrimWhitespace(selection, base::TRIM_ALL)));
  if (!link && !selected.length) return;
  // Crest's rows go ahead of the engine's. MenuControllerCocoa identifies its
  // rows by their model indices, so rows inserted ahead of them change only
  // their native positions.
  [UI() addPageMenuItems:menu page:UUIDFor(page->key()) link:link selection:selected.length ? selected : nil];
}

// A page the core asked whether it may close answers the core.
bool CompletePageClosePreparation(content::WebContents* contents, bool proceed) {
  return crest::AnswerBeforeUnload(contents, proceed);
}
void ShowExtensionPrompt(
    std::unique_ptr<ExtensionInstallPromptShowParams> params,
    ExtensionInstallPrompt::DoneCallback callback,
    std::unique_ptr<extensions::InstallPromptData> prompt) {
  using Result = extensions::ExtensionInstallPromptClient::Result;
  using Payload = ExtensionInstallPrompt::DoneCallbackPayload;
  NSWindow* window = params->GetParentWindow().GetNativeNSWindow();
  if (!window || window.attachedSheet || params->WasParentDestroyed() || prompt->requires_parent_permission()) {
    std::move(callback).Run(Payload(Result::ABORTED));
    return;
  }
  struct PendingPrompt {
    std::unique_ptr<ExtensionInstallPromptShowParams> params;
    ExtensionInstallPrompt::DoneCallback callback;
    std::unique_ptr<extensions::InstallPromptData> prompt;
  };
  auto pending = std::make_shared<PendingPrompt>(std::move(params), std::move(callback), std::move(prompt));
  // An install a Crest window started is a question for the core, which the
  // window's own review answers.
  const auto window_id = window.identifier ? crest::ParseGuid(base::SysNSStringToUTF8(window.identifier)) : std::nullopt;
  if (window_id && pending->prompt->extension() &&
      pending->prompt->type() == extensions::InstallPromptData::INSTALL_PROMPT) {
    auto* extension = pending->prompt->extension();
    crest::engine::ExtensionInstallQuestion question{
        .extension_id = extension->id(),
        .name = extension->name(),
        .version = extension->version().GetString(),
        .can_withhold_site_access = extensions::util::CanWithholdPermissionsFromExtension(*extension),
        .withholds_site_access = pending->prompt->ShouldWithheldPermissionsOnDialogAccept()};
    if (const std::string* summary = extension->manifest()->FindStringPath("description")) question.summary = *summary;
    const auto permission_details = pending->prompt->GetPermissions();
    for (size_t i = 0; i < pending->prompt->GetPermissionCount(); ++i) {
      question.permissions.push_back(base::UTF16ToUTF8(pending->prompt->GetPermission(i)));
      if (i < permission_details.details.size() && !permission_details.details[i].empty())
        question.permissions.push_back(base::UTF16ToUTF8(permission_details.details[i]));
    }
    if (!pending->prompt->icon().IsEmpty()) {
      if (auto png = pending->prompt->icon().As1xPNGBytes(); png && png->size())
        question.icon = crest::engine::Bytes(png->data(), png->data() + png->size());
    }
    crest::EngineBinding::Get().Prompts().AskToInstall(*window_id, std::move(question),
        base::BindOnce([](std::shared_ptr<PendingPrompt> pending, bool accepted, bool withhold) {
          if (!pending->callback) return;
          Result result = Result::USER_CANCELED;
          if (pending->params->WasParentDestroyed()) result = Result::ABORTED;
          else if (accepted) { result = withhold ? Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS : Result::ACCEPTED; pending->prompt->OnDialogAccepted(); }
          else pending->prompt->OnDialogCanceled();
          std::move(pending->callback).Run(Payload(result));
        }, pending));
    return;
  }
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = base::SysUTF16ToNSString(pending->prompt->GetDialogTitle());
  NSMutableArray* messages = [NSMutableArray array];
  if (pending->prompt->GetPermissionCount()) {
    [messages addObject:base::SysUTF16ToNSString(pending->prompt->GetPermissionsHeading())];
    for (size_t i = 0; i < pending->prompt->GetPermissionCount(); ++i)
      [messages addObject:base::SysUTF16ToNSString(pending->prompt->GetPermission(i))];
  }
  const bool withhold = pending->prompt->ShouldWithheldPermissionsOnDialogAccept();
  if (withhold) [messages addObject:@"Website access is withheld until you grant it in extension settings."];
  alert.informativeText = [messages componentsJoinedByString:@"\n\n"];
  NSString* accept = base::SysUTF16ToNSString(pending->prompt->GetAcceptButtonLabel());
  if (accept.length) [alert addButtonWithTitle:accept];
  [alert addButtonWithTitle:base::SysUTF16ToNSString(pending->prompt->GetAbortButtonLabel())];
  if (accept.length) {
    alert.buttons.firstObject.enabled = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      alert.buttons.firstObject.enabled = YES;
    });
  }
  id closed = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
      object:window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*) {
    if (alert.window.sheetParent) [alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
  }];
  [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
    [[NSNotificationCenter defaultCenter] removeObserver:closed];
    Result result = Result::USER_CANCELED;
    if (pending->params->WasParentDestroyed()) result = Result::ABORTED;
    else if (accept.length && response == NSAlertFirstButtonReturn) {
      result = withhold ? Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS : Result::ACCEPTED;
      pending->prompt->OnDialogAccepted();
    } else pending->prompt->OnDialogCanceled();
    std::move(pending->callback).Run(Payload(result));
  }];
}

std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* contents, permissions::PermissionPrompt::Delegate* delegate) {
  if (delegate->ShouldDropCurrentRequestIfCannotShowQuietly()) return nullptr;
  // Requests raised again while they take an answer already have it; see
  // AnswerPermissionRequests.
  if (State().answering_permission == delegate) return nullptr;
  // A request Crest's permission record covers is asked through the page, so
  // the decision is recorded per Space and listed in Privacy.
  if (auto prompt = crest::EngineBinding::Get().PermissionPrompt(contents, delegate)) return prompt;
  BrowserWindowInterface* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  NSWindow* window = browser ? WindowForBrowser(static_cast<Browser*>(browser)) : nil;
  if (!window || window.attachedSheet) return nullptr;
  return std::make_unique<NativePermissionPrompt>(window, delegate);
}

void AnswerPermissionRequests(permissions::PermissionPrompt::Delegate& delegate, bool grants, bool remembers) {
  base::AutoReset<raw_ptr<const permissions::PermissionPrompt::Delegate>> answering(
      &State().answering_permission, &delegate);
  if (grants && remembers) {
    delegate.Accept(std::monostate());
  } else if (grants) {
    delegate.AcceptThisTime(std::monostate());
  } else if (remembers) {
    delegate.Deny(std::monostate());
  } else {
    delegate.Dismiss(std::monostate());
  }
}
namespace {
bool HasBundleMarker(NSString* name) {
  NSString* path = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name];
  return path && [NSFileManager.defaultManager fileExistsAtPath:path];
}
// A product bundle hosts the native Crest UI for every launch, including the
// ones Crest cannot add switches to: Finder, login items, the default-browser
// role and Dock reopen. Experiment bundles keep requiring the explicit switch.
bool IsProductBundle() {
  static const bool product = HasBundleMarker(@"Crest-Native-Host");
  return product;
}
}  // namespace
bool IsEnabled() {
  static const bool enabled =
      IsProductBundle() || base::CommandLine::ForCurrentProcess()->HasSwitch("crest-control-plane");
  return enabled;
}
void EnsureCrestUIStarted(Browser* browser) {
  CHECK(NSThread.isMainThread);
  if (State().started) return;
  // An experiment bundle must name its own engine profile root. A product
  // bundle uses Chromium's default directory for its own bundle identity.
  CHECK(IsProductBundle() || base::CommandLine::ForCurrentProcess()->HasSwitch("user-data-dir"));
  // The review and product compositions keep separate framework names so a
  // package can only ever contain the one it was assembled from.
  NSBundle* bundle = nil;
  for (NSString* name in @[ @"CrestChromiumUI.framework", @"CrestChromiumUIProduct.framework" ]) {
    NSString* path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:name];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
    bundle = [NSBundle bundleWithPath:path];
    break;
  }
  CHECK(bundle);
  NSError* error = nil;
  CHECK([bundle loadAndReturnError:&error]) << base::SysNSStringToUTF8(error.description);
  // The framework's one entry point. It registers the binding with the core
  // the framework creates, and keeps the shell for what only AppKit does.
  base::apple::ScopedCFTypeRef<CFBundleRef> framework(
      CFBundleCreate(kCFAllocatorDefault, base::apple::NSToCFPtrCast(bundle.bundleURL)));
  auto start = reinterpret_cast<CrestChromiumUIStart>(
      CFBundleGetFunctionPointerForName(framework.get(), CFSTR("crest_chromium_ui_start")));
  CHECK(start);
  State().started = true;
  static base::NoDestructor<MacShell> shell;
  auto& binding = crest::EngineBinding::Get();
  binding.SetShell(shell.get());
  const crest_engine_binding_t table = binding.Table();
  const crest_engine_pages_t pages = binding.Pages();
  const auto& fingerprint = crest::EngineBinding::Fingerprint();
  start([[CrestChromiumMacShell alloc] init], &table, fingerprint.data(), fingerprint.size(), &pages);
  auto pending = std::move(State().pending_authentication_sessions);
  State().pending_authentication_sessions.clear();
  for (ASWebAuthenticationSessionRequest* request : pending) StartAuthenticationSession(request);
}
id<CrestMacUI> MacUI() {
  return UI();
}
// Whether AppKit is hosting Crest is the shell's to say: before Crest's UI
// runs, and once it is shutting down or a quit has been accepted, the engine's
// own answer stands. Otherwise the binding decides, since it keeps the
// Browsers.
bool CanCreateEngineBrowser(Profile* profile) {
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return true;
  return crest::EngineBinding::Get().Browsers().MayCreate(profile);
}
NSWindow* WindowForBrowser(Browser* browser) {
  if (!State().started) return nil;
  const auto& browsers = crest::EngineBinding::Get().Browsers();
  // A reserved engine window has an identifier before it has a window: a
  // renderer popup never opens the one reserved for it, because its tab is
  // adopted into the opener's window. Those Browsers keep the same fallback
  // they had before they carried an identifier at all.
  if (NSUUID* identifier = UUIDFor(browsers.WindowOf(browser))) {
    if (NSWindow* window = [UI() windowWithID:identifier]) return window;
  }
  // The window a Browser is being created for, or with none, the window an
  // engine surface with no window of its own is shown in.
  return [UI() windowWithID:UUIDFor(browsers.creating_window())];
}
bool DeferQuit() {
  return IsEnabled() && State().started && !State().quitting && [UI() deferQuit];
}
bool Reopen() {
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return false;
  return [UI() reopen];
}
bool OpenExternalURLs(NSArray<NSURL*>* urls) {
  // Before the native root exists there is nothing to route into, and after a
  // quit has been accepted there is nothing left to open. Chromium then keeps
  // its own behavior rather than dropping the request.
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return false;
  return [UI() openExternalURLs:urls];
}
NSMenu* DockMenu() {
  if (!IsEnabled() || !State().started || State().disposing || State().quitting) return nil;
  return [UI() dockMenu];
}
bool BeginAuthenticationSession(ASWebAuthenticationSessionRequest* request) {
  CHECK(NSThread.isMainThread);
  if (!IsEnabled()) return false;
  if (!State().started) { State().pending_authentication_sessions.push_back(request); return true; }
  StartAuthenticationSession(request);
  return true;
}
bool CancelAuthenticationSession(ASWebAuthenticationSessionRequest* request) {
  CHECK(NSThread.isMainThread);
  if (!IsEnabled()) return false;
  auto& state = State();
  auto pending = std::find_if(state.pending_authentication_sessions.begin(),
      state.pending_authentication_sessions.end(),
      [&](ASWebAuthenticationSessionRequest* candidate) { return [candidate.UUID isEqual:request.UUID]; });
  if (pending != state.pending_authentication_sessions.end()) {
    state.pending_authentication_sessions.erase(pending);
    [request cancelWithError:[NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain
                                                 code:ASWebAuthenticationSessionErrorCodeCanceledLogin
                                             userInfo:nil]];
    return true;
  }
  for (const auto& [window, candidate] : state.authentication_sessions) {
    if (![candidate.UUID isEqual:request.UUID]) continue;
    EndAuthenticationSession(std::string(window), nil, true);
    break;
  }
  return true;
}
void TranslateSelection(const std::u16string& text) {
  if (!IsEnabled() || !State().started || State().disposing || text.empty()) return;
  [UI() translateText:base::SysUTF16ToNSString(text)];
}
void ShowEngineNotice(const std::u16string& message, ToastId toast) {
  if (!IsEnabled() || !State().started || State().disposing || message.empty()) return;
  [UI() showEngineNotice:base::SysUTF16ToNSString(message)
                    kind:toast == ToastId::kLinkCopied ? CrestEngineNoticeKindLinkCopied
                                                       : CrestEngineNoticeKindConfirmation];
}
}  // namespace crest
