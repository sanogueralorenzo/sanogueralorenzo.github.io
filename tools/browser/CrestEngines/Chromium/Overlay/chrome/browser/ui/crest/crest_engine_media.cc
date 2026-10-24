#include "chrome/browser/ui/crest/crest_engine_media.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdlib>
#include <numbers>
#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/scoped_refptr.h"
#include "base/sequence_checker.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "content/public/browser/audio_service.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/web_contents.h"
#include "media/audio/audio_input_device.h"
#include "media/audio/audio_input_ipc.h"
#include "media/base/audio_bus.h"
#include "media/base/audio_capturer_source.h"
#include "media/base/audio_parameters.h"
#include "media/mojo/mojom/audio_data_pipe.mojom.h"
#include "media/mojo/mojom/audio_input_stream.mojom.h"
#include "media/mojo/mojom/audio_stream_factory.mojom.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "mojo/public/cpp/bindings/self_owned_receiver.h"
#include "services/audio/public/mojom/audio_service.mojom.h"
#include "services/media_session/public/cpp/media_image_manager.h"
#include "services/media_session/public/cpp/media_metadata.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/codec/png_codec.h"

namespace crest {

namespace {

// The longest document identity Crest issues.
constexpr size_t kDocumentLength = 128;

// The longest side of the artwork Crest keeps, in pixels: what the engine's own
// media controls ask for, and enough for the system's Now Playing. The engine
// scales a larger image down to it, keeping its shape.
constexpr int kArtworkPixels = 512;

// The smallest artwork Crest takes. Any image the page gives beats none.
constexpr int kArtworkMinimumPixels = 0;

std::optional<std::string> Text(const std::u16string& value) {
  return value.empty() ? std::nullopt : std::optional<std::string>(base::UTF16ToUTF8(value));
}

// The loopback stream's own observer, which has nothing to do.
class SilentStreamObserver final : public media::mojom::AudioInputStreamObserver {
 public:
  void DidStartRecording() final {}
};

// Opens a loopback stream of everything one page plays, from the audio
// service, for an input device to read. The engine's own tab capture reads
// a page the same way.
class LoopbackAudioInputIPC final : public media::AudioInputIPC, public media::mojom::AudioInputStreamClient {
 public:
  explicit LoopbackAudioInputIPC(const base::UnguessableToken& group) : group_(group) {
    DETACH_FROM_SEQUENCE(sequence_checker_);
  }
  LoopbackAudioInputIPC(const LoopbackAudioInputIPC&) = delete;
  LoopbackAudioInputIPC& operator=(const LoopbackAudioInputIPC&) = delete;
  ~LoopbackAudioInputIPC() override = default;

  // media::AudioInputIPC:
  void CreateStream(media::AudioInputIPCDelegate* delegate, const media::AudioParameters& params,
                    bool automatic_gain_control, uint32_t total_segments) override {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    delegate_ = delegate;
    content::GetAudioService().BindStreamFactory(factory_.BindNewPipeAndPassReceiver());
    auto client = client_.BindNewPipeAndPassRemote();
    client_.set_disconnect_handler(base::BindOnce(&LoopbackAudioInputIPC::OnError, weak_factory_.GetWeakPtr(),
                                                  media::mojom::InputStreamErrorCode::kUnknown));
    mojo::PendingRemote<media::mojom::AudioInputStreamObserver> observer;
    mojo::MakeSelfOwnedReceiver(std::make_unique<SilentStreamObserver>(),
                                observer.InitWithNewPipeAndPassReceiver());
    factory_->CreateLoopbackStream(stream_.BindNewPipeAndPassReceiver(), std::move(client), std::move(observer),
                                   params, total_segments, group_,
                                   base::BindOnce(&LoopbackAudioInputIPC::StreamCreated, weak_factory_.GetWeakPtr()));
  }

  void RecordStream() override {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    if (stream_.is_bound()) {
      stream_->Record();
    }
  }

  void SetVolume(double volume) override {}

  void SetOutputDeviceForAec(const std::string& output_device_id) override {}

  void CloseStream() override {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    delegate_ = nullptr;
    client_.reset();
    stream_.reset();
    weak_factory_.InvalidateWeakPtrs();
  }

  // media::mojom::AudioInputStreamClient:
  void OnError(media::mojom::InputStreamErrorCode code) override {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    if (delegate_) {
      delegate_->OnError(media::AudioCapturerSource::ErrorCode::kUnknown);
    }
  }

  void OnMutedStateChanged(bool is_muted) override {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    if (delegate_) {
      delegate_->OnMuted(is_muted);
    }
  }

 private:
  void StreamCreated(media::mojom::ReadWriteAudioDataPipePtr data_pipe) {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    if (data_pipe.is_null() || !delegate_) {
      OnError(media::mojom::InputStreamErrorCode::kUnknown);
      return;
    }
    delegate_->OnStreamCreated(std::move(data_pipe->shared_memory), data_pipe->socket.TakePlatformFile(),
                               /*initially_muted=*/false);
  }

  SEQUENCE_CHECKER(sequence_checker_);
  const base::UnguessableToken group_;
  raw_ptr<media::AudioInputIPCDelegate> delegate_ = nullptr;
  mojo::Remote<media::mojom::AudioStreamFactory> factory_;
  mojo::Remote<media::mojom::AudioInputStream> stream_;
  mojo::Receiver<media::mojom::AudioInputStreamClient> client_{this};
  base::WeakPtrFactory<LoopbackAudioInputIPC> weak_factory_{this};
};

}  // namespace

// Listens to everything one page plays and measures how loud it is in each of
// a few frequency bands, a few times a second, handing on a measure only when
// it differs from the last one it handed on. It reads the sound the page
// sends to the audio service, as tab capture does, so a page's media
// elements, Web Audio and plug-in sound all count. The device delivers sound
// on its own thread; the tap measures there and hands each result to the
// page's media on the thread that made it.
class AudioSpectrumTap final : public media::AudioCapturerSource::CaptureCallback {
 public:
  using Measured = base::RepeatingCallback<void(engine::Bytes)>;

  AudioSpectrumTap(const base::UnguessableToken& group, Measured measured)
      : measured_(std::move(measured)), reply_(base::SequencedTaskRunner::GetCurrentDefault()) {
    for (size_t index = 0; index < kWindow; ++index) {
      window_[index] = 0.5f - 0.5f * std::cos(2 * std::numbers::pi_v<float> * static_cast<float>(index) /
                                               static_cast<float>(kWindow - 1));
    }
    const float bin_width = static_cast<float>(kSampleRate) / static_cast<float>(kWindow);
    for (size_t band = 0; band <= kBands; ++band) {
      const float frequency =
          kLowest * std::pow(kHighest / kLowest, static_cast<float>(band) / static_cast<float>(kBands));
      edges_[band] = std::clamp<size_t>(static_cast<size_t>(frequency / bin_width), 1, kWindow / 2);
    }
    device_ = base::MakeRefCounted<media::AudioInputDevice>(std::make_unique<LoopbackAudioInputIPC>(group),
                                                            media::AudioInputDevice::Purpose::kLoopback,
                                                            media::AudioInputDevice::DeadStreamDetection::kDisabled);
    device_->Initialize(media::AudioParameters(media::AudioParameters::AUDIO_PCM_LOW_LATENCY,
                                               media::ChannelLayoutConfig::Stereo(), kSampleRate, kBufferFrames),
                        this);
    device_->Start();
  }
  AudioSpectrumTap(const AudioSpectrumTap&) = delete;
  AudioSpectrumTap& operator=(const AudioSpectrumTap&) = delete;

  // Stopping the device waits for its thread, so no sound arrives after.
  ~AudioSpectrumTap() override { device_->Stop(); }

  // media::AudioCapturerSource::CaptureCallback:
  void Capture(const media::AudioBus* source, base::TimeTicks, const media::AudioGlitchInfo&, double) override {
    const int channels = source->channels();
    for (int frame = 0; frame < source->frames(); ++frame) {
      float sample = 0;
      for (int channel = 0; channel < channels; ++channel) {
        sample += source->channel(channel)[static_cast<size_t>(frame)];
      }
      recent_[next_] = sample / static_cast<float>(std::max(channels, 1));
      next_ = (next_ + 1) % kWindow;
      if (++since_measure_ >= kMeasureFrames) {
        since_measure_ = 0;
        Measure();
      }
    }
  }

  void OnCaptureError(media::AudioCapturerSource::ErrorCode, const std::string&) override {}

  void OnCaptureMuted(bool) override {}

 private:
  // The sound the tap reads, in buffers long enough that the device wakes
  // only a few times between measures, and how often it measures it.
  static constexpr int kSampleRate = 48000;
  static constexpr int kBufferFrames = kSampleRate / 20;
  static constexpr int kMeasureFrames = kSampleRate / 15;
  // The window each measure looks at, in samples, a power of two.
  static constexpr size_t kWindow = 1024;
  // The bands, spaced evenly in pitch between the lowest and highest
  // frequencies they cover.
  static constexpr size_t kBands = 24;
  static constexpr float kLowest = 60;
  static constexpr float kHighest = 16000;
  // The loudness a band shows as empty and as full, in decibels below full
  // scale.
  static constexpr float kFloor = -72;
  static constexpr float kCeiling = -12;
  // How much of its last level a band keeps when the sound falls, so bars rise
  // at once and settle back.
  static constexpr float kRelease = 0.66f;
  // How far a band must move, out of 255, before a measure is worth handing
  // on.
  static constexpr int kChange = 3;

  // Measures the window that ended with the newest sample and hands on its
  // bands, unless the page stayed silent.
  void Measure() {
    std::array<std::complex<float>, kWindow> spectrum;
    for (size_t index = 0; index < kWindow; ++index) {
      spectrum[index] = recent_[(next_ + index) % kWindow] * window_[index];
    }
    Transform(spectrum);
    engine::Bytes bands(kBands);
    bool changed = false;
    for (size_t band = 0; band < kBands; ++band) {
      float peak = 0;
      const size_t last = std::max(edges_[band + 1], edges_[band] + 1);
      for (size_t bin = edges_[band]; bin < last && bin < kWindow / 2; ++bin) {
        peak = std::max(peak, std::abs(spectrum[bin]));
      }
      // A full-scale sine reaches a quarter of the window through Hann.
      const float decibels = 20 * std::log10(std::max(peak / static_cast<float>(kWindow / 4), 1e-6f));
      const float level = std::clamp((decibels - kFloor) / (kCeiling - kFloor), 0.0f, 1.0f);
      levels_[band] = std::max(level, levels_[band] * kRelease);
      bands[band] = static_cast<uint8_t>(std::lround(levels_[band] * 255));
      changed = changed || std::abs(bands[band] - handed_[band]) >= kChange ||
                (bands[band] == 0 && handed_[band] != 0);
    }
    if (!changed) {
      return;
    }
    std::copy(bands.begin(), bands.end(), handed_.begin());
    reply_->PostTask(FROM_HERE, base::BindOnce(measured_, std::move(bands)));
  }

  // An in-place radix-2 Fourier transform of the window.
  static void Transform(std::array<std::complex<float>, kWindow>& values) {
    for (size_t index = 1, reversed = 0; index < kWindow; ++index) {
      size_t bit = kWindow >> 1;
      for (; reversed & bit; bit >>= 1) {
        reversed ^= bit;
      }
      reversed ^= bit;
      if (index < reversed) {
        std::swap(values[index], values[reversed]);
      }
    }
    for (size_t length = 2; length <= kWindow; length <<= 1) {
      const float angle = -2 * std::numbers::pi_v<float> / static_cast<float>(length);
      const std::complex<float> step(std::cos(angle), std::sin(angle));
      for (size_t start = 0; start < kWindow; start += length) {
        std::complex<float> twiddle(1, 0);
        for (size_t offset = 0; offset < length / 2; ++offset) {
          const std::complex<float> even = values[start + offset];
          const std::complex<float> odd = values[start + offset + length / 2] * twiddle;
          values[start + offset] = even + odd;
          values[start + offset + length / 2] = even - odd;
          twiddle *= step;
        }
      }
    }
  }

  const Measured measured_;
  const scoped_refptr<base::SequencedTaskRunner> reply_;
  scoped_refptr<media::AudioInputDevice> device_;
  // Read and written only on the device's thread.
  std::array<float, kWindow> window_{};
  std::array<size_t, kBands + 1> edges_{};
  std::array<float, kWindow> recent_{};
  std::array<float, kBands> levels_{};
  // The bands of the last measure handed on.
  std::array<int, kBands> handed_{};
  size_t next_ = 0;
  int since_measure_ = 0;
};

PageMedia::PageMedia(content::WebContents* contents, const engine::Guid& page, Present present,
                     base::RepeatingClosure changed)
    : contents_(contents), page_(page), present_(std::move(present)), changed_(std::move(changed)) {
  if (auto* session = content::MediaSession::Get(contents)) {
    session->AddObserver(receiver_.BindNewPipeAndPassRemote());
  }
}

PageMedia::~PageMedia() = default;

engine::PageMediaActivity PageMedia::Activity() const {
  using engine::PageMediaActivity;
  PageMediaActivity activity = PageMediaActivity::kNone;
  if (played_before_hidden_ || !playing_videos_.empty() || last_playing_ || contents_->IsCurrentlyAudible() ||
      contents_->GetCurrentlyPlayingVideoCount() > 0) {
    activity = activity | PageMediaActivity::kPlaying;
  }
  auto indicator = MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator();
  if (shares_ > 0 || sharing_ > 0 || contents_->IsBeingCaptured() || indicator->IsCapturingUserMedia(contents_) ||
      indicator->IsCapturingTab(contents_) || indicator->IsCapturingWindow(contents_) ||
      indicator->IsCapturingDisplay(contents_)) {
    activity = activity | PageMediaActivity::kCapturing;
  }
  if (contents_->HasPictureInPictureVideo() || contents_->HasPictureInPictureDocument()) {
    activity = activity | PageMediaActivity::kPictureInPicture;
  }
  return activity;
}

void PageMedia::PlayerStarted(const content::MediaPlayerId& id, bool has_video) {
  if (has_video) {
    playing_videos_.insert(id);
  }
}

void PageMedia::PlayerStopped(const content::MediaPlayerId& id) {
  playing_videos_.erase(id);
}

void PageMedia::AudioChanged() {
  Publish();
}

void PageMedia::DocumentChanged() {
  document_.clear();
  seen_active_ = false;
  last_playing_ = false;
  playing_videos_.clear();
  played_before_hidden_ = false;
}

void PageMedia::VisibilityChanged(bool visible) {
  played_before_hidden_ = !visible && !playing_videos_.empty();
}

void PageMedia::PictureInPictureChanged(bool active) {
  if (active || leaving_picture_in_picture_) {
    return;
  }
  leaving_picture_in_picture_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<PageMedia> media) {
                       if (media) {
                         media->leaving_picture_in_picture_ = false;
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

void PageMedia::SharedChanged(bool shared) {
  // A page the engine followed anew after the sharing began has no share
  // of it to end.
  shares_ = std::max(0, shares_ + (shared ? 1 : -1));
  changed_.Run();
}

void PageMedia::SharingChanged(bool sharing) {
  sharing_ = std::max(0, sharing_ + (sharing ? 1 : -1));
  changed_.Run();
}

// A video's return control closes its window and then asks for the page, in
// one task; a document's asks while its window is still open. An ask for a
// page whose video still floats is someone else's, such as an extension
// focusing the window.
bool PageMedia::ReturnsFromPictureInPicture() const {
  return leaving_picture_in_picture_ || contents_->HasPictureInPictureDocument();
}

// The browser's Media Session chooses the active video player and asks its
// renderer to enter Picture in Picture; no page gesture is synthesized.
bool PageMedia::EnterPictureInPicture() {
  if ((!played_before_hidden_ && playing_videos_.empty() && !last_playing_ &&
       contents_->GetCurrentlyPlayingVideoCount() == 0) ||
      contents_->HasPictureInPictureVideo() || contents_->HasPictureInPictureDocument()) {
    return false;
  }
  auto* session = content::MediaSession::GetIfExists(contents_);
  if (!session) {
    return false;
  }
  session->EnterPictureInPicture();
  return true;
}

// The engine's window manager closes the Picture in Picture window, and the
// video goes back to its element and keeps playing. It keeps one window for
// every page, so the page asks only while that window is its own.
bool PageMedia::ExitPictureInPicture() {
  if (!contents_->HasPictureInPictureVideo() && !contents_->HasPictureInPictureDocument()) {
    return false;
  }
  content::MediaSession::Get(contents_)->ExitPictureInPicture();
  return true;
}

bool PageMedia::Activate(const std::string& document) {
  if (document.empty() || document.size() > kDocumentLength) {
    return false;
  }
  document_ = document;
  Publish();
  return true;
}

bool PageMedia::Perform(const std::string& document, engine::MediaSessionAction action) {
  if (document.empty() || document != document_) {
    return false;
  }
  auto* session = content::MediaSession::Get(contents_);
  if (!session) {
    return false;
  }
  using SuspendType = media_session::mojom::MediaSession::SuspendType;
  switch (action) {
    case engine::MediaSessionAction::kPlay:
      session->Resume(SuspendType::kUI);
      break;
    case engine::MediaSessionAction::kPause:
      session->Suspend(SuspendType::kUI);
      break;
    case engine::MediaSessionAction::kPreviousTrack:
      session->PreviousTrack();
      break;
    case engine::MediaSessionAction::kNextTrack:
      session->NextTrack();
      break;
  }
  return true;
}

bool PageMedia::Mute(const std::string& document, bool muted) {
  if (document.empty() || document != document_) {
    return false;
  }
  contents_->SetAudioMuted(muted);
  return true;
}

bool PageMedia::ObserveSpectrum(bool observed) {
  if (!observed) {
    spectrum_.reset();
  } else if (!spectrum_) {
    spectrum_ = std::make_unique<AudioSpectrumTap>(
        contents_->GetAudioGroupId(),
        base::BindRepeating(&PageMedia::SpectrumMeasured, weak_factory_.GetWeakPtr()));
  }
  return true;
}

void PageMedia::SpectrumMeasured(engine::Bytes bands) {
  if (spectrum_) {
    present_.Run(engine::AudioSpectrumChanged{.page_id = page_, .bands = std::move(bands)});
  }
}

void PageMedia::MediaSessionInfoChanged(media_session::mojom::MediaSessionInfoPtr info) {
  info_ = std::move(info);
  Publish();
}

void PageMedia::MediaSessionMetadataChanged(const std::optional<media_session::MediaMetadata>& metadata) {
  metadata_ = metadata;
  Publish();
}

void PageMedia::MediaSessionActionsChanged(const std::vector<media_session::mojom::MediaSessionAction>& actions) {
  actions_ = actions;
  Publish();
}

// The page named its artwork. The engine picks the image that best fits the
// size Crest keeps and fetches it; until it arrives the session shows none.
void PageMedia::MediaSessionImagesChanged(
    const base::flat_map<media_session::mojom::MediaSessionImageType, std::vector<media_session::MediaImage>>&
        images) {
  std::optional<media_session::MediaImage> picked;
  if (auto artwork = images.find(media_session::mojom::MediaSessionImageType::kArtwork); artwork != images.end()) {
    picked = media_session::MediaImageManager(kArtworkMinimumPixels, kArtworkPixels).SelectImage(artwork->second);
  }
  if (picked == artwork_image_) {
    return;
  }
  artwork_image_ = std::move(picked);
  ++artwork_generation_;
  const bool showed_artwork = artwork_.has_value();
  artwork_.reset();
  if (artwork_image_) {
    if (auto* session = content::MediaSession::GetIfExists(contents_)) {
      session->GetMediaImageBitmap(
          *artwork_image_, kArtworkMinimumPixels, kArtworkPixels,
          base::BindOnce(&PageMedia::ArtworkLoaded, weak_factory_.GetWeakPtr(), artwork_generation_));
    }
  }
  if (showed_artwork) {
    Publish();
  }
}

void PageMedia::ArtworkLoaded(uint64_t generation, const SkBitmap& bitmap) {
  if (generation != artwork_generation_ || bitmap.drawsNothing()) {
    return;
  }
  artwork_ = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, /*discard_transparency=*/false);
  if (artwork_) {
    Publish();
  }
}

void PageMedia::MediaSessionPositionChanged(const std::optional<media_session::MediaPosition>&) {}

void PageMedia::Publish() {
  changed_.Run();
  if (document_.empty()) {
    return;
  }
  using SessionState = media_session::mojom::MediaSessionInfo::SessionState;
  const bool engine_active = info_ && info_->state != SessionState::kInactive;
  if (engine_active) {
    seen_active_ = true;
    last_playing_ = info_->playback_state == media_session::mojom::MediaPlaybackState::kPlaying;
  }
  const bool active = engine_active || (info_ && seen_active_ && contents_->IsAudioMuted());
  engine::MediaSessionChanged session{
      .page_id = page_,
      .document = document_,
      .sequence = ++sequence_,
      .location = PresentedURL(contents_->GetLastCommittedURL()),
      .active = active,
      // While muted the engine reports no playback; the last state it did
      // report stands.
      .playback = !active        ? engine::MediaPlayback::kNone
                  : last_playing_ ? engine::MediaPlayback::kPlaying
                                  : engine::MediaPlayback::kPaused,
      .audible = contents_->IsCurrentlyAudible(),
      .muted = contents_->IsAudioMuted(),
  };
  if (metadata_) {
    session.title = Text(metadata_->title);
    session.artist = Text(metadata_->artist);
    session.album = Text(metadata_->album);
  }
  session.artwork = artwork_;
  for (auto action : actions_) {
    switch (action) {
      case media_session::mojom::MediaSessionAction::kPlay:
        session.actions.push_back(engine::MediaSessionAction::kPlay);
        break;
      case media_session::mojom::MediaSessionAction::kPause:
        session.actions.push_back(engine::MediaSessionAction::kPause);
        break;
      case media_session::mojom::MediaSessionAction::kPreviousTrack:
        session.actions.push_back(engine::MediaSessionAction::kPreviousTrack);
        break;
      case media_session::mojom::MediaSessionAction::kNextTrack:
        session.actions.push_back(engine::MediaSessionAction::kNextTrack);
        break;
      default:
        break;
    }
  }
  present_.Run(std::move(session));
}

}  // namespace crest
