#include "chrome/browser/ui/crest/crest_engine_profiles.h"

#include <utility>

#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "base/uuid.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_remover_constants.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/nuke_profile_directory_utils.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_attributes_storage_observer.h"
#include "chrome/browser/profiles/profile_destroyer.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_metrics.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browsing_data_remover.h"

namespace crest {

namespace {

// The directory of the regular profile a Space's profile `id` browses in.
base::FilePath ProfilePath(ProfileManager* manager, const std::string& id) {
  return manager->user_data_dir().AppendASCII("Crest-" + id);
}

bool IsProfileIdentity(const std::string& id) {
  return base::Uuid::ParseCaseInsensitive(id).is_valid();
}

}  // namespace

// The engine owns the wipe, its profile registry and crash-recoverable disk
// cleanup; this keeps the profile alive until the wipe and the deletion
// marker have both completed.
class EngineProfiles::Deletion final : public content::BrowsingDataRemover::Observer,
                                       public ProfileAttributesStorageObserver {
 public:
  Deletion(EngineProfiles& owner, std::string id, base::FilePath path, base::OnceCallback<void(bool)> done)
      : owner_(owner), id_(std::move(id)), path_(std::move(path)), done_(std::move(done)) {}

  ~Deletion() override {
    if (remover_) {
      remover_->RemoveObserver(this);
    }
    if (observing_storage_) {
      g_browser_process->profile_manager()->GetProfileAttributesStorage().RemoveObserver(this);
    }
  }

  void Start(Profile* profile) {
    if (!profile || owner_->disposing_) {
      Finish(false);
      return;
    }
    profile_ = profile;
    keep_alive_ = std::make_unique<ScopedProfileKeepAlive>(profile, ProfileKeepAliveOrigin::kProfileDeletionProcess);
    if (IsProfileDirectoryMarkedForDeletion(path_)) {
      Wipe();
      return;
    }
    auto* manager = g_browser_process->profile_manager();
    manager->GetProfileAttributesStorage().AddObserver(this);
    observing_storage_ = true;
    // This first signs the profile out, so the engine's own sync cannot carry
    // the deletion anywhere, and persists its deletion marker.
    manager->GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(path_, base::DoNothing(),
                                                                      ProfileMetrics::DELETE_PROFILE_SETTINGS);
  }

  // content::BrowsingDataRemover::Observer:
  void OnBrowsingDataRemoverDone(uint64_t failures) override {
    remover_->RemoveObserver(this);
    remover_ = nullptr;
    if (failures || owner_->disposing_) {
      Finish(false);
      return;
    }
    // Success is not reported while the next launch's cleanup marker is only
    // in memory.
    g_browser_process->local_state()->CommitPendingWrite(
        base::BindOnce(&Deletion::Finish, weak_factory_.GetWeakPtr(), true));
  }

  // ProfileAttributesStorageObserver:
  void OnProfileWasRemoved(const base::FilePath& path, const std::u16string&) override {
    if (path != path_) {
      return;
    }
    g_browser_process->profile_manager()->GetProfileAttributesStorage().RemoveObserver(this);
    observing_storage_ = false;
    Wipe();
  }

  void Finish(bool success) {
    if (finished_) {
      return;
    }
    finished_ = true;
    const bool may_retry = !success && !IsProfileDirectoryMarkedForDeletion(path_);
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<EngineProfiles> owner, std::string id, bool may_retry,
                          base::OnceCallback<void(bool)> done, bool success) {
                         if (owner) {
                           owner->Finished(id, may_retry);
                         }
                         std::move(done).Run(success);
                       },
                       owner_->weak_factory_.GetWeakPtr(), id_, may_retry, std::move(done_), success));
  }

 private:
  void Wipe() {
    remover_ = profile_->GetBrowsingDataRemover();
    remover_->AddObserver(this);
    remover_->RemoveAndReply(base::Time(), base::Time::Max(), chrome_browsing_data_remover::WIPE_PROFILE,
                             chrome_browsing_data_remover::ALL_ORIGIN_TYPES, this);
  }

  const raw_ref<EngineProfiles> owner_;
  const std::string id_;
  const base::FilePath path_;
  base::OnceCallback<void(bool)> done_;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive_;
  raw_ptr<Profile> profile_ = nullptr;
  raw_ptr<content::BrowsingDataRemover> remover_ = nullptr;
  bool observing_storage_ = false;
  bool finished_ = false;
  base::WeakPtrFactory<Deletion> weak_factory_{this};
};

EngineProfiles::EngineProfiles() = default;

EngineProfiles::~EngineProfiles() = default;

void EngineProfiles::SetRoot(Profile* root) {
  root_ = root;
}

Profile* EngineProfiles::Find(const std::string& id) const {
  auto found = profiles_.find(id);
  return found == profiles_.end() ? nullptr : found->second.get();
}

std::string EngineProfiles::IdFor(const content::BrowserContext* context) const {
  for (const auto& [id, profile] : profiles_) {
    if (profile.get() == context) {
      return id;
    }
  }
  return std::string();
}

bool EngineProfiles::IsDeleting(const std::string& id) const {
  return deleting_.contains(id);
}

void EngineProfiles::Load(const std::string& id, bool is_private, base::OnceCallback<void(Profile*)> done) {
  auto* manager = g_browser_process->profile_manager();
  if (!root_ || disposing_ || !manager || !IsProfileIdentity(id) || deleting_.contains(id)) {
    std::move(done).Run(nullptr);
    return;
  }
  // A private profile derives from the engine's own, never from a Space's,
  // so no Space's cookies, settings or extensions reach it.
  if (is_private) {
    Loaded(id, is_private, std::move(done), root_.get());
    return;
  }
  manager->CreateProfileAsync(ProfilePath(manager, id), base::BindOnce(&EngineProfiles::Loaded,
                                                                     weak_factory_.GetWeakPtr(), id, is_private,
                                                                     std::move(done)));
}

void EngineProfiles::Loaded(const std::string& id,
                            bool is_private,
                            base::OnceCallback<void(Profile*)> done,
                            Profile* profile) {
  if (!profile || disposing_ || deleting_.contains(id)) {
    std::move(done).Run(nullptr);
    return;
  }
  if (!profiles_.contains(id)) {
    // The regular profile owns an off-the-record one and must outlive it. A
    // private profile creates no profile directory, session checkpoint or
    // browsing history, and each private Space's is its own.
    leases_[id] = std::make_unique<ScopedProfileKeepAlive>(profile, ProfileKeepAliveOrigin::kAppWindow);
    profiles_[id] = is_private ? profile->GetOffTheRecordProfile(
                                     Profile::OTRProfileID::CreateUnique("Crest::Private::" + id), true)
                               : profile;
  }
  std::move(done).Run(profiles_[id]);
}

void EngineProfiles::Prepare(const std::string& id, base::OnceCallback<void(bool)> done) {
  auto* manager = g_browser_process->profile_manager();
  if (!manager || !IsProfileIdentity(id) || disposing_ || deleting_.contains(id)) {
    std::move(done).Run(false);
    return;
  }
  if (Profile* loaded = Find(id)) {
    std::move(done).Run(!loaded->IsOffTheRecord());
    return;
  }
  manager->CreateProfileAsync(
      ProfilePath(manager, id),
      base::BindOnce(
          [](base::WeakPtr<EngineProfiles> profiles, std::string id, base::OnceCallback<void(bool)> done,
             Profile* profile) {
            if (!profiles || !profile || profiles->disposing_ || profiles->deleting_.contains(id)) {
              std::move(done).Run(false);
              return;
            }
            if (!profiles->profiles_.contains(id)) {
              profiles->profiles_[id] = profile;
              profiles->leases_[id] =
                  std::make_unique<ScopedProfileKeepAlive>(profile, ProfileKeepAliveOrigin::kAppWindow);
            }
            std::move(done).Run(true);
          },
          weak_factory_.GetWeakPtr(), id, std::move(done)));
}

void EngineProfiles::Release(const std::string& id) {
  auto found = profiles_.find(id);
  if (found == profiles_.end()) {
    return;
  }
  Profile* profile = found->second;
  profiles_.erase(found);
  if (profile->IsOffTheRecord()) {
    ProfileDestroyer::DestroyOTRProfileWhenAppropriate(profile);
  }
  leases_.erase(id);
}

void EngineProfiles::ReleaseAll() {
  for (const auto& [id, profile] : profiles_) {
    if (profile->IsOffTheRecord()) {
      ProfileDestroyer::DestroyOTRProfileWhenAppropriate(profile);
    }
  }
  profiles_.clear();
  leases_.clear();
  deletion_holds_.clear();
}

bool EngineProfiles::HasStore(const std::string& id) const {
  auto* manager = g_browser_process->profile_manager();
  if (!manager || !IsProfileIdentity(id)) {
    return false;
  }
  const base::FilePath path = ProfilePath(manager, id);
  return manager->GetProfileAttributesStorage().GetProfileAttributesWithPath(path) || base::PathExists(path);
}

bool EngineProfiles::BeginDeletion(const std::string& id, bool ephemeral) {
  auto* manager = g_browser_process->profile_manager();
  if (!manager || disposing_ || !IsProfileIdentity(id) || deletions_.contains(id)) {
    return false;
  }
  Profile* profile = Find(id);
  if (ephemeral && profile && !profile->IsOffTheRecord()) {
    return false;
  }
  if (profile == root_ || (profile && !profile->IsOffTheRecord() && profile->GetPath() != ProfilePath(manager, id))) {
    return false;
  }
  if (profile && !profile->IsOffTheRecord()) {
    // Held while its pages, Browsers and Crest's own leases are let go of.
    deletion_holds_[id] =
        std::make_unique<ScopedProfileKeepAlive>(profile, ProfileKeepAliveOrigin::kProfileDeletionProcess);
  }
  deleting_.insert(id);
  return true;
}

void EngineProfiles::Delete(const std::string& id, bool ephemeral, base::OnceCallback<void(bool)> done) {
  // The hold ends once the deletion holds the profile itself, or has nothing
  // to hold.
  base::ScopedClosureRunner release_hold(base::BindOnce(
      [](base::WeakPtr<EngineProfiles> profiles, std::string id) {
        if (profiles) {
          profiles->deletion_holds_.erase(id);
        }
      },
      weak_factory_.GetWeakPtr(), id));
  auto* manager = g_browser_process->profile_manager();
  if (ephemeral) {
    std::move(done).Run(true);
    return;
  }
  if (!manager || disposing_) {
    std::move(done).Run(false);
    return;
  }
  const base::FilePath path = ProfilePath(manager, id);
  if (!manager->GetProfileAttributesStorage().GetProfileAttributesWithPath(path) &&
      !manager->GetProfileByPath(path) && !base::PathExists(path)) {
    std::move(done).Run(true);
    return;
  }
  auto deletion = std::make_unique<Deletion>(*this, id, path, std::move(done));
  Deletion* pending = deletion.get();
  deletions_.emplace(id, std::move(deletion));
  if (Profile* loaded = manager->GetProfileByPath(path)) {
    pending->Start(loaded);
    return;
  }
  if (IsProfileDirectoryMarkedForDeletion(path)) {
    pending->Finish(false);
    return;
  }
  manager->CreateProfileAsync(path, base::BindOnce(
                                        [](base::WeakPtr<EngineProfiles> profiles, std::string id, Profile* loaded) {
                                          if (!profiles) {
                                            return;
                                          }
                                          if (auto found = profiles->deletions_.find(id);
                                              found != profiles->deletions_.end()) {
                                            found->second->Start(loaded);
                                          }
                                        },
                                        weak_factory_.GetWeakPtr(), id));
}

void EngineProfiles::Finished(const std::string& id, bool may_retry) {
  if (may_retry) {
    deleting_.erase(id);
  }
  deletions_.erase(id);
}

void EngineProfiles::Dispose() {
  disposing_ = true;
}

}  // namespace crest
