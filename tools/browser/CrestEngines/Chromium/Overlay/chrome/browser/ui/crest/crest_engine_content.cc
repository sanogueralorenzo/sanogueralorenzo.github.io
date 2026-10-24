#include "chrome/browser/ui/crest/crest_engine_content.h"

#include <optional>

#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/ui/crest/crest_chrome_hooks.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "url/origin.h"

namespace crest {

namespace {

// The world's own setup, which answers the document's nonce, or null when the
// world was already set up in this document.
constexpr char kBridgeShim[] = R"JS(
(() => {
  if (globalThis.__crestBridge) return null;
  const doc = Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const queue = [];
  let waiter = null;
  const flush = () => {
    if (!waiter || !queue.length) return;
    const resolve = waiter;
    waiter = null;
    resolve({ doc, messages: queue.splice(0) });
  };
  const handlers = new Map();
  const handler = (name) => {
    if (!handlers.has(name)) {
      handlers.set(name, Object.freeze({
        postMessage(body) {
          queue.push({ handler: name, body: JSON.parse(JSON.stringify(body ?? null)) });
          flush();
        },
      }));
    }
    return handlers.get(name);
  };
  globalThis.webkit = Object.freeze({
    messageHandlers: new Proxy({}, { get: (_, name) => typeof name === "string" ? handler(name) : undefined }),
  });
  globalThis.__crestBridge = Object.freeze({
    doc,
    next() { return new Promise((resolve) => { waiter = resolve; flush(); }); },
  });
  return doc;
})();
)JS";

// A frame's document as the platform names it: the frame's process and
// routing identity, and the document's nonce.
std::string FrameIdentity(content::RenderFrameHost* frame, const std::string& document) {
  const auto id = frame->GetGlobalId();
  return base::NumberToString(id.child_id.GetUnsafeValue()) + ":" + base::NumberToString(id.frame_routing_id) + ":" +
         document;
}

}  // namespace

PageContent::PageContent(content::WebContents* contents, const engine::Guid& page, Present present)
    : contents_(contents), page_(page), present_(std::move(present)) {}

PageContent::~PageContent() = default;

void PageContent::Add(std::string source, bool main_frame_only) {
  scripts_.emplace_back(std::move(source), main_frame_only);
}

void PageContent::DocumentAvailable(content::RenderFrameHost* frame) {
  if (scripts_.empty() || !frame || !frame->IsRenderFrameLive()) {
    return;
  }
  const bool main = frame->IsInPrimaryMainFrame();
  if (!main && frame->GetMainFrame() != contents_->GetPrimaryMainFrame()) {
    return;
  }
  std::string script = "(() => { const doc = " + std::string(kBridgeShim) + " if (doc === null) return null;\n";
  for (const auto& [source, main_frame_only] : scripts_) {
    if (main_frame_only && !main) {
      continue;
    }
    script += "try {\n" + source + "\n} catch (_) {}\n";
  }
  script += "return doc; })()";
  frame->ExecuteJavaScriptInIsolatedWorld(
      base::UTF8ToUTF16(script),
      base::BindOnce(
          [](base::WeakPtr<PageContent> content, content::GlobalRenderFrameHostId frame, base::Value document) {
            if (content && document.is_string()) {
              content->Poll(frame, document.GetString());
            }
          },
          weak_factory_.GetWeakPtr(), frame->GetGlobalId()),
      kContentWorldID);
}

void PageContent::Poll(content::GlobalRenderFrameHostId id, const std::string& document) {
  auto* frame = content::RenderFrameHost::FromID(id);
  if (!frame || !frame->IsRenderFrameLive() || content::WebContents::FromRenderFrameHost(frame) != contents_) {
    return;
  }
  frame->ExecuteJavaScriptInIsolatedWorld(
      u"globalThis.__crestBridge?.next()",
      base::BindOnce(&PageContent::Deliver, weak_factory_.GetWeakPtr(), id, document), kContentWorldID);
}

// An empty answer means the document went away or its world was torn down;
// the next document arms a poll of its own.
void PageContent::Deliver(content::GlobalRenderFrameHostId id, const std::string& document, base::Value batch) {
  if (!batch.is_dict()) {
    return;
  }
  const auto* batch_document = batch.GetDict().FindString("doc");
  const auto* messages = batch.GetDict().FindList("messages");
  auto* frame = content::RenderFrameHost::FromID(id);
  if (!batch_document || *batch_document != document || !messages || !frame) {
    return;
  }
  const url::Origin origin = frame->GetLastCommittedOrigin();
  const engine::ContentFrame source{.id = FrameIdentity(frame, document),
                                    .is_main_frame = frame->IsInPrimaryMainFrame(),
                                    .protocol = origin.scheme(),
                                    .host = origin.host(),
                                    .port = origin.port()};
  for (const auto& message : *messages) {
    if (!message.is_dict()) {
      continue;
    }
    const auto* handler = message.GetDict().FindString("handler");
    const auto* body = message.GetDict().Find("body");
    auto json = body ? base::WriteJson(*body) : std::nullopt;
    if (!handler || !json) {
      continue;
    }
    present_.Run(engine::ContentMessagePosted{.page_id = page_, .handler = *handler, .body = *json, .frame = source});
  }
  Poll(id, document);
}

bool PageContent::Evaluate(const engine::Guid& evaluation, const std::string& source, const std::string& frame_id) {
  content::RenderFrameHost* frame = nullptr;
  std::string script;
  // "main" addresses the primary main frame's current document directly.
  if (frame_id == "main") {
    frame = contents_->GetPrimaryMainFrame();
    script = "(async () => {\n" + source + "\n})()";
  } else {
    auto parts = base::SplitString(frame_id, ":", base::KEEP_WHITESPACE, base::SPLIT_WANT_ALL);
    int child = 0;
    int routing = 0;
    if (parts.size() != 3 || !base::StringToInt(parts[0], &child) || !base::StringToInt(parts[1], &routing)) {
      return false;
    }
    frame = content::RenderFrameHost::FromID(content::GlobalRenderFrameHostId(child, routing));
    if (frame && content::WebContents::FromRenderFrameHost(frame) != contents_) {
      frame = nullptr;
    }
    auto document = base::WriteJson(base::Value(parts[2]));
    // The source runs only in the document it was addressed to.
    script = "(async () => { if (globalThis.__crestBridge?.doc !== " + document.value_or("null") +
             ") return null;\n" + source + "\n})()";
  }
  if (!frame || !frame->IsRenderFrameLive()) {
    return false;
  }
  // A document torn down mid-evaluation drops its reply; the platform still
  // hears an answer.
  frame->ExecuteJavaScriptInIsolatedWorld(
      base::UTF8ToUTF16(script),
      mojo::WrapCallbackWithDefaultInvokeIfNotRun(
          base::BindOnce(&PageContent::Answer, weak_factory_.GetWeakPtr(), evaluation), base::Value()),
      kContentWorldID);
  return true;
}

void PageContent::Answer(const engine::Guid& evaluation, base::Value value) {
  std::optional<std::string> json;
  if (!value.is_none()) {
    json = base::WriteJson(value);
  }
  present_.Run(engine::ContentScriptEvaluated{.page_id = page_, .evaluation_id = evaluation, .json = json});
}

}  // namespace crest
