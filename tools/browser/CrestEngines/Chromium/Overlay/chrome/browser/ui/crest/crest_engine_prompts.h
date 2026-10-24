#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_PROMPTS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_PROMPTS_H_

#include <functional>
#include <map>
#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "components/permissions/permission_prompt.h"
#include "content/public/browser/javascript_dialog_manager.h"

class GURL;
class Profile;

namespace content {
class WebContents;
}

namespace net {
class AuthChallengeInfo;
}

namespace crest {

// What an engine page, or the engine itself, asks the person. Each question is
// reported to the core, which answers a site's permission request from its
// Space's choices or asks the person, and settles it with a command.
class EnginePrompts final : public content::JavaScriptDialogManager {
 public:
  using Report = base::RepeatingCallback<void(engine::EngineEvent)>;
  using AuthenticationReply = std::function<void(bool, const std::u16string&, const std::u16string&)>;
  using InstallReply = base::OnceCallback<void(bool accepted, bool withholds_site_access)>;
  using ShareReply = base::OnceCallback<void(bool proceeds)>;

  explicit EnginePrompts(Report report);
  EnginePrompts(const EnginePrompts&) = delete;
  EnginePrompts& operator=(const EnginePrompts&) = delete;
  ~EnginePrompts() override;

  bool Settle(const engine::SettleScriptDialog& settlement);

  // An HTTP challenge for `page`'s load, the `previous_failures`th for the
  // same server and realm.
  void Authenticate(const engine::Guid& page,
                    const net::AuthChallengeInfo& challenge,
                    int previous_failures,
                    AuthenticationReply reply);
  bool Settle(const engine::SettleAuthentication& settlement);

  // A permission request Crest's record covers, or nullptr for any other.
  std::unique_ptr<permissions::PermissionPrompt> Prompt(const engine::Guid& page,
                                                         permissions::PermissionPrompt::Delegate* delegate);
  bool Settle(const engine::SettlePermission& settlement);

  // A document at `origin` in `page`, whose top-level document is at
  // `top_level_origin`, asked to share the screen. The core answers from the
  // page's Space: `reply` hears whether the request goes on to the system's
  // own sharing picker, which asks the person, or is refused. Answers the
  // question's identity, for `WithdrawShare` when the request ends first.
  engine::Guid AskToShareScreen(const engine::Guid& page,
                                const GURL& origin,
                                const GURL& top_level_origin,
                                ShareReply reply);
  void WithdrawShare(const engine::Guid& id);

  // Whether to install the extension an install the window `window` started
  // verified; `reply` hears the answer, or a decline when nobody can give one.
  void AskToInstall(const engine::Guid& window, engine::ExtensionInstallQuestion question, InstallReply reply);
  bool Settle(const engine::SettleExtensionInstall& settlement);

  // The page closed: what it asked goes unanswered.
  void Forget(const engine::Guid& page);

  // content::JavaScriptDialogManager:
  void RunJavaScriptDialog(content::WebContents* contents,
                           content::RenderFrameHost* frame,
                           content::JavaScriptDialogType type,
                           const std::u16string& message,
                           const std::u16string& default_text,
                           DialogClosedCallback callback,
                           bool* did_suppress_message) override;
  void RunBeforeUnloadDialog(content::WebContents* contents,
                             content::RenderFrameHost* frame,
                             bool is_reload,
                             DialogClosedCallback callback) override;
  bool HandleJavaScriptDialog(content::WebContents* contents,
                              bool accept,
                              const std::u16string* prompt_override) override;
  void CancelDialogs(content::WebContents* contents, bool reset_state) override;

 private:
  class PermissionPrompt;
  friend class PermissionPrompt;
  struct Dialog {
    engine::Guid page;
    engine::Guid id;
    DialogClosedCallback callback;
  };
  struct Challenge {
    engine::Guid page;
    AuthenticationReply reply;
  };
  struct Share {
    engine::Guid page;
    ShareReply reply;
  };

  void Open(content::WebContents* contents,
            content::RenderFrameHost* frame,
            engine::JavaScriptDialogKind kind,
            const std::u16string& message,
            const std::u16string& default_text,
            DialogClosedCallback callback);
  // Closes the dialog `id` in `contents`. One the core did not settle is
  // withdrawn: the engine closed it, or a new one replaced it.
  void Close(content::WebContents* contents,
             const engine::Guid& id,
             bool accepted,
             const std::u16string& input,
             bool settled);
  // A permission prompt the engine let go of before the core answered it.
  void Withdrawn(const engine::Guid& id);

  const Report report_;
  std::map<content::WebContents*, Dialog> dialogs_;
  std::map<engine::Guid, Challenge> challenges_;
  std::map<engine::Guid, base::WeakPtr<PermissionPrompt>> permissions_;
  std::map<engine::Guid, InstallReply> installs_;
  std::map<engine::Guid, Share> shares_;
  base::WeakPtrFactory<EnginePrompts> weak_factory_{this};
};

// A fresh identity for something the binding asks the platform.
engine::Guid RandomGuid();

// Removes one site's cookies, storage and cache from `profile`, then answers.
void ClearSiteData(Profile* profile, const GURL& url, base::OnceCallback<void(bool)> done);

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_PROMPTS_H_
