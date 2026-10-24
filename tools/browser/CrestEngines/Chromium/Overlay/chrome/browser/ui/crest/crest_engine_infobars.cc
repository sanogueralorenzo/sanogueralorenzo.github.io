#include "chrome/browser/ui/crest/crest_engine_infobars.h"

#include <utility>
#include <vector>

#include "base/strings/utf_string_conversions.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"

namespace crest {

namespace {

ConfirmInfoBarDelegate* Confirming(infobars::InfoBar* bar) {
  return bar && bar->delegate() ? bar->delegate()->AsConfirmInfoBarDelegate() : nullptr;
}

}  // namespace

PageInfoBars::PageInfoBars(content::WebContents* contents, const engine::Guid& page, Present present)
    : page_(page), present_(std::move(present)) {
  manager_ = infobars::ContentInfoBarManager::FromWebContents(contents);
  if (!manager_) {
    return;
  }
  manager_->AddObserver(this);
  // A page the engine offered may already carry bars.
  const std::vector<infobars::InfoBar*> existing(manager_->infobars().begin(), manager_->infobars().end());
  for (auto* bar : existing) {
    Add(bar);
  }
}

PageInfoBars::~PageInfoBars() {
  if (manager_) {
    manager_->RemoveObserver(this);
  }
}

void PageInfoBars::PresentAll() {
  for (const auto& [id, bar] : bars_) {
    Show(id, bar);
  }
}

bool PageInfoBars::Answer(int id, engine::InfoBarAnswer answer) {
  auto found = bars_.find(id);
  if (found == bars_.end() || !found->second->delegate()) {
    return false;
  }
  infobars::InfoBar* bar = found->second;
  auto* confirm = Confirming(bar);
  bool remove = false;
  switch (answer) {
    case engine::InfoBarAnswer::kAccept:
      if (!confirm) {
        return false;
      }
      remove = confirm->Accept();
      break;
    case engine::InfoBarAnswer::kCancel:
      if (!confirm) {
        return false;
      }
      remove = confirm->Cancel();
      break;
    case engine::InfoBarAnswer::kDismiss:
      bar->delegate()->InfoBarDismissed();
      remove = true;
      break;
  }
  if (remove) {
    bar->RemoveSelf();
  }
  return true;
}

void PageInfoBars::OnInfoBarAdded(infobars::InfoBar* bar) {
  Add(bar);
}

void PageInfoBars::OnInfoBarRemoved(infobars::InfoBar* bar, bool) {
  for (auto it = bars_.begin(); it != bars_.end(); ++it) {
    if (it->second != bar) {
      continue;
    }
    const int id = it->first;
    bars_.erase(it);
    present_.Run(engine::InfoBarRemoved{.page_id = page_, .info_bar_id = id});
    return;
  }
}

void PageInfoBars::OnInfoBarReplaced(infobars::InfoBar* old_bar, infobars::InfoBar* new_bar) {
  OnInfoBarRemoved(old_bar, false);
  Add(new_bar);
}

void PageInfoBars::OnManagerWillBeDestroyed(infobars::InfoBarManager* manager) {
  if (manager == manager_) {
    manager->RemoveObserver(this);
    manager_ = nullptr;
  }
  bars_.clear();
}

void PageInfoBars::Add(infobars::InfoBar* bar) {
  if (!Confirming(bar)) {
    return;
  }
  for (const auto& [id, known] : bars_) {
    if (known == bar) {
      return;
    }
  }
  const int id = ++next_id_;
  bars_[id] = bar;
  Show(id, bar);
}

void PageInfoBars::Show(int id, infobars::InfoBar* bar) {
  auto* confirm = Confirming(bar);
  if (!confirm) {
    return;
  }
  const int buttons = confirm->GetButtons();
  auto label = [&](ConfirmInfoBarDelegate::InfoBarButton button) -> std::optional<std::string> {
    if (!(buttons & button)) {
      return std::nullopt;
    }
    return base::UTF16ToUTF8(confirm->GetButtonLabel(button));
  };
  present_.Run(engine::InfoBarShown{.page_id = page_,
                                    .info_bar_id = id,
                                    .message = base::UTF16ToUTF8(confirm->GetMessageText()),
                                    .accept_label = label(ConfirmInfoBarDelegate::BUTTON_OK),
                                    .cancel_label = label(ConfirmInfoBarDelegate::BUTTON_CANCEL),
                                    .closeable = confirm->IsCloseable(),
                                    // Only Crest's own tab-sharing bars report
                                    // something that lasts; the rest ask.
                                    .minimizable = confirm->GetIdentifier() ==
                                                   infobars::InfoBarDelegate::TAB_SHARING_INFOBAR_DELEGATE});
}

}  // namespace crest
