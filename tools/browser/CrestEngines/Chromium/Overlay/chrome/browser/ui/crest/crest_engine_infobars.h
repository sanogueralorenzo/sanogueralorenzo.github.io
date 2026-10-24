#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_INFOBARS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_INFOBARS_H_

#include <map>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "components/infobars/core/infobar_manager.h"

namespace content {
class WebContents;
}

namespace crest {

// The engine's bars over a page — tab sharing, `chrome.debugger`, extension
// notices — which have no Views container in this build. A bar that asks the
// person to confirm something is presented for the platform to show over the
// page; the rest carry no text of their own and stay silent.
class PageInfoBars final : public infobars::InfoBarManager::Observer {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;

  PageInfoBars(content::WebContents* contents, const engine::Guid& page, Present present);
  PageInfoBars(const PageInfoBars&) = delete;
  PageInfoBars& operator=(const PageInfoBars&) = delete;
  ~PageInfoBars() override;

  // Presents every bar the page shows again, for a platform that comes to
  // the page after they appeared.
  void PresentAll();
  // Runs the person's answer to the bar `id` names.
  bool Answer(int id, engine::InfoBarAnswer answer);

  // infobars::InfoBarManager::Observer:
  void OnInfoBarAdded(infobars::InfoBar* bar) override;
  void OnInfoBarRemoved(infobars::InfoBar* bar, bool animate) override;
  void OnInfoBarReplaced(infobars::InfoBar* old_bar, infobars::InfoBar* new_bar) override;
  void OnManagerWillBeDestroyed(infobars::InfoBarManager* manager) override;

 private:
  void Add(infobars::InfoBar* bar);
  void Show(int id, infobars::InfoBar* bar);

  const engine::Guid page_;
  const Present present_;
  raw_ptr<infobars::InfoBarManager> manager_ = nullptr;
  std::map<int, raw_ptr<infobars::InfoBar>> bars_;
  int next_id_ = 0;
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_INFOBARS_H_
