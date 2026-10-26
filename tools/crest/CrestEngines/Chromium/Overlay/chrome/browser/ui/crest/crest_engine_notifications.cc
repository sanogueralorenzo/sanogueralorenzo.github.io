#include "chrome/browser/ui/crest/crest_engine_notifications.h"

#include <algorithm>
#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/notifications/notification_display_service_impl.h"
#include "chrome/browser/notifications/notification_platform_bridge.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/crest/crest_engine_binding.h"
#include "chrome/browser/ui/crest/crest_engine_page.h"
#include "chrome/browser/ui/crest/crest_engine_profiles.h"
#include "chrome/common/notifications/notification_operation.h"
#include "content/public/browser/notification_event_dispatcher.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/extension.h"
#include "extensions/common/mojom/api_permission_id.mojom.h"
#include "extensions/common/permissions/permissions_data.h"
#include "ui/message_center/public/cpp/notification.h"
#include "url/origin.h"

namespace crest {

namespace {

// The origin a notification belongs to, as Crest's choices name it.
engine::SiteOrigin SiteOriginOf(const GURL& url) {
  const url::Origin origin = url::Origin::Create(url);
  return engine::SiteOrigin{
      .scheme = origin.scheme(), .host = origin.host(), .port = origin.port()};
}

// The live document that posted the non-persistent notification `id`, or null
// for a worker's or once the document is gone.
content::RenderFrameHost* DocumentOf(const std::string& id) {
  return content::NotificationEventDispatcher::GetInstance()
      ->GetNonPersistentNotificationDocument(id);
}

bool ExtensionMayNotify(Profile* profile, const GURL& origin) {
  if (!origin.SchemeIs("chrome-extension")) {
    return false;
  }
  const auto* extension =
      extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(
          std::string(origin.host()));
  return extension && extension->permissions_data()->HasAPIPermission(
                          extensions::mojom::APIPermissionID::kNotifications);
}

// Tells `profile`'s display service that a notification it just displayed is
// closed, once that display has returned: Crest does not show it.
void CloseSoon(Profile* profile,
               NotificationHandler::Type type,
               const GURL& origin,
               const std::string& id) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](base::WeakPtr<Profile> profile, NotificationHandler::Type type,
             const GURL& origin, const std::string& id) {
            if (!profile) {
              return;
            }
            NotificationDisplayServiceImpl::GetForProfile(profile.get())
                ->ProcessNotificationOperation(NotificationOperation::kClose,
                                               type, origin, id, std::nullopt,
                                               std::nullopt, /*by_user=*/false,
                                               std::nullopt, base::DoNothing());
          },
          profile->GetWeakPtr(), type, origin, id));
}

// Chromium's notification display service reaches the binding's
// notifications through this, in place of its macOS bridge.
class NotificationBridge final : public NotificationPlatformBridge {
 public:
  NotificationBridge() = default;

  // NotificationPlatformBridge:
  void Display(
      NotificationHandler::Type type,
      Profile* profile,
      const message_center::Notification& notification,
      std::unique_ptr<NotificationCommon::Metadata> metadata) override {
    EngineBinding::Get().Notifications().Display(type, profile, notification);
  }

  void Close(Profile* profile, const std::string& notification_id) override {
    EngineBinding::Get().Notifications().Close(profile, notification_id);
  }

  void GetDisplayed(Profile* profile,
                    GetDisplayedNotificationsCallback callback) const override {
    Reply(EngineBinding::Get().Notifications().Displayed(profile, std::nullopt),
          std::move(callback));
  }

  void GetDisplayedForOrigin(
      Profile* profile,
      const GURL& origin,
      GetDisplayedNotificationsCallback callback) const override {
    Reply(EngineBinding::Get().Notifications().Displayed(profile, origin),
          std::move(callback));
  }

  void SetReadyCallback(NotificationBridgeReadyCallback callback) override {
    std::move(callback).Run(true);
  }

  void DisplayServiceShutDown(Profile* profile) override {
    EngineBinding::Get().Notifications().ShutDown(profile);
  }

 private:
  // Every notification Crest shows is one the binding knows, so the display
  // service may treat any it does not list as closed.
  static void Reply(std::set<std::string> notifications,
                    GetDisplayedNotificationsCallback callback) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(callback), std::move(notifications),
                                  /*supports_synchronization=*/true));
  }
};

}  // namespace

EngineNotifications::EngineNotifications(Present present)
    : present_(std::move(present)) {}

EngineNotifications::~EngineNotifications() = default;

// Chromium's display service.

void EngineNotifications::Display(
    NotificationHandler::Type type,
    Profile* profile,
    const message_center::Notification& notification) {
  const std::string& id = notification.id();
  EnginePage* page =
      type == NotificationHandler::Type::WEB_NON_PERSISTENT
          ? EngineBinding::Get().PageFor(
                content::WebContents::FromRenderFrameHost(DocumentOf(id)))
          : nullptr;
  const auto profile_id =
      ParseGuid(EngineBinding::Get().Profiles().IdFor(profile));
  const bool independent =
      profile && !profile->IsOffTheRecord() &&
      (type == NotificationHandler::Type::WEB_PERSISTENT ||
       (type == NotificationHandler::Type::EXTENSION &&
        ExtensionMayNotify(profile, notification.origin_url())));
  // Replacement invalidates any system delivery still in flight.
  if (auto previous = Find(profile, id); previous != posted_.end()) {
    Withdraw(*previous);
    posted_.erase(previous);
  }
  if (!profile_id || (!page && !independent)) {
    CloseSoon(profile, type, notification.origin_url(), id);
    return;
  }
  posted_.push_back(
      Posted{.page = page ? std::optional(page->id()) : std::nullopt,
             .profile_id = *profile_id,
             .type = type,
             .notification = id,
             .profile = profile->GetWeakPtr(),
             .origin = notification.origin_url()});
  if (page) {
    present_.Run(engine::WebNotificationPosted{
        .page_id = page->id(),
        .notification_id = id,
        .origin = SiteOriginOf(notification.origin_url()),
        .title = base::UTF16ToUTF8(notification.title()),
        .body = base::UTF16ToUTF8(notification.message()),
        .silent = notification.silent()});
  } else {
    present_.Run(engine::ProfileNotificationPosted{
        .profile_id = *profile_id,
        .notification_id = id,
        .origin = SiteOriginOf(notification.origin_url()),
        .source = type == NotificationHandler::Type::EXTENSION
                      ? engine::ProfileNotificationSource::kExtension
                      : engine::ProfileNotificationSource::kServiceWorker,
        .title = base::UTF16ToUTF8(notification.title()),
        .body = base::UTF16ToUTF8(notification.message()),
        .silent = notification.silent()});
  }
}

// The document closed it, as `Notification.close()` does.
void EngineNotifications::Close(Profile* profile,
                                const std::string& notification_id) {
  auto found = Find(profile, notification_id);
  if (found == posted_.end()) {
    return;
  }
  Withdraw(*found);
  posted_.erase(found);
}

std::set<std::string> EngineNotifications::Displayed(
    Profile* profile,
    const std::optional<GURL>& origin) const {
  std::set<std::string> notifications;
  for (const Posted& posted : posted_) {
    if (posted.profile.get() == profile &&
        (!origin || url::IsSameOriginWith(posted.origin, *origin))) {
      notifications.insert(posted.notification);
    }
  }
  return notifications;
}

void EngineNotifications::ShutDown(Profile* profile) {
  std::erase_if(posted_, [this, profile](const Posted& posted) {
    if (profile && posted.profile && posted.profile.get() != profile) {
      return false;
    }
    Withdraw(posted);
    return true;
  });
}

void EngineNotifications::Withdraw(const Posted& posted) {
  if (posted.page) {
    present_.Run(engine::WebNotificationClosed{
        .page_id = *posted.page, .notification_id = posted.notification});
  } else {
    present_.Run(engine::ProfileNotificationClosed{
        .profile_id = posted.profile_id,
        .notification_id = posted.notification});
  }
}

// The platform's side.

// A click reaches the document only while it lives: the platform has brought
// its page forward already, and nothing else hears it. One Crest did not show
// closes, as Chromium hears of a notification the system dismissed.
bool EngineNotifications::Answer(const engine::AnswerWebNotification& answer) {
  auto found = std::find_if(
      posted_.begin(), posted_.end(), [&answer](const Posted& posted) {
        return posted.page == answer.page_id &&
               posted.notification == answer.notification_id;
      });
  return Answer(found, answer.answer);
}

bool EngineNotifications::Answer(
    const engine::AnswerProfileNotification& answer) {
  auto found = std::find_if(
      posted_.begin(), posted_.end(), [&answer](const Posted& posted) {
        return !posted.page && posted.profile_id == answer.profile_id &&
               posted.notification == answer.notification_id;
      });
  return Answer(found, answer.answer);
}

bool EngineNotifications::Answer(std::vector<Posted>::iterator found,
                                 engine::WebNotificationAnswer answer) {
  if (found == posted_.end()) {
    return false;
  }
  const Posted posted = std::move(*found);
  posted_.erase(found);
  if (!posted.profile) {
    return false;
  }
  const bool clicked = answer == engine::WebNotificationAnswer::kClicked;
  if (clicked && ((posted.page && !DocumentOf(posted.notification)) ||
                  (posted.type == NotificationHandler::Type::EXTENSION &&
                   !ExtensionMayNotify(posted.profile.get(), posted.origin)))) {
    return false;
  }
  NotificationDisplayServiceImpl::GetForProfile(posted.profile.get())
      ->ProcessNotificationOperation(
          clicked ? NotificationOperation::kClick
                  : NotificationOperation::kClose,
          posted.type, posted.origin, posted.notification, std::nullopt,
          std::nullopt, clicked ? std::nullopt : std::optional<bool>(false),
          std::nullopt, base::DoNothing());
  return true;
}

void EngineNotifications::Forget(const engine::Guid& page) {
  std::erase_if(posted_, [this, &page](const Posted& posted) {
    if (posted.page != page) {
      return false;
    }
    Withdraw(posted);
    return true;
  });
}

std::vector<EngineNotifications::Posted>::iterator EngineNotifications::Find(
    Profile* profile,
    const std::string& notification_id) {
  return std::find_if(posted_.begin(), posted_.end(),
                      [profile, &notification_id](const Posted& posted) {
                        return posted.profile.get() == profile &&
                               posted.notification == notification_id;
                      });
}

std::unique_ptr<NotificationPlatformBridge> CreateNotificationBridge() {
  return std::make_unique<NotificationBridge>();
}

}  // namespace crest
