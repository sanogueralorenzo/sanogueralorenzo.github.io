#include "chrome/browser/ui/crest/crest_engine_documents.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include "base/base64.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "base/values.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"

namespace crest {

namespace {

// The largest full-page image, in CSS pixels, and the largest image width a
// caller may ask for.
constexpr double kMaximumWidth = 6000;
constexpr double kMaximumHeight = 24000;
// The width a full-page image takes when the caller names none.
constexpr double kDefaultWidth = 1600;
// The largest protocol message and exported document the page accepts.
constexpr size_t kMaximumMessageBytes = 96 * 1024 * 1024;
constexpr size_t kMaximumDocumentBytes = 64 * 1024 * 1024;
constexpr base::TimeDelta kTimeout = base::Seconds(45);

}  // namespace

PageDocuments::PageDocuments(content::WebContents* contents) : content::WebContentsObserver(contents) {}

PageDocuments::~PageDocuments() {
  Finish(std::nullopt, engine::PageExportFailure::kClosed);
}

void PageDocuments::Export(engine::PageExportFormat format, double width, Done done) {
  if (done_) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(done), std::optional<std::vector<uint8_t>>(),
                                  std::optional<engine::PageExportFailure>(engine::PageExportFailure::kBusy)));
    return;
  }
  done_ = std::move(done);
  if (!web_contents() || !std::isfinite(width) || width < 0 || width > kMaximumWidth) {
    Finish(std::nullopt, engine::PageExportFailure::kUnsupported);
    return;
  }
  format_ = format;
  width_ = width;
  agent_ = content::DevToolsAgentHost::GetOrCreateFor(web_contents());
  attached_ = agent_ && agent_->AttachClient(this);
  if (!attached_) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  timer_.Start(FROM_HERE, kTimeout,
               base::BindOnce(&PageDocuments::Finish, base::Unretained(this), std::optional<std::vector<uint8_t>>(),
                              std::optional<engine::PageExportFailure>(engine::PageExportFailure::kTimedOut)));
  switch (format) {
    case engine::PageExportFormat::kPdf:
      Send("Page.printToPDF",
           base::DictValue().Set("printBackground", true).Set("preferCSSPageSize", true).Set("generateTaggedPDF", true));
      break;
    case engine::PageExportFormat::kMhtml:
      Send("Page.captureSnapshot", base::DictValue().Set("format", "mhtml"));
      break;
    case engine::PageExportFormat::kPng:
      measuring_ = true;
      Send("Page.getLayoutMetrics", base::DictValue());
      break;
    case engine::PageExportFormat::kWebArchive:
      Finish(std::nullopt, engine::PageExportFailure::kUnsupported);
      break;
  }
}

void PageDocuments::DispatchProtocolMessage(content::DevToolsAgentHost*, base::span<const uint8_t> message) {
  if (!done_) {
    return;
  }
  if (message.size() > kMaximumMessageBytes) {
    Finish(std::nullopt, engine::PageExportFailure::kTooLarge);
    return;
  }
  auto response = base::JSONReader::ReadDict(base::as_string_view(message), base::JSON_PARSE_RFC);
  if (!response || response->FindInt("id") != sequence_) {
    return;
  }
  const auto* result = response->FindDict("result");
  if (!result) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  if (measuring_) {
    measuring_ = false;
    const auto* dimensions = result->FindDict("cssContentSize");
    double width = dimensions ? dimensions->FindDouble("width").value_or(0) : 0;
    double height = dimensions ? dimensions->FindDouble("height").value_or(0) : 0;
    if (!std::isfinite(width) || !std::isfinite(height) || width <= 0 || height <= 0) {
      Finish(std::nullopt, engine::PageExportFailure::kFailed);
      return;
    }
    width = std::min(width, kMaximumWidth);
    height = std::min(height, kMaximumHeight);
    const double target = width_ > 0 ? width_ : std::min(width, kDefaultWidth);
    auto clip = base::DictValue()
                    .Set("x", 0)
                    .Set("y", 0)
                    .Set("width", width)
                    .Set("height", height)
                    .Set("scale", target / width);
    Send("Page.captureScreenshot", base::DictValue()
                                       .Set("format", "png")
                                       .Set("fromSurface", true)
                                       .Set("captureBeyondViewport", true)
                                       .Set("clip", std::move(clip)));
    return;
  }
  const std::string* encoded = result->FindString("data");
  if (!encoded) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  // An archive arrives as its text; a PDF or an image as base64.
  std::optional<std::vector<uint8_t>> document =
      format_ == engine::PageExportFormat::kMhtml ? std::vector<uint8_t>(encoded->begin(), encoded->end())
                                                  : base::Base64Decode(*encoded);
  if (!document || document->empty()) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  if (document->size() > kMaximumDocumentBytes) {
    Finish(std::nullopt, engine::PageExportFailure::kTooLarge);
    return;
  }
  Finish(std::move(document), std::nullopt);
}

void PageDocuments::AgentHostClosed(content::DevToolsAgentHost*) {
  attached_ = false;
  agent_.reset();
  Finish(std::nullopt, engine::PageExportFailure::kClosed);
}

void PageDocuments::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
    Finish(std::nullopt, engine::PageExportFailure::kNavigated);
  }
}

void PageDocuments::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) {
  Finish(std::nullopt, engine::PageExportFailure::kRendererStopped);
}

void PageDocuments::WebContentsDestroyed() {
  Finish(std::nullopt, engine::PageExportFailure::kClosed);
  Observe(nullptr);
}

void PageDocuments::Send(const char* method, base::DictValue params) {
  if (!done_ || !agent_) {
    return;
  }
  auto json = base::WriteJson(
      base::DictValue().Set("id", ++sequence_).Set("method", method).Set("params", std::move(params)));
  if (!json) {
    Finish(std::nullopt, engine::PageExportFailure::kFailed);
    return;
  }
  agent_->DispatchProtocolMessage(this, base::as_byte_span(*json));
}

// Answers on a task of its own: whoever asked may let the page go when it
// hears, and must not do so on the protocol's stack.
void PageDocuments::Finish(std::optional<std::vector<uint8_t>> document,
                           std::optional<engine::PageExportFailure> failure) {
  Done done = std::move(done_);
  measuring_ = false;
  timer_.Stop();
  if (attached_ && agent_) {
    attached_ = false;
    agent_->DetachClient(this);
  }
  agent_.reset();
  if (done) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(done), std::move(document), failure));
  }
}

}  // namespace crest
