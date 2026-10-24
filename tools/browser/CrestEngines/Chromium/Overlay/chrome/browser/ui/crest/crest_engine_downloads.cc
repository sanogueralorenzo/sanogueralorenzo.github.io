#include "chrome/browser/ui/crest/crest_engine_downloads.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/download/download_confirmation_result.h"
#include "chrome/browser/download/download_item_model.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_profiles.h"
#include "chrome/browser/ui/crest/crest_engine_prompts.h"
#include "components/download/public/common/download_interrupt_reasons.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/download_manager.h"
#include "net/base/mime_util.h"
#include "ui/shell_dialogs/selected_file_info.h"

namespace crest {

namespace {

// Seconds from the Unix epoch to the wire's reference date, 2001-01-01.
constexpr double kReferenceDateOffset = 978307200;

// What the platform knows about a file before the core judges its risk: its
// name, the type its server declared, and whether that type matches the one
// its name implies (unknown when either type is). Which types run code is the
// core's to say.
engine::DownloadRiskFacts RiskFacts(download::DownloadItem* item,
                                    const base::FilePath& path) {
  const std::string name = path.BaseName().AsUTF8Unsafe();
  engine::DownloadRiskFacts facts{.suggested_filename = name,
                                  .sanitized_filename = name};
  const std::string declared = item->GetMimeType();
  if (declared.empty()) {
    return facts;
  }
  facts.mime_type = declared;
  std::string implied;
  if (net::GetMimeTypeFromFile(path, &implied)) {
    facts.types_related = net::MatchesMimeType(implied, declared) ||
                          net::MatchesMimeType(declared, implied);
  }
  return facts;
}

// Only a warning the person may override enters the approval path. A policy
// block or known malware stays blocked; a pending scan stays the engine's.
std::optional<engine::EngineDownloadWarning> WarningFor(
    download::DownloadItem* item,
    bool* blocked) {
  *blocked = false;
  if (item->IsInsecure()) {
    *blocked =
        item->GetInsecureDownloadStatus() != download::DownloadItem::WARN;
    return *blocked ? engine::EngineDownloadWarning::kInsecureBlocked
                    : engine::EngineDownloadWarning::kInsecureConnection;
  }
  if (!item->IsDangerous()) {
    return std::nullopt;
  }
  switch (item->GetDangerType()) {
    case download::DOWNLOAD_DANGER_TYPE_DANGEROUS_FILE:
      return engine::EngineDownloadWarning::kDangerousFile;
    case download::DOWNLOAD_DANGER_TYPE_UNCOMMON_CONTENT:
      return engine::EngineDownloadWarning::kUncommonContent;
    case download::DOWNLOAD_DANGER_TYPE_POTENTIALLY_UNWANTED:
      return engine::EngineDownloadWarning::kPotentiallyUnwanted;
    case download::DOWNLOAD_DANGER_TYPE_ASYNC_SCANNING:
    case download::DOWNLOAD_DANGER_TYPE_ASYNC_LOCAL_PASSWORD_SCANNING:
    case download::DOWNLOAD_DANGER_TYPE_MAYBE_DANGEROUS_CONTENT:
      return std::nullopt;
    default:
      *blocked = true;
      return engine::EngineDownloadWarning::kPolicyBlocked;
  }
}

// What stopped a download, as Crest names it.
engine::EngineDownloadInterruption InterruptionOf(
    download::DownloadInterruptReason reason) {
  switch (reason) {
    case download::DOWNLOAD_INTERRUPT_REASON_NETWORK_FAILED:
    case download::DOWNLOAD_INTERRUPT_REASON_NETWORK_TIMEOUT:
    case download::DOWNLOAD_INTERRUPT_REASON_NETWORK_DISCONNECTED:
    case download::DOWNLOAD_INTERRUPT_REASON_NETWORK_SERVER_DOWN:
    case download::DOWNLOAD_INTERRUPT_REASON_NETWORK_INVALID_REQUEST:
      return engine::EngineDownloadInterruption::kNetwork;
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_FAILED:
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_NO_RANGE:
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_BAD_CONTENT:
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_UNAUTHORIZED:
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_CERT_PROBLEM:
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_FORBIDDEN:
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_UNREACHABLE:
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_CONTENT_LENGTH_MISMATCH:
    case download::DOWNLOAD_INTERRUPT_REASON_SERVER_CROSS_ORIGIN_REDIRECT:
      return engine::EngineDownloadInterruption::kServer;
    case download::DOWNLOAD_INTERRUPT_REASON_FILE_NO_SPACE:
      return engine::EngineDownloadInterruption::kNoSpace;
    case download::DOWNLOAD_INTERRUPT_REASON_FILE_FAILED:
    case download::DOWNLOAD_INTERRUPT_REASON_FILE_ACCESS_DENIED:
    case download::DOWNLOAD_INTERRUPT_REASON_FILE_NAME_TOO_LONG:
    case download::DOWNLOAD_INTERRUPT_REASON_FILE_TOO_LARGE:
    case download::DOWNLOAD_INTERRUPT_REASON_FILE_TRANSIENT_ERROR:
    case download::DOWNLOAD_INTERRUPT_REASON_FILE_SAME_AS_SOURCE:
      return engine::EngineDownloadInterruption::kFileAccess;
    default:
      return engine::EngineDownloadInterruption::kOther;
  }
}

// The warning a person's approval answers, so a download whose verdict
// changed since is never kept on an old answer.
std::string ApprovalToken(download::DownloadItem* item) {
  return base::NumberToString(static_cast<int>(item->GetDangerType())) + ":" +
         base::NumberToString(
             static_cast<int>(item->GetInsecureDownloadStatus()));
}

}  // namespace

EngineDownloads::EngineDownloads(EngineProfiles& profiles,
                                 Report report,
                                 PageFor page_for)
    : profiles_(profiles),
      report_(std::move(report)),
      page_for_(std::move(page_for)) {}

EngineDownloads::~EngineDownloads() = default;

// An extension package the engine installs itself, and a transient download,
// stay the engine's.
bool EngineDownloads::Owns(download::DownloadItem* item) const {
  return !item->IsTransient() &&
         item->GetMimeType() != "application/x-chrome-extension" &&
         !profiles_->IdFor(content::DownloadItemUtils::GetBrowserContext(item))
              .empty();
}

std::optional<engine::EngineDownload> EngineDownloads::Describe(
    download::DownloadItem* item) const {
  const auto profile = ParseGuid(
      profiles_->IdFor(content::DownloadItemUtils::GetBrowserContext(item)));
  if (!profile) {
    return std::nullopt;
  }
  engine::EngineDownload download{
      .download_id = item->GetGuid(),
      .profile_id = *profile,
      .source_page_id = page_for_.Run(item),
      .filename = item->GetFileNameToReportUser().AsUTF8Unsafe(),
      .received = item->GetReceivedBytes(),
      .total = item->GetTotalBytes(),
      .started_at =
          engine::Date{.seconds_since_2001 =
                           item->GetStartTime().InSecondsFSinceUnixEpoch() -
                           kReferenceDateOffset},
      .restored = item->GetStartTime() < started_at_,
      .paused = item->IsPaused(),
      .state = engine::EngineDownloadState::kPreparing,
      .approval_token = ApprovalToken(item),
  };
  if (!item->GetTargetFilePath().empty()) {
    download.path = item->GetTargetFilePath().AsUTF8Unsafe();
  }
  switch (item->GetState()) {
    case download::DownloadItem::COMPLETE:
      download.state = engine::EngineDownloadState::kFinished;
      break;
    case download::DownloadItem::CANCELLED:
      download.state = engine::EngineDownloadState::kCanceled;
      break;
    case download::DownloadItem::INTERRUPTED:
      download.state = engine::EngineDownloadState::kFailed;
      download.interruption = InterruptionOf(item->GetLastReason());
      download.failure_detail =
          base::UTF16ToUTF8(DownloadItemModel(item).GetInterruptDescription());
      break;
    case download::DownloadItem::IN_PROGRESS: {
      download.state = item->GetTargetFilePath().empty()
                           ? engine::EngineDownloadState::kPreparing
                           : engine::EngineDownloadState::kDownloading;
      bool blocked = false;
      if (auto warning = WarningFor(item, &blocked)) {
        download.state = blocked
                             ? engine::EngineDownloadState::kFailed
                             : engine::EngineDownloadState::kAwaitingApproval;
        download.warning = warning;
      }
      break;
    }
    default:
      break;
  }
  // Recovery never substitutes for approval of an unsafe file. The engine
  // owns whether a request can continue, or must restart from its saved data.
  bool blocked = false;
  if (!WarningFor(item, &blocked)) {
    download.can_pause =
        item->GetState() == download::DownloadItem::IN_PROGRESS &&
        !item->IsPaused();
    download.can_resume = item->CanResume();
  }
  return download;
}

// The engine's notification is not the place to change the download, so a
// blocked one is canceled once the report is sent.
void EngineDownloads::Changed(download::DownloadItem* item) {
  auto download = Describe(item);
  if (!download) {
    return;
  }
  const bool failed = download->state == engine::EngineDownloadState::kFailed;
  std::string profile = GuidText(download->profile_id);
  std::string id = download->download_id;
  report_.Run(engine::EngineDownloadChanged{.download = std::move(*download)});
  if (failed) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&EngineDownloads::CancelIfBlocked,
                                  weak_factory_.GetWeakPtr(),
                                  std::move(profile), std::move(id)));
  }
}

void EngineDownloads::CancelIfBlocked(std::string profile,
                                      std::string download) {
  auto* current = Find(profile, download);
  if (!current || current->GetState() != download::DownloadItem::IN_PROGRESS) {
    return;
  }
  bool blocked = false;
  WarningFor(current, &blocked);
  if (blocked) {
    current->Cancel(true);
  }
}

// Reached only after the engine's own name and path reservation checks. A
// data-loss-prevention or managed target keeps the engine's policy path.
void EngineDownloads::ChooseDestination(
    download::DownloadItem* item,
    const base::FilePath& suggested_path,
    DownloadConfirmationReason reason,
    DownloadTargetDeterminerDelegate::ConfirmationCallback callback) {
  auto download = Describe(item);
  if (!download || reason == DownloadConfirmationReason::DLP_BLOCKED) {
    std::move(callback).Run(DownloadConfirmationResult::CANCELED,
                            ui::SelectedFileInfo());
    return;
  }
  const engine::Guid id = RandomGuid();
  destinations_[id] = Destination{.profile = GuidText(download->profile_id),
                                  .download = download->download_id,
                                  .callback = std::move(callback)};
  // Only the host of the file's address leaves the engine, for the question
  // about a file the core judges dangerous.
  const std::string host(item->GetURL().host());
  report_.Run(engine::EngineDownloadDestinationRequested{
      .prompt_id = id,
      .download = std::move(*download),
      .suggested_filename = suggested_path.BaseName().AsUTF8Unsafe(),
      .forces_prompt = reason != DownloadConfirmationReason::NONE &&
                       reason != DownloadConfirmationReason::PREFERENCE,
      .facts = RiskFacts(item, suggested_path),
      .user_initiated = item->HasUserGesture(),
      .source_host =
          host.empty() ? std::nullopt : std::optional<std::string>(host)});
}

// Choosing where a file goes never overrides the engine's safety verdict,
// even through a save panel; the engine still checks the file.
bool EngineDownloads::Settle(const engine::SettleDownloadDestination& answer) {
  auto found = destinations_.find(answer.prompt_id);
  if (found == destinations_.end()) {
    return false;
  }
  Destination destination = std::move(found->second);
  destinations_.erase(found);
  auto* current = Find(destination.profile, destination.download);
  if (!answer.path || answer.path->empty() || !current ||
      current->GetState() != download::DownloadItem::IN_PROGRESS) {
    std::move(destination.callback)
        .Run(DownloadConfirmationResult::CANCELED, ui::SelectedFileInfo());
    return true;
  }
  std::move(destination.callback)
      .Run(DownloadConfirmationResult::CONTINUE_WITHOUT_CONFIRMATION,
           ui::SelectedFileInfo(base::FilePath(*answer.path)));
  return true;
}

// Never on the download's own notification stack.
bool EngineDownloads::Cancel(const engine::CancelEngineDownload& command) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<EngineDownloads> downloads,
                        std::string profile, std::string download) {
                       if (!downloads) {
                         return;
                       }
                       if (auto* item = downloads->Find(profile, download)) {
                         item->Cancel(true);
                       }
                     },
                     weak_factory_.GetWeakPtr(), GuidText(command.profile_id),
                     command.download_id));
  return true;
}

bool EngineDownloads::Pause(const engine::PauseEngineDownload& command) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<EngineDownloads> downloads,
                        std::string profile, std::string download) {
                       if (!downloads) {
                         return;
                       }
                       if (auto* item = downloads->Find(profile, download)) {
                         if (auto snapshot = downloads->Describe(item);
                             snapshot && snapshot->can_pause) {
                           item->Pause();
                         }
                         downloads->Changed(item);
                       }
                     },
                     weak_factory_.GetWeakPtr(), GuidText(command.profile_id),
                     command.download_id));
  return true;
}

bool EngineDownloads::Resume(const engine::ResumeEngineDownload& command) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<EngineDownloads> downloads,
                        std::string profile, std::string download) {
                       if (!downloads) {
                         return;
                       }
                       if (auto* item = downloads->Find(profile, download)) {
                         if (auto snapshot = downloads->Describe(item);
                             snapshot && snapshot->can_resume) {
                           item->Resume(true);
                         }
                         downloads->Changed(item);
                       }
                     },
                     weak_factory_.GetWeakPtr(), GuidText(command.profile_id),
                     command.download_id));
  return true;
}

bool EngineDownloads::Remove(const engine::RemoveEngineDownload& command) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<EngineDownloads> downloads,
                        std::string profile, std::string download) {
                       if (!downloads) {
                         return;
                       }
                       if (auto* item = downloads->Find(profile, download)) {
                         item->Remove();
                       }
                     },
                     weak_factory_.GetWeakPtr(), GuidText(command.profile_id),
                     command.download_id));
  return true;
}

bool EngineDownloads::Approve(const engine::ApproveEngineDownload& command) {
  auto* item = Find(GuidText(command.profile_id), command.download_id);
  if (!item || item->GetState() != download::DownloadItem::IN_PROGRESS ||
      ApprovalToken(item) != command.approval_token) {
    return false;
  }
  bool blocked = false;
  if (!WarningFor(item, &blocked) || blocked) {
    return false;
  }
  if (item->IsInsecure()) {
    item->ValidateInsecureDownload();
  } else if (item->IsDangerous()) {
    item->ValidateDangerousDownload();
  }
  return true;
}

download::DownloadItem* EngineDownloads::Find(
    const std::string& profile,
    const std::string& download) const {
  Profile* found = profiles_->Find(profile);
  return found ? found->GetDownloadManager()->GetDownloadByGuid(download)
               : nullptr;
}

}  // namespace crest
