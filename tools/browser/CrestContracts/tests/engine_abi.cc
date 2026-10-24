// A C++ engine binding against the actual core library, through the generated
// C++ codec alone: it registers with the codec's fingerprint, decodes the
// commands the core issues and reports every engine event the core reads.
// Chromium's binding speaks the same codec, so this proves the two agree
// without building Chromium.
#include "crest_app.h"
#include "crest_contracts.h"
#include "crest_engine.h"
#include "crest_engine_contract.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace {

namespace engine = crest::engine;

// A binding under test: what attach handed it and the commands it ran.
struct Binding {
  uint64_t app = 0;
  uint64_t engine = 0;
  crest_engine_report_t report = nullptr;
  crest_engine_ask_t ask = nullptr;
  std::vector<engine::EngineCommand> commands;
};

void CREST_CALL Attach(void* context, uint64_t app, uint64_t engine_handle, crest_engine_report_t report,
                       crest_engine_ask_t ask) {
  auto* binding = static_cast<Binding*>(context);
  binding->app = app;
  binding->engine = engine_handle;
  binding->report = report;
  binding->ask = ask;
}

void CREST_CALL Run(void* context, const uint8_t* bytes, size_t length) {
  auto command = engine::Decode<engine::EngineCommand>(bytes, length);
  assert(command.has_value());
  static_cast<Binding*>(context)->commands.push_back(std::move(*command));
}

crest_status_t Report(const Binding& binding, const engine::EngineEvent& event) {
  const std::vector<uint8_t> bytes = engine::Encode(event);
  return binding.report(binding.app, binding.engine, bytes.data(), bytes.size());
}

// Keeps the encoded answer the core handed back.
void CREST_CALL Received(void* context, const uint8_t* bytes, size_t length) {
  static_cast<std::vector<uint8_t>*>(context)->assign(bytes, bytes + length);
}

// What the core answered `question`, or nothing when it could not.
template <typename Question>
std::optional<typename engine::EngineQuestionAnswer<Question>::Type> Ask(const Binding& binding, const Question& question) {
  const std::vector<uint8_t> bytes = engine::Encode(engine::EngineQuestion{question});
  std::vector<uint8_t> answer;
  if (binding.ask(binding.app, binding.engine, bytes.data(), bytes.size(), Received, &answer) != CREST_OK) {
    return std::nullopt;
  }
  return engine::Decode<typename engine::EngineQuestionAnswer<Question>::Type>(answer.data(), answer.size());
}

engine::Guid Filled(uint8_t value) {
  engine::Guid guid;
  guid.fill(value);
  return guid;
}

std::vector<uint8_t> Drained(uint64_t app) {
  crest_buffer_t buffer = {nullptr, 0};
  assert(crest_app_drain(app, &buffer) == CREST_OK);
  std::vector<uint8_t> bytes(buffer.bytes, buffer.bytes + buffer.length);
  crest_buffer_free(&buffer);
  return bytes;
}

std::vector<uint8_t> Dispatched(uint64_t app, const std::vector<uint8_t>& intent) {
  crest_buffer_t buffer = {nullptr, 0};
  assert(crest_app_dispatch(app, intent.data(), intent.size(), &buffer) == CREST_OK);
  std::vector<uint8_t> bytes(buffer.bytes, buffer.bytes + buffer.length);
  crest_buffer_free(&buffer);
  return bytes;
}

// A fixed set member or an enum of the application contract, which the
// engine codec does not name: its tag.
struct Member {
  uint32_t tag;
};
void Write(engine::WireWriter& writer, Member member) { writer.WriteVarint(member.tag); }

// A SessionState seed, as a platform sends a record the core resolves values
// of: its fields alone. One Space (all 0x44) with its profile (all 0x55),
// named Reading, with no tabs and its accent's legacy look, and nothing else.
struct SessionSeed {};
void Write(engine::WireWriter& writer, SessionSeed) {
  using engine::Write;
  writer.WriteVarint(1);
  Write(writer, Filled(0x44));
  Write(writer, Filled(0x55));
  Write(writer, std::string("Reading"));
  Write(writer, std::string("book"));
  // The first accent, and no branding, so the accent's legacy look.
  writer.WriteVarint(0);
  Write(writer, false);
  // No engine chosen, no custom engine, no custom providers and no suggestions;
  // its own search and suggestions, not the device's defaults; then the first
  // tab cleanup, content blocking, and history, archive and download retention.
  Write(writer, false);
  Write(writer, false);
  writer.WriteVarint(0);
  Write(writer, false);
  Write(writer, false);
  Write(writer, false);
  for (int member = 0; member < 5; member++) writer.WriteVarint(0);
  // Offers to save passwords and sync them, not to the system's; open; saved
  // tabs expanded and never collapsed; nobody chose whether it uses Crest
  // Passwords, or its lock.
  Write(writer, true);
  Write(writer, true);
  Write(writer, false);
  writer.WriteVarint(0);
  Write(writer, true);
  Write(writer, false);
  Write(writer, false);
  Write(writer, false);
  // No folders, tabs, splits, archived tabs or history; no default Space,
  // seed marker, Space deletion or app preferences.
  for (int list = 0; list < 5; list++) writer.WriteVarint(0);
  Write(writer, false);
  Write(writer, false);
  writer.WriteVarint(0);
  Write(writer, false);
}

// An intent spelled with the codec's writer: its tag, then its fields.
template <typename... Fields>
std::vector<uint8_t> Intent(uint32_t tag, const Fields&... fields) {
  using engine::Write;
  engine::WireWriter writer;
  writer.WriteVarint(tag);
  (Write(writer, fields), ...);
  return writer.Take();
}

// Every event the core reads survives the codec unchanged, and a message
// that is cut short, runs on, or holds a string that is not UTF-8 decodes to
// nothing.
void CodecRoundTrips() {
  const engine::Guid page = Filled(0x61);
  const engine::SiteOrigin maps{.scheme = "https", .host = "maps.example", .port = 443};
  const std::vector<engine::EngineEvent> events = {
      engine::AuthenticationChallenged{.prompt_id = Filled(0x71),
                                       .page_id = page,
                                       .question = {.url = "https://intranet.example/",
                                                    .host = "intranet.example",
                                                    .port = 443,
                                                    .realm = "Staff",
                                                    .scheme = engine::AuthenticationScheme::kDigest,
                                                    .previous_failures = 1}},
      engine::BeforeUnloadAnswered{.page_id = page, .proceeds = true},
      engine::DataErased{.erasure_id = Filled(0x7a), .erased = true},
      engine::EngineDownloadChanged{.download = {.download_id = "7",
                                                 .profile_id = Filled(0x76),
                                                 .source_page_id = page,
                                                 .filename = "report.pdf",
                                                 .received = 50,
                                                 .total = 100,
                                                 .state = engine::EngineDownloadState::kAwaitingApproval,
                                                 .warning = engine::EngineDownloadWarning::kDangerousFile,
                                                 .approval_token = "3:0"}},
      engine::EngineDownloadDestinationRequested{.prompt_id = Filled(0x77),
                                                 .download = {.download_id = "8", .profile_id = Filled(0x76)},
                                                 .suggested_filename = "report.pdf",
                                                 .forces_prompt = true,
                                                 .facts = {.suggested_filename = "report.pdf",
                                                           .sanitized_filename = "report.pdf",
                                                           .mime_type = "application/pdf",
                                                           .types_related = true},
                                                 .user_initiated = true,
                                                 .source_host = "files.example"},
      engine::ExtensionInstallRequested{.prompt_id = Filled(0x72),
                                        .window_id = Filled(0x73),
                                        .question = {.extension_id = "abcdefghijklmnopabcdefghijklmnop",
                                                     .name = "Reader",
                                                     .version = "1.0",
                                                     .summary = "Reads.",
                                                     .permissions = {"Read your history"},
                                                     .icon = engine::Bytes{0x89, 0x50},
                                                     .can_withhold_site_access = true}},
      engine::NavigationCommitted{.page_id = page, .url = "https://example.com/a", .same_document = true},
      engine::NavigationFailed{.page_id = page,
                               .failure = {.error = engine::NavigationError::kCannotFindServer,
                                           .url = "https://missing.example/",
                                           .replaced_document = true,
                                           .domain = "net",
                                           .code = -105}},
      engine::NavigationFinished{.page_id = page, .url = "https://example.com/a", .title = "Caf\xc3\xa9"},
      engine::NavigationStarted{.page_id = page, .url = "https://example.com/b"},
      engine::PageCloseRequested{.page_id = page},
      engine::PageClosed{.page_id = page,
                         .restore_state = engine::PageRestoreState{.url = "https://example.com/a", .state = {0x01, 0x02}}},
      engine::PageCrashed{.page_id = page, .domain = "ChromiumTerminationStatus", .code = 3},
      engine::PageCreated{.page_id = page},
      engine::PageCreationFailed{.page_id = page},
      engine::PageGroupChanged{.group_id = Filled(0x79),
                               .window_id = Filled(0x73),
                               .title = "Research",
                               .color = engine::TabGroupColor::kOrange,
                               .is_collapsed = true,
                               .page_ids = {page}},
      engine::PageHistoryReported{.page_id = page,
                                  .entries = {{.id = Filled(0x7c), .url = "https://example.com/a", .title = "A"},
                                              {.id = Filled(0x7d), .url = "https://example.com/", .title = "Example"}},
                                  .current = 1},
      engine::PageIconChanged{.page_id = page, .url = "https://example.com/", .accent = engine::TabIconAccent{0.25, 0.5, 1}},
      engine::PageOffered{.offer_id = Filled(0x78),
                          .profile_id = Filled(0x76),
                          .source_page_id = page,
                          .window_id = Filled(0x73),
                          .space_id = std::nullopt,
                          .url = "https://example.com/popup",
                          .foreground = true},
      engine::PageStateChanged{.page_id = page,
                               .snapshot = {.url = "https://example.com/",
                                            .pending_url = std::nullopt,
                                            .title = "Example",
                                            .is_loading = true,
                                            .security = engine::PageSecurity::kMixedContent,
                                            .media = engine::PageMediaActivity::kPlaying |
                                                     engine::PageMediaActivity::kPictureInPicture}},
      engine::PermissionRequested{.prompt_id = Filled(0x74),
                                  .page_id = page,
                                  .question = {.permission = engine::SitePermission::kLocation,
                                               .origin = maps,
                                               .top_level_origin = maps}},
      engine::PictureInPictureReturned{.page_id = page},
      engine::PromptWithdrawn{.prompt_id = Filled(0x74)},
      engine::ProtectedMediaUnavailable{.page_id = page, .key_system = engine::KeySystem::kPlayReady},
      engine::ScriptDialogOpened{.prompt_id = Filled(0x75),
                                 .page_id = page,
                                 .question = {.kind = engine::JavaScriptDialogKind::kBeforeUnload,
                                              .source_url = "https://example.com/"}},
      engine::StagedLinkUnavailable{.page_id = page},
  };
  for (size_t tag = 0; tag < events.size(); ++tag) {
    assert(events[tag].index() == tag);
    std::vector<uint8_t> bytes = engine::Encode(events[tag]);
    assert(bytes[0] == tag);
    assert(engine::Decode<engine::EngineEvent>(bytes.data(), bytes.size()) == events[tag]);
    assert(!engine::Decode<engine::EngineEvent>(bytes.data(), bytes.size() - 1));
    bytes.push_back(0);
    assert(!engine::Decode<engine::EngineEvent>(bytes.data(), bytes.size()));
  }
  std::vector<uint8_t> finished = engine::Encode(events[CREST_ENGINE_EVENT_NAVIGATION_FINISHED]);
  finished[finished.size() - 2] = 0xff;  // The title's é, no longer UTF-8.
  assert(!engine::Decode<engine::EngineEvent>(finished.data(), finished.size()));
  const uint8_t overlong[] = {0x80, 0x00};
  assert(!engine::Decode<engine::EngineEvent>(overlong, sizeof(overlong)));
  const uint8_t unknown[] = {CREST_ENGINE_EVENT_STAGED_LINK_UNAVAILABLE + 1};
  assert(!engine::Decode<engine::EngineEvent>(unknown, sizeof(unknown)));
}

void EngineBoundary() {
  const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
  const uint8_t engine_fingerprint[CREST_ENGINE_CONTRACT_FINGERPRINT_LENGTH] = CREST_ENGINE_CONTRACT_FINGERPRINT;
  static_assert(sizeof(engine_fingerprint) == engine::kFingerprint.size());
  assert(std::memcmp(engine_fingerprint, engine::kFingerprint.data(), sizeof(engine_fingerprint)) == 0);
  // AppConfiguration(StorageDirectory: null, Platform: Desktop, ImportNames: null).
  const uint8_t memory_only[] = {0, 0, 0};
  uint64_t app = 0;
  crest_buffer_t buffer = {nullptr, 0};
  assert(crest_app_create(fingerprint, sizeof(fingerprint), memory_only, sizeof(memory_only), &app, &buffer) == CREST_OK);

  Binding binding;
  const crest_engine_binding_t table = {&binding, Attach, Run};
  const std::vector<uint8_t> registration = engine::Encode(engine::EngineRegistration{
      .kind = engine::EngineKind::kChromium,
      .capabilities = {engine::EngineCapability::kPages, engine::EngineCapability::kNavigation,
                       engine::EngineCapability::kWorkspaceProfiles, engine::EngineCapability::kProfileDeletion},
      .is_default = true});
  uint64_t handle = 0;
  assert(crest_engine_register(app, engine::kFingerprint.data(), engine::kFingerprint.size(), registration.data(),
                               registration.size(), &table, &handle, &buffer) == CREST_OK);
  assert(handle != 0 && binding.engine == handle && binding.app == app && binding.report == crest_engine_report &&
         binding.ask == crest_engine_ask);
  Drained(app);

  // A workspace opened from a seed, with a window open over it.
  // OpenWorkspace: WorkspaceKind.Persistent, then the seed.
  const std::vector<uint8_t> opened =
      Dispatched(app, Intent(CREST_INTENT_OPEN_WORKSPACE, Member{0}, std::optional<SessionSeed>(SessionSeed{})));
  assert(opened[0] == 1 && opened[1] == CREST_CHANGE_WORKSPACE_OPENED);
  engine::Guid workspace;
  std::memcpy(workspace.data(), opened.data() + 2, 16);
  const engine::Guid window = Filled(0x42);
  // OpenWindow: not saved, nothing to copy or show, no tabs, RestoresTabs.
  Dispatched(app, Intent(CREST_INTENT_OPEN_WINDOW, window, workspace, false, std::optional<engine::Guid>(),
                         std::optional<engine::Guid>(), std::vector<engine::Guid>(), true));

  // OpenPage for a transient request, with no transient presentation and no
  // opener: the binding creates it in its window.
  const engine::Guid page = Filled(0x61);
  Dispatched(app, Intent(CREST_INTENT_OPEN_PAGE, page, workspace, Filled(0x44), std::optional<engine::Guid>(), window,
                         std::optional<Member>(), std::optional<engine::Guid>()));
  assert(binding.commands.size() == 1);
  const auto& creation = std::get<engine::CreatePage>(binding.commands[0]);
  assert(creation.page_id == page && creation.profile_id == Filled(0x55) && !creation.is_private &&
         creation.window_id == window);

  // Every event the binding reports decodes in the core.
  assert(Report(binding, engine::PageCreated{.page_id = page}) == CREST_OK);
  Dispatched(app, Intent(CREST_INTENT_NAVIGATE, page, std::string("https://example.com/")));
  assert(binding.commands.size() == 2);
  assert(std::get<engine::LoadPage>(binding.commands[1]).url == "https://example.com/");
  const std::string url = "https://example.com/";
  assert(Report(binding, engine::NavigationStarted{.page_id = page, .url = url}) == CREST_OK);
  assert(Report(binding, engine::NavigationCommitted{.page_id = page, .url = url}) == CREST_OK);
  assert(Report(binding, engine::PageStateChanged{
      .page_id = page, .snapshot = {.url = url, .title = "Example", .security = engine::PageSecurity::kSecure}}) == CREST_OK);
  assert(Report(binding, engine::PageIconChanged{.page_id = page, .url = url, .accent = engine::TabIconAccent{1, 0, 0}}) ==
         CREST_OK);
  assert(Report(binding, engine::NavigationFinished{.page_id = page, .url = url, .title = "Example"}) == CREST_OK);
  assert(Report(binding, engine::NavigationFailed{
      .page_id = page, .failure = {.error = engine::NavigationError::kOffline, .url = url, .domain = "net", .code = -106}}) ==
      CREST_OK);
  const std::vector<uint8_t> drained = Drained(app);
  assert(!drained.empty() && drained[0] > 0);

  // The binding asks what a click on a link does while its engine waits: a
  // plain click in a page without a tab loads in the page.
  const auto followed = Ask(binding, engine::LinkActivation{
      .page_id = page, .url = "https://example.com/next", .gesture = {.user_activated = true, .top_level = true}});
  assert(followed && followed->decision == engine::LinkNavigationDecision::kNavigate);
  // A page a page without a tab opened stays in it: the core closes the offer
  // and the page loads its address.
  const engine::Guid offer = Filled(0x62);
  assert(Report(binding, engine::PageOffered{.offer_id = offer,
                                             .profile_id = Filled(0x55),
                                             .source_page_id = page,
                                             .window_id = window,
                                             .url = "https://example.com/popup",
                                             .foreground = true}) == CREST_OK);
  assert(binding.commands.size() == 4);
  assert(std::get<engine::RejectOfferedPage>(binding.commands[2]).offer_id == offer);
  assert(std::get<engine::LoadPage>(binding.commands[3]).url == "https://example.com/popup");

  // The page's release closes what the engine holds.
  Dispatched(app, Intent(CREST_INTENT_RELEASE_PAGE, page, false));
  assert(binding.commands.size() == 5);
  assert(std::get<engine::ClosePage>(binding.commands[4]) == (engine::ClosePage{.page_id = page}));
  assert(Report(binding, engine::PageClosed{.page_id = page}) == CREST_OK);

  // A report that does not decode is malformed, never a rejection.
  const uint8_t garbage[] = {0x7f, 0x01};
  assert(binding.report(app, handle, garbage, sizeof(garbage)) == CREST_INVALID_MESSAGE);
  std::vector<uint8_t> unanswered;
  assert(binding.ask(app, handle, garbage, sizeof(garbage), Received, &unanswered) == CREST_INVALID_MESSAGE &&
         unanswered.empty());
  assert(crest_engine_unregister(app, handle) == CREST_OK);
  assert(crest_app_destroy(app) == CREST_OK);
}

}  // namespace

int main() {
  CodecRoundTrips();
  EngineBoundary();
  std::puts("C++ engine codec and binding checks passed.");
  return 0;
}
