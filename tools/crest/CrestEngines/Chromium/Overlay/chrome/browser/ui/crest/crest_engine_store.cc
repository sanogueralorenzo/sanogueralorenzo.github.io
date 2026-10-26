#include "chrome/browser/ui/crest/crest_engine_store.h"

#include <string_view>
#include <vector>

#include "base/json/json_writer.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/values.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_registry.h"
#include "url/gurl.h"
#include "url/url_constants.h"

namespace crest {

namespace {

bool IsWebStoreURL(const GURL& url) {
  return url.SchemeIs(url::kHttpsScheme) && url.host() == "chromewebstore.google.com";
}

// Chrome Web Store identifiers are 32 characters from a-p.
bool IsExtensionID(std::string_view candidate) {
  if (candidate.size() != 32) return false;
  for (char character : candidate)
    if (character < 'a' || character > 'p') return false;
  return true;
}

// The extension a store listing URL names, or an empty string for any other
// store page. A listing is /detail/<id> or /detail/<name>/<id>, and its
// reviews and support pages add a segment after the identifier.
std::string WebStoreExtensionID(const GURL& url) {
  if (!IsWebStoreURL(url)) return std::string();
  const std::string_view path = url.path();
  std::vector<std::string_view> parts = base::SplitStringPiece(
      path, "/", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
  if (parts.size() < 2 || parts.front() != "detail") return std::string();
  if (parts.size() > 2 && IsExtensionID(parts[2])) return std::string(parts[2]);
  if (IsExtensionID(parts[1])) return std::string(parts[1]);
  return std::string();
}

// The isolated-world script. It uses DOM and CSSOM APIs only: the store's
// content policy rejects stylesheets and inline style attributes Crest would
// add to the markup, but script-driven property changes are not markup.
const char* CrestStoreScript() {
  return R"JS((function() {
  if (window.__crestStore) { window.__crestStore.render(); return; }
  var labels = { install: 'Add to Crest', installed: 'Added to Crest',
                 remove: 'Remove from Crest', busy: 'Installing…' };
  var state = { id: '', installed: false, busy: false };
  var adopted = null, hovering = false, pending = false;
  // The host's listing rule: /detail/<id> or /detail/<name>/<id>, optionally
  // followed by the listing's reviews or support page.
  function detailID() {
    var match = /^\/detail\/(?:[^\/]+\/)?([a-p]{32})(?:\/|$)/.exec(location.pathname);
    return match ? match[1] : '';
  }
  function label(button) { return button.querySelector('span[jsname="V67aGc"]') || button; }
  function text(node) { return (node.textContent || '').replace(/\s+/g, ' ').trim(); }
  // The store keeps the listing it navigated away from in the document and
  // only hides it, so anything that is not actually rendered is stale.
  function shown(element) {
    if (!element || !element.isConnected) return false;
    var rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }
  // The store words its button in the page's language, and some languages
  // leave Chrome out of it, so the button is known by what the store does
  // with it: it is the labelled control the store disables for a browser that
  // is not Chrome, or the one that names Chrome or, once adopted, Crest.
  function installButton(button) {
    var value = text(label(button));
    return value !== '' && (button.disabled || /chrome|crest/i.test(value));
  }
  // The listing's own install button: the one in the section that carries the
  // extension's title, so a related listing's button is never adopted.
  function locate() {
    if (shown(adopted)) return adopted;
    adopted = null; hovering = false;
    if (!detailID()) return null;
    var headings = document.querySelectorAll('h1'), scope = null;
    for (var heading = 0; heading < headings.length; heading++) {
      if (!shown(headings[heading])) continue;
      scope = headings[heading].closest('section');
      break;
    }
    if (!scope) return null;
    var buttons = scope.querySelectorAll('button');
    for (var index = 0; index < buttons.length; index++) {
      var button = buttons[index];
      if (!shown(button) || !installButton(button)) continue;
      adopted = button;
      button.addEventListener('pointerenter', function() { hovering = true; render(); });
      button.addEventListener('pointerleave', function() { hovering = false; render(); });
      button.addEventListener('focus', function() { hovering = true; render(); });
      button.addEventListener('blur', function() { hovering = false; render(); });
      return button;
    }
    return null;
  }
  // The store's desktop layout keeps a minimum width wider than a Crest page
  // card, which pushes the listing and its install button past the card's
  // edge. Releasing that minimum lets the store use its own narrow layout.
  function relax() {
    // The store keeps the listing it navigated away from, so each document can
    // hold more than one of these; every one of them has to be released.
    var elements = [document.body].concat(
        Array.prototype.slice.call(document.querySelectorAll('header, main')));
    for (var index = 0; index < elements.length; index++) {
      var element = elements[index];
      if (!element) continue;
      var minimum = parseFloat(getComputedStyle(element).minWidth);
      if (minimum > 0 && minimum > window.innerWidth) element.style.minWidth = 'auto';
    }
  }
  // Crest installs extensions itself, so the store's prompts to switch to
  // Chrome are noise. Their wording follows the page's language, so each is
  // found from the action it offers: the dialog links to Chrome's download
  // page, and the listing's notice holds the store's Install Chrome button,
  // which the store's own analytics name 276336.
  var promptActions = '[role="dialog"] a[href^="https://www.google.com/chrome/"], ' +
                      'button[jslog^="276336;"]';
  // The outermost element around a notice's action that holds no other
  // control and no heading, so the listing around it is never affected.
  function notice(action) {
    var box = action;
    for (var parent = box.parentElement; parent && parent !== document.body;
         parent = parent.parentElement) {
      if (parent.querySelector('h1, h2, h3') ||
          parent.querySelectorAll('a[href], button').length > 1) break;
      box = parent;
    }
    return box;
  }
  function hidePrompts() {
    var actions = document.querySelectorAll(promptActions);
    for (var index = 0; index < actions.length; index++) {
      var box = actions[index].closest('[role="dialog"]') || notice(actions[index]);
      if (box.style.display !== 'none') box.style.display = 'none';
    }
  }
  function render() {
    relax();
    hidePrompts();
    var button = locate();
    if (!button) return;
    var wanted = state.busy ? labels.busy
        : (state.installed ? (hovering ? labels.remove : labels.installed) : labels.install);
    var span = label(button);
    if (text(span) !== wanted) span.textContent = wanted;
    if (button.disabled) button.disabled = false;
    button.removeAttribute('disabled');
    button.setAttribute('aria-disabled', state.busy ? 'true' : 'false');
    button.setAttribute('aria-label', wanted);
    // The labels are Crest's English, whatever the store's language, so
    // assistive technology reads them as English and a right-to-left page
    // keeps the progress label's ellipsis at its end.
    if (button.lang !== 'en') button.lang = 'en';
    if (button.dir !== 'ltr') button.dir = 'ltr';
  }
  function schedule() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function() { pending = false; render(); });
  }
  // The core owns the install review, so the click never reaches the store's
  // own handler. The request names the extension the page itself is showing
  // and the core checks that name again before it downloads anything.
  function request() {
    var id = detailID();
    if (!id || state.busy) return;
    var command = state.installed ? 'crest-remove' : 'crest-install';
    if (!state.installed) { state.busy = true; render(); }
    history.replaceState(history.state, '',
        location.pathname + location.search + '#' + command + '=' + id);
  }
  document.addEventListener('click', function(event) {
    var button = locate();
    var target = event.target;
    if (!button || !target || !(target === button || (target.nodeType === 1 && button.contains(target)))) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    request();
  }, true);
  window.addEventListener('resize', function() { schedule(); });
  new MutationObserver(schedule).observe(document.documentElement,
      { childList: true, subtree: true, characterData: true });
  window.__crestStore = {
    render: render,
    apply: function(next) {
      state.id = next && typeof next.id === 'string' ? next.id : '';
      state.installed = !!(next && next.installed);
      state.busy = false;
      if (!adopted || !adopted.isConnected) { adopted = null; }
      render();
    }
  };
  render();
})();)JS";
}

}  // namespace

PageStore::PageStore(content::WebContents* contents, const engine::Guid& page, Present present)
    : contents_(contents), page_(page), present_(std::move(present)) {}

PageStore::~PageStore() = default;

void PageStore::DocumentAvailable() {
  if (!Frame()) {
    return;
  }
  Run(CrestStoreScript());
  Refresh();
}

bool PageStore::Committed(const GURL& url) {
  if (Consume(url)) {
    return true;
  }
  // The store is a single-page application: a listing change keeps the
  // document, so the script stays and only its state has to be refreshed.
  // Restoring the listing's own address is Crest's own edit, not a change of
  // listing, so it must not reset a request that is still open.
  if (request_open_) {
    request_open_ = false;
  } else {
    Refresh();
  }
  return false;
}

void PageStore::RequestFinished() {
  request_open_ = false;
  Refresh();
}

void PageStore::Refresh() {
  auto* frame = Frame();
  if (!frame) {
    return;
  }
  const std::string id = WebStoreExtensionID(frame->GetLastCommittedURL());
  bool installed = false;
  if (!id.empty()) {
    auto* registry = extensions::ExtensionRegistry::Get(contents_->GetBrowserContext());
    installed = registry && registry->GetInstalledExtension(id) != nullptr;
  }
  auto json = base::WriteJson(base::DictValue().Set("id", id).Set("installed", installed));
  if (!json) {
    return;
  }
  Run("window.__crestStore && window.__crestStore.apply(" + *json + ");");
}

// Regular profiles only: a private window must not change a Space's
// persistent extension state, so its store pages keep the engine's own
// behaviour.
content::RenderFrameHost* PageStore::Frame() const {
  if (contents_->GetBrowserContext()->IsOffTheRecord()) {
    return nullptr;
  }
  auto* frame = contents_->GetPrimaryMainFrame();
  if (!frame || !IsWebStoreURL(frame->GetLastCommittedURL())) {
    return nullptr;
  }
  return frame;
}

void PageStore::Run(const std::string& script) {
  if (auto* frame = Frame()) {
    frame->ExecuteJavaScriptInIsolatedWorld(base::UTF8ToUTF16(script), {}, ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
}

// A request the injected script wrote into the listing's own URL fragment.
// The extension it names has to be the one the page is showing, so a store
// page cannot ask Crest to install anything else, and Crest still runs its
// own install review before the engine verifies the package.
bool PageStore::Consume(const GURL& url) {
  if (!Frame() || !url.has_ref()) {
    return false;
  }
  const std::string_view ref = url.ref();
  constexpr std::string_view kInstall = "crest-install=";
  constexpr std::string_view kRemove = "crest-remove=";
  bool removes = false;
  std::string requested;
  if (base::StartsWith(ref, kInstall)) {
    requested = std::string(ref.substr(kInstall.size()));
  } else if (base::StartsWith(ref, kRemove)) {
    removes = true;
    requested = std::string(ref.substr(kRemove.size()));
  } else {
    return false;
  }
  // Leave the listing's own address in place; the fragment is a message.
  Run("history.replaceState(history.state, '', location.pathname + location.search);");
  const std::string expected = WebStoreExtensionID(url);
  if (expected.empty() || requested != expected) {
    Refresh();
    return true;
  }
  // Crest owns the request now: the button keeps its own progress label
  // until the review Crest presents finishes.
  request_open_ = true;
  if (removes) {
    present_.Run(engine::StoreRemovalRequested{.page_id = page_, .extension_id = expected});
  } else {
    present_.Run(engine::StoreInstallRequested{.page_id = page_, .extension_id = expected});
  }
  return true;
}

}  // namespace crest
