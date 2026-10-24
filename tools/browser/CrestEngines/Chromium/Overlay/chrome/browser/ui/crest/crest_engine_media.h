#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_MEDIA_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_MEDIA_H_

#include <cstdint>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "content/public/browser/media_player_id.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "services/media_session/public/cpp/media_image.h"
#include "services/media_session/public/mojom/media_session.mojom.h"

class SkBitmap;

namespace content {
class WebContents;
}

namespace crest {

class AudioSpectrumTap;

// A page's media: what it plays and captures, and the engine's own Media
// Session — metadata, artwork, playback state and the actions the page
// handles — as Crest shows it under the document identity Crest issued for the
// document the page shows. The engine deactivates the session of a muted page;
// Crest keeps showing it, muted, so the person can unmute it.
//
// The engine fetches the artwork it picks from the page's list through the
// frame that set it, with that frame's cookies, so artwork a signed-in site
// serves only to its session loads too. The image is kept until the page names
// other artwork, and each report carries it.
class PageMedia final : public media_session::mojom::MediaSessionObserver {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;

  // Follows `contents`' media for the page `page`. `present` hears the
  // session as Crest shows it, and `changed` that what the page runs changed.
  PageMedia(content::WebContents* contents, const engine::Guid& page, Present present,
            base::RepeatingClosure changed);
  PageMedia(const PageMedia&) = delete;
  PageMedia& operator=(const PageMedia&) = delete;
  ~PageMedia() override;

  // What the page runs now. A video that was playing when the page left the
  // screen still counts as playing.
  engine::PageMediaActivity Activity() const;

  void PlayerStarted(const content::MediaPlayerId& id, bool has_video);
  void PlayerStopped(const content::MediaPlayerId& id);
  // The page's sound or muting changed.
  void AudioChanged();
  // The page committed a new document, which gets a session identity of its own.
  void DocumentChanged();
  // The page's view left the screen or came back to it.
  void VisibilityChanged(bool visible);
  // The page's video or document entered or left Picture in Picture.
  void PictureInPictureChanged(bool active);
  // Another page began or stopped sharing this one as a tab, which counts as
  // capture for as long as it lasts.
  void SharedChanged(bool shared);
  // Whether another page shares this one as a tab now.
  bool shared() const { return shares_ > 0; }
  // This page began or stopped sharing another tab, which counts as capture
  // for as long as it lasts.
  void SharingChanged(bool sharing);
  // Whether this page shares another tab now.
  bool sharing() const { return sharing_ > 0; }
  // Whether an ask for the page comes from its Picture in Picture window's
  // return control: the page left Picture in Picture in the task running
  // now, or its document is still there.
  bool ReturnsFromPictureInPicture() const;

  // What the platform asks of the session.
  bool EnterPictureInPicture();
  // Ends the page's own Picture in Picture; one of another page stays.
  bool ExitPictureInPicture();
  bool Activate(const std::string& document);
  bool Perform(const std::string& document, engine::MediaSessionAction action);
  bool Mute(const std::string& document, bool muted);
  // Starts or stops measuring the sound the page plays, band by band, for its
  // tab to show. While measured, `present` hears the bands a few times a
  // second, and a silent page sends nothing new.
  bool ObserveSpectrum(bool observed);

  // media_session::mojom::MediaSessionObserver:
  void MediaSessionInfoChanged(media_session::mojom::MediaSessionInfoPtr info) override;
  void MediaSessionMetadataChanged(const std::optional<media_session::MediaMetadata>& metadata) override;
  void MediaSessionActionsChanged(const std::vector<media_session::mojom::MediaSessionAction>& actions) override;
  void MediaSessionImagesChanged(
      const base::flat_map<media_session::mojom::MediaSessionImageType, std::vector<media_session::MediaImage>>&
          images) override;
  void MediaSessionPositionChanged(const std::optional<media_session::MediaPosition>& position) override;

 private:
  // Presents the session as Crest shows it, once Crest issued its document.
  void Publish();
  // Keeps the artwork the engine fetched for `generation`, unless the page
  // named other artwork since.
  void ArtworkLoaded(uint64_t generation, const SkBitmap& bitmap);
  // Presents the bands the spectrum tap measured last.
  void SpectrumMeasured(engine::Bytes bands);

  const raw_ptr<content::WebContents> contents_;
  const engine::Guid page_;
  const Present present_;
  const base::RepeatingClosure changed_;
  mojo::Receiver<media_session::mojom::MediaSessionObserver> receiver_{this};
  media_session::mojom::MediaSessionInfoPtr info_;
  std::optional<media_session::MediaMetadata> metadata_;
  std::vector<media_session::mojom::MediaSessionAction> actions_;
  // The artwork picked from the page's list, and its image once fetched.
  std::optional<media_session::MediaImage> artwork_image_;
  std::optional<std::vector<uint8_t>> artwork_;
  // Counts artwork changes, so a fetch that finishes late is dropped.
  uint64_t artwork_generation_ = 0;
  std::string document_;
  int64_t sequence_ = 0;
  bool seen_active_ = false;
  bool last_playing_ = false;
  std::set<content::MediaPlayerId> playing_videos_;
  bool played_before_hidden_ = false;
  // The page left Picture in Picture in the task running now.
  bool leaving_picture_in_picture_ = false;
  // How many captures share the page as a tab now.
  int shares_ = 0;
  // How many tabs the page shares now.
  int sharing_ = 0;
  // Listens to the page's own sound while the platform observes it.
  std::unique_ptr<AudioSpectrumTap> spectrum_;
  base::WeakPtrFactory<PageMedia> weak_factory_{this};
};

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_MEDIA_H_
