#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_INSPECTOR_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_INSPECTOR_H_

#include <optional>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"

namespace content {
class WebContents;
}

namespace crest {

// The engine's inspector on a page. Crest is a single-window browser, so a
// docked inspector belongs inside the card of the page it inspects rather
// than in a window of its own. This build never creates Chrome's Views
// contents container, so its `DevtoolsUIController` — which normally hosts a
// docked frontend — does not exist; this takes its place for a page's
// inspector. The platform's shell hosts the frontend's view; this decides
// when there is one to host and where it goes. Undocking hands the frontend
// back to the engine, which opens the window the person asked for.
class PageInspector final {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;
  // The shell hosts the docked frontend's view over the page, or none.
  using Dock = base::RepeatingCallback<void(content::WebContents* frontend)>;

  PageInspector(content::WebContents* inspected, const engine::Guid& page, Present present, Dock dock);
  PageInspector(const PageInspector&) = delete;
  PageInspector& operator=(const PageInspector&) = delete;
  ~PageInspector();

  bool Open(std::optional<engine::InspectorPanel> panel);
  bool Close();
  bool IsOpen() const;
  engine::InspectorLayout Layout(double width, double height) const;

  // The engine offered, relaid or withdrew the docked frontend.
  void Update();
  // The inspector is going away by any route: its own close button, an
  // undocked window closing, or the inspected page closing.
  void Closing();

 private:
  const raw_ptr<content::WebContents> inspected_;
  const engine::Guid page_;
  const Present present_;
  const Dock dock_;
  // The frontend docked in the card, and where the page goes over it.
  base::WeakPtr<content::WebContents> docked_;
  DevToolsContentsResizingStrategy strategy_;
  // A frontend handed back to the engine's own window. Its renderer is
  // switched to Views drawing there for good, so docking it again replaces it
  // rather than hosts it.
  base::WeakPtr<content::WebContents> undocked_;
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_INSPECTOR_H_
