#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_CONTENT_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_CONTENT_H_

#include <string>
#include <utility>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "content/public/browser/global_routing_id.h"

namespace content {
class RenderFrameHost;
class WebContents;
}

namespace crest {

// Crest's content bridges in a page. They run in one isolated world of their
// own, as they do in WebKit's named content worlds: the page cannot see or
// call them. The bridges are written against WebKit's
// `webkit.messageHandlers.<name>.postMessage`, so the world defines that
// object itself and the bridge scripts run unchanged.
//
// A message leaves the world through a long poll: one `__crestBridge.next()`
// evaluation stays outstanding per document, the engine resolves it when a
// bridge posts (the patched evaluator awaits promises in this world only),
// and the next batch is asked for at once. Every batch and every evaluation
// names the document by a nonce the world minted, so nothing from a previous
// document is attributed to, or runs in, the next one.
class PageContent final {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;

  PageContent(content::WebContents* contents, const engine::Guid& page, Present present);
  PageContent(const PageContent&) = delete;
  PageContent& operator=(const PageContent&) = delete;
  ~PageContent();

  // Runs `source` in every document the page loads from now on, or in its
  // main frame's only.
  void Add(std::string source, bool main_frame_only);
  // `frame`'s document can take the bridges.
  void DocumentAvailable(content::RenderFrameHost* frame);
  // Runs `source` once in the document `frame` names and presents what it
  // answered with `evaluation`. False when the frame is gone.
  bool Evaluate(const engine::Guid& evaluation, const std::string& source, const std::string& frame);

 private:
  void Poll(content::GlobalRenderFrameHostId frame, const std::string& document);
  void Deliver(content::GlobalRenderFrameHostId frame, const std::string& document, base::Value batch);
  void Answer(const engine::Guid& evaluation, base::Value value);

  const raw_ptr<content::WebContents> contents_;
  const engine::Guid page_;
  const Present present_;
  // The bridge sources, in install order, and whether each is limited to the
  // main frame.
  std::vector<std::pair<std::string, bool>> scripts_;
  base::WeakPtrFactory<PageContent> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_CONTENT_H_
