#ifndef CHROME_BROWSER_UI_CREST_CREST_DOWNLOAD_HOOKS_H_
#define CHROME_BROWSER_UI_CREST_CREST_DOWNLOAD_HOOKS_H_

#include "chrome/browser/download/download_confirmation_reason.h"
#include "chrome/browser/download/download_target_determiner_delegate.h"

namespace download { class DownloadItem; }
namespace crest {
bool OwnsDownload(download::DownloadItem* item);
void PublishDownload(download::DownloadItem* item);
void ChooseDownloadDestination(download::DownloadItem* item,
    const base::FilePath& suggested_path, DownloadConfirmationReason reason,
    DownloadTargetDeterminerDelegate::ConfirmationCallback callback);
}
#endif
