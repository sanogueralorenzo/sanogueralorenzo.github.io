#include "chrome/browser/ui/crest/crest_engine_inspector.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/geometry/rect.h"

namespace crest {

namespace {

engine::PageArea Area(const gfx::Rect& rect) {
  return engine::PageArea{.x = static_cast<double>(rect.x()),
                          .y = static_cast<double>(rect.y()),
                          .width = static_cast<double>(rect.width()),
                          .height = static_cast<double>(rect.height())};
}

}  // namespace

PageInspector::PageInspector(content::WebContents* inspected, const engine::Guid& page, Present present, Dock dock)
    : inspected_(inspected), page_(page), present_(std::move(present)), dock_(std::move(dock)) {}

PageInspector::~PageInspector() {
  if (docked_) {
    dock_.Run(nullptr);
  }
}

// DevToolsToggleAction is the only public way to choose a starting panel, and
// it covers Console and Elements. Network has no toggle action and the
// frontend's panel parameter is private to DevToolsWindow, so Network opens
// the inspector wherever it was.
bool PageInspector::Open(std::optional<engine::InspectorPanel> panel) {
  DevToolsToggleAction action = DevToolsToggleAction::Show();
  DevToolsOpenedByAction opened_by = DevToolsOpenedByAction::kMainMenuOrMainShortcut;
  if (panel == engine::InspectorPanel::kConsole) {
    action = DevToolsToggleAction::ShowConsolePanel();
    opened_by = DevToolsOpenedByAction::kConsoleShortcut;
  } else if (panel == engine::InspectorPanel::kElements) {
    action = DevToolsToggleAction::ShowElementsPanel();
  }
  DevToolsWindow::OpenDevToolsWindow(inspected_, action, opened_by);
  return true;
}

// Closing the frontend contents is the one path that covers both states: a
// docked frontend is its own delegate and tears the inspector down from
// there, and an undocked one takes the route its window's close takes. The
// browser's own toggle cannot be used instead — it acts on whichever tab is
// active, which is not necessarily this page.
bool PageInspector::Close() {
  auto* inspector = DevToolsWindow::GetInstanceForInspectedWebContents(inspected_);
  content::WebContents* frontend = inspector ? inspector->GetDevToolsWebContents() : nullptr;
  if (!frontend) {
    return false;
  }
  frontend->Close();
  return true;
}

bool PageInspector::IsOpen() const {
  return DevToolsWindow::GetInstanceForInspectedWebContents(inspected_) != nullptr;
}

// The frontend takes the whole card and the page is drawn over it at the
// area the frontend asked for, which is how its own dock side, splitter
// position and drawer height reach the card.
engine::InspectorLayout PageInspector::Layout(double width, double height) const {
  if (!docked_ || width <= 0 || height <= 0) {
    return engine::InspectorLayout{};
  }
  gfx::Rect frontend;
  gfx::Rect page;
  ApplyDevToolsContentsResizingStrategy(strategy_,
                                        gfx::Rect(0, 0, static_cast<int>(width), static_cast<int>(height)),
                                        &frontend, &page);
  return engine::InspectorLayout{.inspector = Area(frontend), .page = Area(page)};
}

void PageInspector::Update() {
  auto* inspector = DevToolsWindow::GetInstanceForInspectedWebContents(inspected_);
  DevToolsContentsResizingStrategy strategy;
  // Only a docked frontend belongs in the card. An undocked window also offers
  // its device-emulation container for the inspected page, which Crest does
  // not show: the card keeps showing the page.
  content::WebContents* frontend =
      inspector && inspector->IsDocked() ? DevToolsWindow::GetInTabWebContents(inspected_, &strategy) : nullptr;
  if (!frontend) {
    if (inspector && !inspector->IsDocked()) {
      if (content::WebContents* undocked = inspector->GetDevToolsWebContents()) {
        undocked_ = undocked->GetWeakPtr();
      }
    }
    // Nothing is docked any more: the inspector closed, or the person undocked
    // it and the engine took the frontend into a window of its own.
    if (!docked_) {
      return;
    }
    docked_.reset();
    dock_.Run(nullptr);
  } else if (undocked_.get() == frontend) {
    // The person docked the window they had undocked. That frontend can no
    // longer draw outside Views, so it is replaced with a fresh docked one.
    undocked_.reset();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<content::WebContents> inspected, base::WeakPtr<content::WebContents> stale) {
                         if (stale) {
                           stale->Close();
                         }
                         if (inspected) {
                           DevToolsWindow::OpenDevToolsWindow(inspected.get(), DevToolsToggleAction::Show(),
                                                              DevToolsOpenedByAction::kMainMenuOrMainShortcut);
                         }
                       },
                       inspected_->GetWeakPtr(), frontend->GetWeakPtr()));
    return;
  } else {
    if (docked_.get() != frontend) {
      docked_ = frontend->GetWeakPtr();
      dock_.Run(frontend);
    }
    strategy_.CopyFrom(strategy);
  }
  present_.Run(engine::InspectorLayoutChanged{.page_id = page_});
}

void PageInspector::Closing() {
  present_.Run(engine::InspectorClosed{.page_id = page_});
}

}  // namespace crest
