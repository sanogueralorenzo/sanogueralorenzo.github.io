// Android-like LiteRT-LM evaluator for prompt benchmarking on desktop.
// Matches app defaults: sampler profile level 0, max_num_tokens=224, and
// GPU->CPU backend fallback.

#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include <cctype>

#include "absl/base/log_severity.h"  // from @com_google_absl
#include "absl/flags/flag.h"  // from @com_google_absl
#include "absl/flags/parse.h"  // from @com_google_absl
#include "absl/log/absl_check.h"  // from @com_google_absl
#include "absl/log/absl_log.h"  // from @com_google_absl
#include "absl/log/globals.h"  // from @com_google_absl
#include "absl/status/status.h"  // from @com_google_absl
#include "absl/status/statusor.h"  // from @com_google_absl
#include "nlohmann/json.hpp"  // from @nlohmann_json
#include "runtime/conversation/conversation.h"
#include "runtime/conversation/io_types.h"
#include "runtime/engine/engine_factory.h"
#include "runtime/engine/engine_settings.h"
#include "runtime/engine/io_types.h"
#include "runtime/proto/sampler_params.pb.h"
#include "runtime/util/status_macros.h"

ABSL_FLAG(std::string, model_path, "", "Path to the .litertlm model file.");
ABSL_FLAG(std::string, backend, "auto", "Backend: auto|gpu|cpu");
ABSL_FLAG(std::string, input_prompt, "", "Input prompt text.");
ABSL_FLAG(std::string, input_prompt_file, "", "Input prompt file path.");
ABSL_FLAG(std::string, system_instruction, "", "System instruction text.");
ABSL_FLAG(std::string, system_instruction_file, "",
          "System instruction file path.");
ABSL_FLAG(int, max_num_tokens, 224,
          "Max context/output token budget (Android default: 224).");
ABSL_FLAG(int, top_k, 1, "Sampler top-k (Android style level 0).");
ABSL_FLAG(double, top_p, 1.0, "Sampler top-p (Android style level 0).");
ABSL_FLAG(double, temperature, 0.0,
          "Sampler temperature (Android style level 0).");
ABSL_FLAG(int, seed, 42, "Sampler seed (Android style level 0).");

namespace {

using ::litert::lm::Backend;
using ::litert::lm::Conversation;
using ::litert::lm::ConversationConfig;
using ::litert::lm::EngineSettings;
using ::litert::lm::JsonMessage;
using ::litert::lm::JsonPreface;
using ::litert::lm::Message;
using ::litert::lm::ModelAssets;
using ::nlohmann::json;

absl::StatusOr<std::string> ReadTextFromFlagOrFile(
    const std::string& text,
    const std::string& file_path,
    const std::string& field_name) {
  if (!text.empty() && !file_path.empty()) {
    return absl::InvalidArgumentError(
        "Only one of --" + field_name + " and --" + field_name +
        "_file may be specified.");
  }

  if (!text.empty()) {
    return text;
  }

  if (file_path.empty()) {
    return std::string();
  }

  std::ifstream file(file_path);
  if (!file.is_open()) {
    return absl::InvalidArgumentError("Could not open file: " + file_path);
  }
  std::stringstream buffer;
  buffer << file.rdbuf();
  return buffer.str();
}

absl::StatusOr<std::vector<Backend>> ResolveBackends(const std::string& backend) {
  std::string normalized = backend;
  for (char& c : normalized) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  if (normalized == "auto") {
    return std::vector<Backend>{Backend::GPU, Backend::CPU};
  }

  ASSIGN_OR_RETURN(auto single_backend,
                   litert::lm::GetBackendFromString(normalized));
  return std::vector<Backend>{single_backend};
}

std::string ExtractText(const Message& message) {
  const auto* json_message = std::get_if<JsonMessage>(&message);
  if (json_message == nullptr || json_message->is_null()) {
    return "";
  }

  std::string output;
  if (json_message->contains("content") && (*json_message)["content"].is_array()) {
    for (const auto& content : (*json_message)["content"]) {
      if (content.contains("type") && content["type"] == "text" &&
          content.contains("text") && content["text"].is_string()) {
        output += content["text"].get<std::string>();
      }
    }
  }
  return output;
}

absl::StatusOr<std::string> RunSingleInference(const std::string& model_path,
                                               Backend backend,
                                               const std::string& system_instruction,
                                               const std::string& input_prompt) {
  ASSIGN_OR_RETURN(ModelAssets model_assets, ModelAssets::Create(model_path));
  ASSIGN_OR_RETURN(EngineSettings engine_settings,
                   EngineSettings::CreateDefault(std::move(model_assets), backend));

  engine_settings.GetMutableMainExecutorSettings().SetMaxNumTokens(
      absl::GetFlag(FLAGS_max_num_tokens));

  ASSIGN_OR_RETURN(auto engine,
                   litert::lm::EngineFactory::CreateAny(std::move(engine_settings)));

  auto session_config = litert::lm::SessionConfig::CreateDefault();
  auto& sampler = session_config.GetMutableSamplerParams();
  sampler.set_type(litert::lm::proto::SamplerParameters::TOP_P);
  sampler.set_k(absl::GetFlag(FLAGS_top_k));
  sampler.set_p(static_cast<float>(absl::GetFlag(FLAGS_top_p)));
  sampler.set_temperature(static_cast<float>(absl::GetFlag(FLAGS_temperature)));
  sampler.set_seed(absl::GetFlag(FLAGS_seed));

  auto builder = ConversationConfig::Builder();
  builder.SetSessionConfig(session_config);

  if (!system_instruction.empty()) {
    JsonPreface preface;
    preface.messages = json::array();
    preface.tools = json::array();
    preface.extra_context = json::object();

    json system_content = json::array();
    json system_text_part = json::object();
    system_text_part["type"] = "text";
    system_text_part["text"] = system_instruction;
    system_content.push_back(system_text_part);

    json system_message = json::object();
    system_message["role"] = "system";
    system_message["content"] = system_content;
    preface.messages.push_back(system_message);

    builder.SetPreface(preface);
  }

  ASSIGN_OR_RETURN(auto conversation_config, builder.Build(*engine));
  ASSIGN_OR_RETURN(auto conversation,
                   Conversation::Create(*engine, conversation_config));

  json user_content = json::array();
  user_content.push_back(json::object({{"type", "text"}, {"text", input_prompt}}));

  ASSIGN_OR_RETURN(auto model_message,
                   conversation->SendMessage(
                       json::object({{"role", "user"}, {"content", user_content}})));

  return ExtractText(model_message);
}

absl::Status MainHelper(int argc, char** argv) {
  absl::ParseCommandLine(argc, argv);
  absl::SetMinLogLevel(absl::LogSeverityAtLeast::kError);
  absl::SetStderrThreshold(absl::LogSeverityAtLeast::kFatal);

  const std::string model_path = absl::GetFlag(FLAGS_model_path);
  if (model_path.empty()) {
    return absl::InvalidArgumentError("Model path is empty.");
  }

  ASSIGN_OR_RETURN(
      std::string input_prompt,
      ReadTextFromFlagOrFile(absl::GetFlag(FLAGS_input_prompt),
                             absl::GetFlag(FLAGS_input_prompt_file),
                             "input_prompt"));
  ASSIGN_OR_RETURN(
      std::string system_instruction,
      ReadTextFromFlagOrFile(absl::GetFlag(FLAGS_system_instruction),
                             absl::GetFlag(FLAGS_system_instruction_file),
                             "system_instruction"));

  if (input_prompt.empty()) {
    return absl::InvalidArgumentError("Input prompt is empty.");
  }

  ASSIGN_OR_RETURN(auto backends,
                   ResolveBackends(absl::GetFlag(FLAGS_backend)));

  absl::Status last_error = absl::UnknownError("No backend attempted.");
  for (const auto backend : backends) {
    auto output_or =
        RunSingleInference(model_path, backend, system_instruction, input_prompt);
    if (output_or.ok()) {
      std::cout << *output_or << std::endl;
      return absl::OkStatus();
    }
    last_error = output_or.status();
  }

  return absl::InternalError(
      "All backends failed. Last error: " + std::string(last_error.message()));
}

}  // namespace

int main(int argc, char** argv) {
  ABSL_CHECK_OK(MainHelper(argc, argv));
  return 0;
}
