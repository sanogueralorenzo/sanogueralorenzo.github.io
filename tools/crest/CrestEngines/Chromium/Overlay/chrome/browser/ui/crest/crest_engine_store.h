#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_STORE_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_STORE_H_

#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"

class GURL;

namespace content {
class RenderFrameHost;
class WebContents;
}

namespace crest {

// A Chrome Web Store listing in a page. The store's own Add to Chrome button
// is inert in this baseline, so Crest owns that affordance: a script in an
// isolated world on the store's own host relabels the button and asks Crest
// to run its install review. The script is not a general scripting entry
// point — it is injected only into the store's own main frame in a regular
// profile, where a Space's persistent extensions live, and the only request
// it can make is for the extension the page's own URL names.
class PageStore final {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;

  PageStore(content::WebContents* contents, const engine::Guid& page, Present present);
  PageStore(const PageStore&) = delete;
  PageStore& operator=(const PageStore&) = delete;
  ~PageStore();

  // The main frame's document can take the listing's script.
  void DocumentAvailable();
  // A move within the listing's document committed at `url`. True when it was
  // the listing's request, written into its own fragment, which is Crest's
  // message rather than a page anyone records.
  bool Committed(const GURL& url);
  // The review the listing's request began finished, or never started: its
  // button goes back to what the engine's registry says.
  void RequestFinished();
  // Restates the listing's button from the engine's registry.
  void Refresh();

 private:
  content::RenderFrameHost* Frame() const;
  void Run(const std::string& script);
  bool Consume(const GURL& url);

  const raw_ptr<content::WebContents> contents_;
  const engine::Guid page_;
  const Present present_;
  // A request from the listing is still with Crest.
  bool request_open_ = false;
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_STORE_H_
