#include "chrome/browser/ui/crest/crest_engine_profiles.h"

#include <map>
#include <set>
#include <string_view>
#include <utility>

#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "base/uuid.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_model_delegate.h"
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
#include "components/browsing_data/content/browsing_data_model.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browsing_data_filter_builder.h"
#include "content/public/browser/browsing_data_remover.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "net/base/schemeful_site.h"
#include "net/cookies/cookie_partition_key_collection.h"
#include "url/gurl.h"
#include "url/origin.h"
#include "url/url_constants.h"

namespace crest {

namespace {

// The directory of the regular profile a Space's profile `id` browses in.
base::FilePath ProfilePath(ProfileManager* manager, const std::string& id) {
  return manager->user_data_dir().AppendASCII("Crest-" + id);
}

bool IsProfileIdentity(const std::string& id) {
  return base::Uuid::ParseCaseInsensitive(id).is_valid();
}

// The web origins a site clear reaches: every one, including those an
// installed app protects, but never an extension's.
constexpr uint64_t kWebOrigins = content::BrowsingDataRemover::ORIGIN_TYPE_UNPROTECTED_WEB |
                                 content::BrowsingDataRemover::ORIGIN_TYPE_PROTECTED_WEB;

// What the remover removes for `category`.
uint64_t RemovalMask(engine::BrowsingDataCategory category) {
  switch (category) {
    case engine::BrowsingDataCategory::kHistory:
      return chrome_browsing_data_remover::DATA_TYPE_HISTORY;
    case engine::BrowsingDataCategory::kSiteData:
      return chrome_browsing_data_remover::DATA_TYPE_SITE_DATA;
    case engine::BrowsingDataCategory::kCache:
      return content::BrowsingDataRemover::DATA_TYPE_CACHE;
  }
  return 0;
}

// The registrable domain the engine groups `host` under, or the host itself
// when it has none, such as localhost or an IP address, which an IPv6 one is
// in brackets, as a URL spells it.
std::string SiteOf(std::string_view host) {
  while (!host.empty() && host.front() == '.') {
    host.remove_prefix(1);
  }
  if (!host.empty() && host.front() != '[' && host.find(':') != std::string_view::npos) {
    return "[" + std::string(host) + "]";
  }
  std::string domain = net::registry_controlled_domains::GetDomainAndRegistry(
      host, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  return domain.empty() ? std::string(host) : domain;
}

// The partition keys of cookies third parties set while embedded in `site`,
// over either scheme.
void AddPartitionKeys(const std::string& site, base::flat_set<net::CookiePartitionKey>& keys) {
  for (const char* scheme : {url::kHttpsScheme, url::kHttpScheme}) {
    const GURL url(std::string(scheme) + "://" + site + "/");
    if (!url.is_valid()) {
      continue;
    }
    const auto collection = net::CookiePartitionKeyCollection::MatchesSite(net::SchemefulSite(url));
    keys.insert(collection.PartitionKeys().begin(), collection.PartitionKeys().end());
  }
}

// Runs browsing data removals on a profile one after another, then answers
// whether every one finished without a failure. It owns itself until the
// last one reports back.
class Removals final : public content::BrowsingDataRemover::Observer {
 public:
  struct Removal {
    uint64_t mask = 0;
    base::Time since;
    // Which origins and cookies it covers, or every one when it is null.
    std::unique_ptr<content::BrowsingDataFilterBuilder> filter;
  };

  static void Run(Profile* profile, std::vector<Removal> removals, base::OnceCallback<void(bool)> done) {
    (new Removals(profile->GetBrowsingDataRemover(), std::move(removals), std::move(done)))->Next();
  }

  void OnBrowsingDataRemoverDone(uint64_t failed_data_types) override {
    removed_ = removed_ && failed_data_types == 0;
    Next();
  }

 private:
  Removals(content::BrowsingDataRemover* remover, std::vector<Removal> removals, base::OnceCallback<void(bool)> done)
      : remover_(remover), removals_(std::move(removals)), done_(std::move(done)) {
    remover_->AddObserver(this);
  }

  void Next() {
    while (!removals_.empty() && removals_.front().mask == 0) {
      removals_.erase(removals_.begin());
    }
    if (removals_.empty()) {
      remover_->RemoveObserver(this);
      std::move(done_).Run(removed_);
      delete this;
      return;
    }
    Removal removal = std::move(removals_.front());
    removals_.erase(removals_.begin());
    if (removal.filter) {
      remover_->RemoveWithFilterAndReply(removal.since, base::Time::Max(), removal.mask, kWebOrigins,
                                         std::move(removal.filter), this);
    } else {
      remover_->RemoveAndReply(removal.since, base::Time::Max(), removal.mask,
                               content::BrowsingDataRemover::ORIGIN_TYPE_UNPROTECTED_WEB, this);
    }
  }

  const raw_ptr<content::BrowsingDataRemover> remover_;
  std::vector<Removals::Removal> removals_;
  base::OnceCallback<void(bool)> done_;
  bool removed_ = true;
};

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

void SiteData::Clear(Profile* profile,
                     const std::vector<std::string>& hosts,
                     const std::vector<engine::BrowsingDataCategory>& categories,
                     base::OnceCallback<void(bool)> done) {
  std::set<std::string> sites;
  for (const std::string& host : hosts) {
    if (std::string site = SiteOf(host); !site.empty()) {
      sites.insert(std::move(site));
    }
  }
  uint64_t mask = 0;
  for (engine::BrowsingDataCategory category : categories) {
    if (category != engine::BrowsingDataCategory::kHistory) {
      mask |= RemovalMask(category);
    }
  }
  if (sites.empty() || mask == 0) {
    std::move(done).Run(false);
    return;
  }
  std::vector<Removals::Removal> removals;
  // The sites' own data, and what their third parties store partitioned
  // under them; cookies match by their own domain only.
  auto own = content::BrowsingDataFilterBuilder::Create(content::BrowsingDataFilterBuilder::Mode::kDelete);
  for (const std::string& site : sites) {
    own->AddRegisterableDomain(site);
  }
  removals.push_back({.mask = mask, .filter = std::move(own)});
  // The cookies third parties set while embedded in the sites, which carry
  // the sites as their partition.
  if (mask & content::BrowsingDataRemover::DATA_TYPE_COOKIES) {
    base::flat_set<net::CookiePartitionKey> keys;
    for (const std::string& site : sites) {
      AddPartitionKeys(site, keys);
    }
    auto partitioned = content::BrowsingDataFilterBuilder::Create(content::BrowsingDataFilterBuilder::Mode::kPreserve);
    partitioned->SetCookiePartitionKeyCollection(net::CookiePartitionKeyCollection(std::move(keys)));
    partitioned->SetPartitionedCookiesOnly(true);
    removals.push_back({.mask = content::BrowsingDataRemover::DATA_TYPE_COOKIES, .filter = std::move(partitioned)});
  }
  Removals::Run(profile, std::move(removals), std::move(done));
}

void SiteData::Clear(Profile* profile,
                     std::optional<base::Time> since,
                     const std::vector<engine::BrowsingDataCategory>& categories,
                     base::OnceCallback<void(bool)> done) {
  uint64_t mask = 0;
  for (engine::BrowsingDataCategory category : categories) {
    mask |= RemovalMask(category);
  }
  std::vector<Removals::Removal> removals;
  removals.push_back({.mask = mask, .since = since.value_or(base::Time())});
  Removals::Run(profile, std::move(removals), std::move(done));
}

void SiteData::Read(Profile* profile, base::OnceCallback<void(std::vector<engine::StoredSite>)> done) {
  BrowsingDataModel::BuildFromDisk(
      profile, ChromeBrowsingDataModelDelegate::CreateForProfile(profile),
      base::BindOnce(
          [](base::OnceCallback<void(std::vector<engine::StoredSite>)> done,
             std::unique_ptr<BrowsingDataModel> model) {
            std::map<std::string, std::set<engine::WebsiteDataKind>> sites;
            for (const BrowsingDataModel::BrowsingDataEntryView& entry : *model) {
              std::string site;
              if (std::optional<net::SchemefulSite> partition = entry.GetThirdPartyPartitioningSite()) {
                site = SiteOf(partition->GetURL().host());
              } else if (const auto* host = std::get_if<std::string>(&*entry.data_owner)) {
                site = SiteOf(*host);
              } else if (const auto& origin = std::get<url::Origin>(*entry.data_owner);
                         origin.scheme() == url::kHttpsScheme || origin.scheme() == url::kHttpScheme) {
                site = SiteOf(origin.host());
              }
              if (site.empty()) {
                continue;
              }
              const bool cookies = entry.data_details->storage_types.Has(BrowsingDataModel::StorageType::kCookie);
              auto& kinds = sites[site];
              kinds.insert(cookies ? engine::WebsiteDataKind::kCookies : engine::WebsiteDataKind::kStorage);
              if (cookies && entry.data_details->storage_types.size() > 1) {
                kinds.insert(engine::WebsiteDataKind::kStorage);
              }
            }
            std::vector<engine::StoredSite> stored;
            for (auto& [site, kinds] : sites) {
              stored.push_back({.site = site, .kinds = {kinds.begin(), kinds.end()}});
            }
            std::move(done).Run(std::move(stored));
          },
          std::move(done)));
}

}  // namespace crest
