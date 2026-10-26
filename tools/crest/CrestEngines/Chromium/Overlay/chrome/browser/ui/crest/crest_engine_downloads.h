#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_DOWNLOADS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_DOWNLOADS_H_

#include <map>
#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ref.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "chrome/browser/download/download_confirmation_reason.h"
#include "chrome/browser/download/download_target_determiner_delegate.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"

namespace download {
class DownloadItem;
}

namespace crest {

class EngineProfiles;

// The engine's downloads in Crest's profiles, reported to the core, which
// records each one in its ledger and answers where its file goes. The engine
// still decides what is safe; the person may keep a download it only warned
// about, never one it blocked.
class EngineDownloads final {
 public:
  using Report = base::RepeatingCallback<void(engine::EngineEvent)>;
  // The page that shows a download's WebContents, if one does.
  using PageFor = base::RepeatingCallback<std::optional<engine::Guid>(
      download::DownloadItem*)>;

  EngineDownloads(EngineProfiles& profiles, Report report, PageFor page_for);
  EngineDownloads(const EngineDownloads&) = delete;
  EngineDownloads& operator=(const EngineDownloads&) = delete;
  ~EngineDownloads();

  bool Owns(download::DownloadItem* item) const;
  void Changed(download::DownloadItem* item);
  void ChooseDestination(
      download::DownloadItem* item,
      const base::FilePath& suggested_path,
      DownloadConfirmationReason reason,
      DownloadTargetDeterminerDelegate::ConfirmationCallback callback);

  bool Settle(const engine::SettleDownloadDestination& settlement);
  bool Cancel(const engine::CancelEngineDownload& command);
  bool Pause(const engine::PauseEngineDownload& command);
  bool Resume(const engine::ResumeEngineDownload& command);
  bool Remove(const engine::RemoveEngineDownload& command);
  bool Approve(const engine::ApproveEngineDownload& command);

 private:
  struct Destination {
    std::string profile;
    std::string download;
    DownloadTargetDeterminerDelegate::ConfirmationCallback callback;
  };

  std::optional<engine::EngineDownload> Describe(
      download::DownloadItem* item) const;
  download::DownloadItem* Find(const std::string& profile,
                               const std::string& download) const;
  void CancelIfBlocked(std::string profile, std::string download);

  const raw_ref<EngineProfiles> profiles_;
  const Report report_;
  const PageFor page_for_;
  // A download that started before this launch is one the engine restored.
  const base::Time started_at_ = base::Time::Now();
  std::map<engine::Guid, Destination> destinations_;
  base::WeakPtrFactory<EngineDownloads> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_DOWNLOADS_H_
