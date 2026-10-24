#include "chrome/browser/ui/crest/crest_engine_agent.h"

#include <cmath>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/strings/utf_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/global_request_id.h"
#include "net/base/net_errors.h"
#include "third_party/blink/public/mojom/loader/resource_load_info.mojom.h"
#include "url/gurl.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "third_party/blink/public/mojom/devtools/console_message.mojom.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

namespace crest {

namespace {

// Seconds from the Unix epoch to the wire's reference date, 2001-01-01.
constexpr double kReferenceDateOffset = 978307200;
// The largest protocol message the page reads.
constexpr size_t kMaximumMessageBytes = 32 * 1024 * 1024;
// The largest view a held page renders at.
constexpr double kMaximumHeldSide = 8192;

engine::Date DateOf(base::Time time) {
  return engine::Date{.seconds_since_2001 = time.InSecondsFSinceUnixEpoch() - kReferenceDateOffset};
}

// Whether `url` shows a web page, a blank one or none yet, which an agent may
// use, rather than one of the browser's own, an extension's or a file.
bool IsWebPage(const GURL& url) {
  return url.is_empty() || url.IsAboutBlank() || url.SchemeIsHTTPOrHTTPS();
}

// The kind of a finished load as DevTools names it.
std::string ResourceTypeOf(network::mojom::RequestDestination destination) {
  switch (destination) {
    case network::mojom::RequestDestination::kDocument:
    case network::mojom::RequestDestination::kIframe:
    case network::mojom::RequestDestination::kFrame:
      return "Document";
    case network::mojom::RequestDestination::kScript:
      return "Script";
    case network::mojom::RequestDestination::kStyle:
      return "Stylesheet";
    case network::mojom::RequestDestination::kImage:
      return "Image";
    case network::mojom::RequestDestination::kFont:
      return "Font";
    case network::mojom::RequestDestination::kAudio:
    case network::mojom::RequestDestination::kVideo:
    case network::mojom::RequestDestination::kTrack:
      return "Media";
    case network::mojom::RequestDestination::kManifest:
      return "Manifest";
    case network::mojom::RequestDestination::kEmpty:
      return "Fetch";
    default:
      return "Other";
  }
}

std::string Clipped(std::string text) {
  if (text.size() > PageAgent::kMaximumText) {
    text.resize(PageAgent::kMaximumText);
  }
  return text;
}

// DevTools modifier bits: Alt 1, Ctrl 2, Meta 4, Shift 8.
int ProtocolModifiers(engine::KeyModifiers modifiers) {
  int bits = 0;
  if (engine::Has(modifiers, engine::KeyModifiers::kOption)) {
    bits |= 1;
  }
  if (engine::Has(modifiers, engine::KeyModifiers::kControl)) {
    bits |= 2;
  }
  if (engine::Has(modifiers, engine::KeyModifiers::kCommand)) {
    bits |= 4;
  }
  if (engine::Has(modifiers, engine::KeyModifiers::kShift)) {
    bits |= 8;
  }
  return bits;
}

const char* ProtocolButton(engine::PointerButton button) {
  switch (button) {
    case engine::PointerButton::kPrimary:
      return "left";
    case engine::PointerButton::kSecondary:
      return "right";
    case engine::PointerButton::kMiddle:
      return "middle";
  }
  return "left";
}

int ProtocolButtons(engine::PointerButton button) {
  switch (button) {
    case engine::PointerButton::kPrimary:
      return 1;
    case engine::PointerButton::kSecondary:
      return 2;
    case engine::PointerButton::kMiddle:
      return 4;
  }
  return 1;
}

engine::PageConsoleLevel LevelOf(blink::mojom::ConsoleMessageLevel level) {
  switch (level) {
    case blink::mojom::ConsoleMessageLevel::kVerbose:
      return engine::PageConsoleLevel::kDebug;
    case blink::mojom::ConsoleMessageLevel::kInfo:
      return engine::PageConsoleLevel::kLog;
    case blink::mojom::ConsoleMessageLevel::kWarning:
      return engine::PageConsoleLevel::kWarning;
    case blink::mojom::ConsoleMessageLevel::kError:
      return engine::PageConsoleLevel::kError;
  }
  return engine::PageConsoleLevel::kLog;
}

std::vector<engine::PageHeader> HeadersOf(const base::DictValue* headers) {
  std::vector<engine::PageHeader> list;
  if (!headers) {
    return list;
  }
  for (const auto [name, value] : *headers) {
    if (value.is_string()) {
      list.push_back(engine::PageHeader{.name = Clipped(name), .value = Clipped(value.GetString())});
    }
  }
  return list;
}

bool ValidPoint(const engine::PagePoint& point) {
  return std::isfinite(point.x) && std::isfinite(point.y) && point.x >= 0 && point.y >= 0;
}

base::DictValue MouseEvent(const char* type, const engine::PagePoint& point) {
  return base::DictValue().Set("type", type).Set("x", point.x).Set("y", point.y);
}

}  // namespace

PageAgent::PageAgent(content::WebContents* contents, const engine::Guid& page, Present present)
    : content::WebContentsObserver(contents), page_(page), present_(std::move(present)) {}

PageAgent::~PageAgent() {
  rendering_.RunAndReset();
  Detach();
}

bool PageAgent::Evaluate(const engine::Guid& evaluation, const std::string& source, engine::PageScriptWorld world) {
  if (!web_contents() || !IsWebPage(web_contents()->GetPrimaryMainFrame()->GetLastCommittedURL())) {
    return false;
  }
  if (world == engine::PageScriptWorld::kPage) {
    if (!Attach()) {
      return false;
    }
    Send("Runtime.evaluate",
         base::DictValue()
             .Set("expression", "(async () => {\n" + source + "\n})()")
             .Set("awaitPromise", true)
             .Set("returnByValue", true)
             .Set("userGesture", true),
         base::BindOnce(
             [](base::WeakPtr<PageAgent> agent, engine::Guid evaluation, const base::DictValue* result) {
               if (!agent) {
                 return;
               }
               engine::PageScriptEvaluated answer{.page_id = agent->page_, .evaluation_id = evaluation};
               if (!result) {
                 agent->present_.Run(std::move(answer));
                 return;
               }
               if (const auto* exception = result->FindDict("exceptionDetails")) {
                 const std::string* description = exception->FindStringByDottedPath("exception.description");
                 const std::string* text = exception->FindString("text");
                 answer.error = Clipped(description ? *description : text ? *text : "The script threw.");
               } else {
                 const base::Value* value = result->FindByDottedPath("result.value");
                 answer.json = value ? base::WriteJson(*value) : base::WriteJson(base::Value());
               }
               agent->present_.Run(std::move(answer));
             },
             weak_factory_.GetWeakPtr(), evaluation));
    return true;
  }
  content::RenderFrameHost* frame = web_contents()->GetPrimaryMainFrame();
  if (!frame || !frame->IsRenderFrameLive()) {
    return false;
  }
  // The world awaits the script and answers what it settled with, so a throw
  // reaches the agent as its message rather than as nothing.
  const std::string script =
      "(async () => { try { return { value: await (async () => {\n" + source +
      "\n})() }; } catch (error) { return { error: String((error && error.message) || error) }; } })()";
  frame->ExecuteJavaScriptInIsolatedWorld(
      base::UTF8ToUTF16(script),
      mojo::WrapCallbackWithDefaultInvokeIfNotRun(
          base::BindOnce(&PageAgent::Answered, weak_factory_.GetWeakPtr(), evaluation), base::Value()),
      kAgentWorldID);
  return true;
}

bool PageAgent::Click(const engine::Guid& input,
                      const engine::PagePoint& point,
                      engine::PointerButton button,
                      int count,
                      engine::KeyModifiers modifiers) {
  if (!ValidPoint(point) || count < 1 || count > 3 || !Attach()) {
    return false;
  }
  std::vector<std::pair<const char*, base::DictValue>> events;
  events.emplace_back("Input.dispatchMouseEvent",
                      MouseEvent("mouseMoved", point).Set("modifiers", ProtocolModifiers(modifiers)));
  for (int click = 1; click <= count; ++click) {
    for (const char* type : {"mousePressed", "mouseReleased"}) {
      events.emplace_back("Input.dispatchMouseEvent", MouseEvent(type, point)
                                                          .Set("button", ProtocolButton(button))
                                                          .Set("buttons", ProtocolButtons(button))
                                                          .Set("clickCount", click)
                                                          .Set("modifiers", ProtocolModifiers(modifiers)));
    }
  }
  Deliver(input, std::move(events));
  return true;
}

bool PageAgent::Hover(const engine::Guid& input, const engine::PagePoint& point) {
  if (!ValidPoint(point) || !Attach()) {
    return false;
  }
  std::vector<std::pair<const char*, base::DictValue>> events;
  events.emplace_back("Input.dispatchMouseEvent", MouseEvent("mouseMoved", point));
  Deliver(input, std::move(events));
  return true;
}

bool PageAgent::Scroll(const engine::Guid& input, const engine::PagePoint& point, double delta_x, double delta_y) {
  if (!ValidPoint(point) || !std::isfinite(delta_x) || !std::isfinite(delta_y) || !Attach()) {
    return false;
  }
  std::vector<std::pair<const char*, base::DictValue>> events;
  events.emplace_back("Input.dispatchMouseEvent",
                      MouseEvent("mouseWheel", point).Set("deltaX", delta_x).Set("deltaY", delta_y));
  Deliver(input, std::move(events));
  return true;
}

bool PageAgent::Type(const engine::Guid& input, const std::string& text) {
  if (text.empty() || !Attach()) {
    return false;
  }
  std::vector<std::pair<const char*, base::DictValue>> events;
  events.emplace_back("Input.insertText", base::DictValue().Set("text", text));
  Deliver(input, std::move(events));
  return true;
}

bool PageAgent::PressKey(const engine::Guid& input, const engine::PageKey& key, engine::KeyModifiers modifiers) {
  if (key.key.empty() || !Attach()) {
    return false;
  }
  auto event = [&](const char* type) {
    auto params = base::DictValue()
                      .Set("type", type)
                      .Set("key", key.key)
                      .Set("code", key.code)
                      .Set("windowsVirtualKeyCode", key.key_code)
                      .Set("modifiers", ProtocolModifiers(modifiers));
    return params;
  };
  std::vector<std::pair<const char*, base::DictValue>> events;
  if (key.text && !key.text->empty()) {
    events.emplace_back("Input.dispatchKeyEvent",
                        event("keyDown").Set("text", *key.text).Set("unmodifiedText", *key.text));
  } else {
    events.emplace_back("Input.dispatchKeyEvent", event("rawKeyDown"));
  }
  events.emplace_back("Input.dispatchKeyEvent", event("keyUp"));
  Deliver(input, std::move(events));
  return true;
}

bool PageAgent::ObserveActivity(bool observing) {
  if (observing == observing_) {
    return true;
  }
  observing_ = observing;
  if (!observing) {
    console_.clear();
    network_.clear();
    requests_.clear();
    console_dropped_ = 0;
    network_dropped_ = 0;
    if (network_enabled_) {
      network_enabled_ = false;
      Send("Network.disable", base::DictValue(), base::DoNothing());
    }
    if (!rendering_) {
      Detach();
    }
    return true;
  }
  if (!Attach()) {
    observing_ = false;
    return false;
  }
  // Requests are watched, never kept: no body is buffered for the agent.
  network_enabled_ = true;
  Send("Network.enable",
       base::DictValue().Set("maxTotalBufferSize", 0).Set("maxResourceBufferSize", 0).Set("maxPostDataSize", 0),
       base::DoNothing());
  return true;
}

engine::PageConsoleLog PageAgent::Console(int64_t after) const {
  engine::PageConsoleLog log{.dropped = console_dropped_};
  for (const auto& message : console_) {
    if (message.sequence > after) {
      log.messages.push_back(message);
    }
  }
  return log;
}

engine::PageNetworkLog PageAgent::Network(int64_t after) const {
  engine::PageNetworkLog log{.dropped = network_dropped_};
  for (const auto& request : network_) {
    if (request.sequence > after) {
      log.requests.push_back(request);
    }
  }
  return log;
}

bool PageAgent::HoldRendering(bool held, double width, double height) {
  if (!web_contents()) {
    return false;
  }
  if (!held) {
    rendering_.RunAndReset();
    // The page counts as unfocused and hidden again; once the agent no
    // longer watches it either, it keeps nothing of the agent's.
    if (!observing_) {
      Detach();
    } else if (attached_) {
      Send("Emulation.setFocusEmulationEnabled", base::DictValue().Set("enabled", false), base::DoNothing());
    }
    return true;
  }
  if (!std::isfinite(width) || !std::isfinite(height) || width < 1 || height < 1 || width > kMaximumHeldSide ||
      height > kMaximumHeldSide) {
    return false;
  }
  const gfx::Size size(static_cast<int>(width), static_cast<int>(height));
  // A page no window has shown has a view of no size, which neither lays out,
  // captures nor takes input; it takes the size the agent works at.
  content::RenderWidgetHostView* view = web_contents()->GetRenderWidgetHostView();
  if (web_contents()->GetSize().IsEmpty()) {
    web_contents()->Resize(gfx::Rect(size));
  }
  if (view && view->GetViewBounds().size().IsEmpty()) {
    view->SetSize(size);
  }
  if (!rendering_) {
    // Renders as captured content does, without showing the page, keeping it
    // from counting as hidden or keeping the display awake. The size above
    // already holds, and a hidden capture takes none.
    rendering_ = web_contents()->IncrementCapturerCount(gfx::Size(), /*stay_hidden=*/true, /*stay_awake=*/false,
                                                        /*is_activity=*/false);
    // While the agent holds the page it takes the agent's keys as though it
    // had focus, as a page in a background tab would not otherwise, without
    // taking focus from the page the person uses.
    if (Attach()) {
      Send("Emulation.setFocusEmulationEnabled", base::DictValue().Set("enabled", true), base::DoNothing());
    }
  }
  return true;
}

void PageAgent::DispatchProtocolMessage(content::DevToolsAgentHost*, base::span<const uint8_t> message) {
  if (message.size() > kMaximumMessageBytes) {
    return;
  }
  auto parsed = base::JSONReader::ReadDict(base::as_string_view(message), base::JSON_PARSE_RFC);
  if (!parsed) {
    return;
  }
  if (std::optional<int> id = parsed->FindInt("id")) {
    auto found = replies_.find(*id);
    if (found == replies_.end()) {
      return;
    }
    Reply reply = std::move(found->second);
    replies_.erase(found);
    std::move(reply).Run(parsed->FindDict("error") ? nullptr : parsed->FindDict("result"));
    return;
  }
  const std::string* method = parsed->FindString("method");
  const base::DictValue* params = parsed->FindDict("params");
  if (method && params && observing_) {
    NetworkEvent(*method, *params);
  }
}

bool PageAgent::MayAttachToURL(const GURL& url, bool is_webui) {
  // DevTools asks again as the page navigates, and lets the agent go of a
  // page that left the web.
  return !is_webui && IsWebPage(url);
}

void PageAgent::AgentHostClosed(content::DevToolsAgentHost*) {
  attached_ = false;
  network_enabled_ = false;
  host_.reset();
  auto replies = std::move(replies_);
  for (auto& [id, reply] : replies) {
    std::move(reply).Run(nullptr);
  }
}

void PageAgent::OnDidAddMessageToConsole(content::RenderFrameHost*,
                                         blink::mojom::ConsoleMessageLevel level,
                                         const std::u16string& message,
                                         int32_t line,
                                         const std::u16string& source,
                                         const std::optional<std::u16string>&) {
  if (!observing_) {
    return;
  }
  std::optional<std::string> origin;
  if (!source.empty()) {
    origin = Clipped(base::UTF16ToUTF8(source));
  }
  console_.push_back(engine::PageConsoleMessage{.sequence = ++console_sequence_,
                                                .level = LevelOf(level),
                                                .text = Clipped(base::UTF16ToUTF8(message)),
                                                .source = std::move(origin),
                                                .line = line,
                                                .at = DateOf(base::Time::Now())});
  if (console_.size() > kMaximumConsoleMessages) {
    console_.pop_front();
    ++console_dropped_;
  }
}

void PageAgent::ResourceLoadComplete(content::RenderFrameHost*,
                                     const content::GlobalRequestID&,
                                     const GURL& original_url,
                                     const blink::mojom::ResourceLoadInfo& info) {
  if (!observing_) {
    return;
  }
  // DevTools reports requests as they go, except the first ones a new tab's
  // page makes: DevTools holds its messages to a renderer while it navigates,
  // so a fresh renderer starts the page before it has the session. Those
  // arrive here once done, without their headers.
  const std::string url = Clipped(info.final_url.spec());
  const std::string first = Clipped(original_url.spec());
  for (const auto& kept : network_) {
    if (kept.method == info.method && (kept.url == url || kept.url == first)) {
      return;
    }
  }
  const base::TimeTicks start = info.load_timing_info.request_start;
  const base::TimeDelta elapsed = start.is_null() ? base::TimeDelta() : base::TimeTicks::Now() - start;
  Keep(engine::PageNetworkRequest{
      .url = url,
      .method = info.method,
      .resource_type = ResourceTypeOf(info.request_destination),
      .status = info.http_status_code,
      .mime_type = info.mime_type.empty() ? std::nullopt : std::optional<std::string>(info.mime_type),
      .started = DateOf(base::Time::Now() - elapsed),
      .duration = elapsed.InMillisecondsF(),
      .bytes = static_cast<int64_t>(info.total_received_bytes.InBytes()),
      .failure = info.net_error == net::OK ? std::nullopt
                                           : std::optional<std::string>(net::ErrorToShortString(info.net_error))});
}

void PageAgent::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) {
  auto replies = std::move(replies_);
  for (auto& [id, reply] : replies) {
    std::move(reply).Run(nullptr);
  }
}

void PageAgent::WebContentsDestroyed() {
  rendering_.RunAndReset();
  Detach();
  content::WebContentsObserver::Observe(nullptr);
}

int64_t PageAgent::Keep(engine::PageNetworkRequest request) {
  request.sequence = ++network_sequence_;
  network_.push_back(std::move(request));
  if (network_.size() > kMaximumNetworkRequests) {
    const int64_t gone = network_.front().sequence;
    network_.pop_front();
    ++network_dropped_;
    std::erase_if(requests_, [gone](const auto& entry) { return entry.second == gone; });
  }
  return network_sequence_;
}

bool PageAgent::Attach() {
  if (attached_) {
    return true;
  }
  if (!web_contents() || !IsWebPage(web_contents()->GetPrimaryMainFrame()->GetLastCommittedURL())) {
    return false;
  }
  host_ = content::DevToolsAgentHost::GetOrCreateFor(web_contents());
  attached_ = host_ && host_->AttachClient(this);
  if (!attached_) {
    host_.reset();
    return false;
  }
  return true;
}

void PageAgent::Detach() {
  if (attached_ && host_) {
    attached_ = false;
    host_->DetachClient(this);
  }
  host_.reset();
  auto replies = std::move(replies_);
  for (auto& [id, reply] : replies) {
    std::move(reply).Run(nullptr);
  }
}

void PageAgent::Send(const char* method, base::DictValue params, Reply reply) {
  if (!attached_ || !host_) {
    std::move(reply).Run(nullptr);
    return;
  }
  const int id = ++sequence_;
  auto json =
      base::WriteJson(base::DictValue().Set("id", id).Set("method", method).Set("params", std::move(params)));
  if (!json) {
    std::move(reply).Run(nullptr);
    return;
  }
  replies_.emplace(id, std::move(reply));
  host_->DispatchProtocolMessage(this, base::as_byte_span(*json));
}

void PageAgent::Deliver(const engine::Guid& input, std::vector<std::pair<const char*, base::DictValue>> events) {
  if (events.empty()) {
    present_.Run(engine::PageInputDelivered{.page_id = page_, .input_id = input, .delivered = true, .trusted = true});
    return;
  }
  auto [method, params] = std::move(events.front());
  events.erase(events.begin());
  Send(method, std::move(params),
       base::BindOnce(
           [](base::WeakPtr<PageAgent> agent, engine::Guid input,
              std::vector<std::pair<const char*, base::DictValue>> rest, const base::DictValue* result) {
             if (!agent) {
               return;
             }
             if (!result) {
               agent->present_.Run(engine::PageInputDelivered{
                   .page_id = agent->page_, .input_id = input, .delivered = false, .trusted = true});
               return;
             }
             agent->Deliver(input, std::move(rest));
           },
           weak_factory_.GetWeakPtr(), input, std::move(events)));
}

void PageAgent::Answered(const engine::Guid& evaluation, base::Value value) {
  engine::PageScriptEvaluated answer{.page_id = page_, .evaluation_id = evaluation};
  if (value.is_dict()) {
    if (const std::string* error = value.GetDict().FindString("error")) {
      answer.error = Clipped(*error);
    } else {
      const base::Value* settled = value.GetDict().Find("value");
      answer.json = settled ? base::WriteJson(*settled) : base::WriteJson(base::Value());
    }
  }
  present_.Run(std::move(answer));
}

void PageAgent::NetworkEvent(const std::string& method, const base::DictValue& params) {
  const std::string* id = params.FindString("requestId");
  if (!id) {
    return;
  }
  auto kept = [&]() -> engine::PageNetworkRequest* {
    auto found = requests_.find(*id);
    if (found == requests_.end()) {
      return nullptr;
    }
    for (auto it = network_.rbegin(); it != network_.rend(); ++it) {
      if (it->sequence == found->second) {
        return &*it;
      }
    }
    return nullptr;
  };
  if (method == "Network.requestWillBeSent") {
    const base::DictValue* request = params.FindDict("request");
    if (!request) {
      return;
    }
    // A redirect answers the hop before it and starts a request of its own.
    if (const base::DictValue* redirect = params.FindDict("redirectResponse")) {
      if (auto* previous = kept()) {
        previous->status = redirect->FindInt("status").value_or(0);
        previous->response_headers = HeadersOf(redirect->FindDict("headers"));
        previous->duration =
            (base::Time::Now() - base::Time::FromSecondsSinceUnixEpoch(previous->started.seconds_since_2001 +
                                                                       kReferenceDateOffset))
                .InMillisecondsF();
      }
    }
    const std::string* url = request->FindString("url");
    const std::string* verb = request->FindString("method");
    const std::string* type = params.FindString("type");
    requests_[*id] = Keep(engine::PageNetworkRequest{.url = Clipped(url ? *url : std::string()),
                                                     .method = verb ? *verb : std::string(),
                                                     .resource_type = type ? *type : std::string(),
                                                     .request_headers = HeadersOf(request->FindDict("headers")),
                                                     .started = DateOf(base::Time::Now())});
    return;
  }
  auto* request = kept();
  if (!request) {
    return;
  }
  if (method == "Network.responseReceived") {
    if (const base::DictValue* response = params.FindDict("response")) {
      request->status = response->FindInt("status").value_or(0);
      if (const std::string* mime = response->FindString("mimeType")) {
        request->mime_type = *mime;
      }
      request->response_headers = HeadersOf(response->FindDict("headers"));
    }
    return;
  }
  const auto elapsed = base::Time::Now() -
                       base::Time::FromSecondsSinceUnixEpoch(request->started.seconds_since_2001 + kReferenceDateOffset);
  if (method == "Network.loadingFinished") {
    request->duration = elapsed.InMillisecondsF();
    request->bytes = static_cast<int64_t>(params.FindDouble("encodedDataLength").value_or(0));
    requests_.erase(*id);
  } else if (method == "Network.loadingFailed") {
    request->duration = elapsed.InMillisecondsF();
    const std::string* error = params.FindString("errorText");
    request->failure = Clipped(error ? *error : std::string("Failed"));
    requests_.erase(*id);
  }
}

}  // namespace crest
