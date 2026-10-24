#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_PROFILES_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_PROFILES_H_

#include <map>
#include <memory>
#include <set>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"

class Profile;
class ScopedProfileKeepAlive;

namespace content {
class BrowserContext;
}

namespace crest {

// The engine profiles Crest browses in: each Space's own regular profile,
// named `Crest-<Space profile>` in the engine's user data directory, and each
// private Space's off-the-record profile. A private profile always derives
// from the engine's own profile, which no Space owns and no page browses in,
// so it shares nothing with any Space; its profile is new each time private
// browsing opens, and it is destroyed when released. Their stores — cookies,
// storage, cache, network state — are the engine's; this decides which
// profile a page gets, keeps the ones in use alive, and wipes one when its
// Space is deleted.
class EngineProfiles final {
 public:
  EngineProfiles();
  EngineProfiles(const EngineProfiles&) = delete;
  EngineProfiles& operator=(const EngineProfiles&) = delete;
  ~EngineProfiles();

  // The profile the engine started with. It is no Space's, is never deleted,
  // and until it exists no profile loads. Private profiles derive from it.
  void SetRoot(Profile* root);

  Profile* Find(const std::string& id) const;
  // Whether the regular profile `id` names has anything on disk.
  bool HasStore(const std::string& id) const;
  // The Crest identity of an engine profile, or an empty string for one Crest
  // does not own.
  std::string IdFor(const content::BrowserContext* context) const;
  bool IsDeleting(const std::string& id) const;
  // A deletion is still wiping a profile's data.
  bool IsDeletingAny() const { return !deletions_.empty(); }

  // Loads the profile `id` names, a Space's regular profile, or a private
  // Space's off-the-record profile derived from the engine's own, and answers
  // it, or nullptr when it cannot load or is being deleted.
  void Load(const std::string& id, bool is_private, base::OnceCallback<void(Profile*)> done);
  // Loads a Space's regular profile for its extensions. Answers whether it is
  // ready; a private profile never is.
  void Prepare(const std::string& id, base::OnceCallback<void(bool)> done);

  // Lets go of `id`: an off-the-record profile is destroyed once the engine
  // can, and Crest's hold on a regular one ends.
  void Release(const std::string& id);
  void ReleaseAll();

  // Begins deleting `id`, which the caller lets go of before `Delete`, or
  // refuses: the engine's own profile, one already being deleted, or a
  // regular profile asked to go as if it were private.
  bool BeginDeletion(const std::string& id, bool ephemeral);
  // Wipes the deleted profile's data and leaves its directory marked for
  // deletion at the next launch, then answers whether that finished. A
  // private profile has nothing on disk, so it is deleted at once.
  void Delete(const std::string& id, bool ephemeral, base::OnceCallback<void(bool)> done);

  // The engine is shutting down: nothing more loads or is deleted.
  void Dispose();

 private:
  class Deletion;

  void Loaded(const std::string& id, bool is_private, base::OnceCallback<void(Profile*)> done, Profile* profile);
  void Finished(const std::string& id, bool may_retry);

  raw_ptr<Profile> root_ = nullptr;
  bool disposing_ = false;
  std::map<std::string, raw_ptr<Profile>> profiles_;
  // The regular profiles Crest holds alive, by the Crest profile that uses
  // them: an off-the-record profile's lease is on its regular source, which
  // must outlive it.
  std::map<std::string, std::unique_ptr<ScopedProfileKeepAlive>> leases_;
  std::set<std::string> deleting_;
  // A regular profile being deleted is held while its pages and Browsers are
  // let go of, until its deletion starts.
  std::map<std::string, std::unique_ptr<ScopedProfileKeepAlive>> deletion_holds_;
  std::map<std::string, std::unique_ptr<Deletion>> deletions_;
  base::WeakPtrFactory<EngineProfiles> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_PROFILES_H_
