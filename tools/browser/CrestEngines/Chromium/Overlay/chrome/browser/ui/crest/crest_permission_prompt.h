#ifndef CHROME_BROWSER_UI_CREST_CREST_PERMISSION_PROMPT_H_
#define CHROME_BROWSER_UI_CREST_CREST_PERMISSION_PROMPT_H_
#include "components/permissions/permission_prompt.h"
namespace crest {
std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* contents, permissions::PermissionPrompt::Delegate* delegate);

// Gives `delegate`'s requests the person's answer: whether it `grants` them,
// and whether the site's later requests follow it (`remembers`). Every Crest
// permission prompt answers through here. Chromium can raise the same requests
// again before the answer returns: once the site is allowed, a page's embedded
// camera, microphone or location control goes on to Chromium's own follow-up
// screens, such as the system's question or System Settings when the system
// has not allowed the device. Those requests already have their answer, and a
// second one ends the browser, so CreatePermissionPrompt shows them nothing
// and Chromium closes them itself.
void AnswerPermissionRequests(permissions::PermissionPrompt::Delegate& delegate, bool grants, bool remembers);
}
#endif
