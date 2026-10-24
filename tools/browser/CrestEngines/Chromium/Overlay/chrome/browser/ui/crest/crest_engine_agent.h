#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_AGENT_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_AGENT_H_

#include <cstdint>
#include <deque>
#include <map>
#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "content/public/browser/web_contents_observer.h"

namespace content {
class DevToolsAgentHost;
}

namespace crest {

// What an agent the person allowed does in one page. Scripts run in an
// isolated world of the agent's own, apart from Crest's content bridges and
// the page, or in the page's own world. Input, scripts in the page's world and
// network activity go through a fixed set of in-process DevTools commands for
// exactly this page; it opens no debugging socket and offers no general
// protocol entry point. Console messages come from the page itself. The page
// keeps rendering while an agent holds it, though no window shows it.
class PageAgent final : public content::WebContentsObserver, public content::DevToolsAgentHostClient {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;

  // The most console messages and network requests the page keeps.
  static constexpr size_t kMaximumConsoleMessages = 500;
  static constexpr size_t kMaximumNetworkRequests = 500;
  // The longest console message text and header value kept.
  static constexpr size_t kMaximumText = 4096;

  PageAgent(content::WebContents* contents, const engine::Guid& page, Present present);
  PageAgent(const PageAgent&) = delete;
  PageAgent& operator=(const PageAgent&) = delete;
  ~PageAgent() override;

  bool Evaluate(const engine::Guid& evaluation, const std::string& source, engine::PageScriptWorld world);
  bool Click(const engine::Guid& input,
             const engine::PagePoint& point,
             engine::PointerButton button,
             int count,
             engine::KeyModifiers modifiers);
  bool Hover(const engine::Guid& input, const engine::PagePoint& point);
  bool Scroll(const engine::Guid& input, const engine::PagePoint& point, double delta_x, double delta_y);
  bool Type(const engine::Guid& input, const std::string& text);
  bool PressKey(const engine::Guid& input, const engine::PageKey& key, engine::KeyModifiers modifiers);
  bool ObserveActivity(bool observing);
  engine::PageConsoleLog Console(int64_t after) const;
  engine::PageNetworkLog Network(int64_t after) const;
  bool HoldRendering(bool held, double width, double height);

 private:
  // What a DevTools command answered: its result, or nothing when it failed.
  using Reply = base::OnceCallback<void(const base::DictValue* result)>;

  // content::DevToolsAgentHostClient:
  void DispatchProtocolMessage(content::DevToolsAgentHost* host, base::span<const uint8_t> message) override;
  void AgentHostClosed(content::DevToolsAgentHost* host) override;
  bool MayAttachToURL(const GURL& url, bool is_webui) override;

  // content::WebContentsObserver:
  void OnDidAddMessageToConsole(content::RenderFrameHost* source_frame,
                                blink::mojom::ConsoleMessageLevel level,
                                const std::u16string& message,
                                int32_t line,
                                const std::u16string& source,
                                const std::optional<std::u16string>& stack_trace) override;
  void ResourceLoadComplete(content::RenderFrameHost* render_frame_host,
                            const content::GlobalRequestID& request_id,
                            const GURL& original_url,
                            const blink::mojom::ResourceLoadInfo& info) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) override;
  void WebContentsDestroyed() override;

  bool Attach();
  // Keeps `request` as the newest, numbering it and dropping the oldest past
  // the bound; answers its number.
  int64_t Keep(engine::PageNetworkRequest request);
  void Detach();
  void Send(const char* method, base::DictValue params, Reply reply);
  // Sends `events` in order and presents whether all of them reached the page.
  void Deliver(const engine::Guid& input, std::vector<std::pair<const char*, base::DictValue>> events);
  void Answered(const engine::Guid& evaluation, base::Value value);
  void NetworkEvent(const std::string& method, const base::DictValue& params);

  const engine::Guid page_;
  const Present present_;
  scoped_refptr<content::DevToolsAgentHost> host_;
  bool attached_ = false;
  int sequence_ = 0;
  std::map<int, Reply> replies_;

  bool observing_ = false;
  bool network_enabled_ = false;
  std::deque<engine::PageConsoleMessage> console_;
  int64_t console_sequence_ = 0;
  int64_t console_dropped_ = 0;
  std::deque<engine::PageNetworkRequest> network_;
  // The kept request each DevTools request identity is, by its sequence.
  std::map<std::string, int64_t> requests_;
  int64_t network_sequence_ = 0;
  int64_t network_dropped_ = 0;

  base::ScopedClosureRunner rendering_;
  base::WeakPtrFactory<PageAgent> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_AGENT_H_
