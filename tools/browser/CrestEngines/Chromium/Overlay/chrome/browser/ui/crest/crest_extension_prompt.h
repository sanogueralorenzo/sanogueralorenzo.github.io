#ifndef CHROME_BROWSER_UI_CREST_CREST_EXTENSION_PROMPT_H_
#define CHROME_BROWSER_UI_CREST_CREST_EXTENSION_PROMPT_H_

#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"

namespace crest {
void ShowExtensionPrompt(
    std::unique_ptr<ExtensionInstallPromptShowParams> params,
    ExtensionInstallPrompt::DoneCallback callback,
    std::unique_ptr<extensions::InstallPromptData> prompt);
}

#endif
