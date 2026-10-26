#ifndef CHROME_BROWSER_UI_CREST_CREST_ENGINE_NOTIFICATIONS_H_
#define CHROME_BROWSER_UI_CREST_CREST_ENGINE_NOTIFICATIONS_H_

#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/notifications/notification_handler.h"
#include "chrome/browser/ui/crest/crest_engine_contract.h"
#include "url/gurl.h"

class NotificationPlatformBridge;
class Profile;

namespace message_center {
class Notification;
}

namespace crest {

// The notifications documents in the binding's pages post, which Crest shows
// as its own. Chromium's macOS bridge posts through NSUserNotificationCenter,
// a client the system refuses for an app that, like Crest, also posts through
// UNUserNotificationCenter, so while Crest hosts the engine Chromium's
// notification display service hands every notification here instead.
//
// A notification a page's live document posted is presented to the platform,
// which shows it when the core lets the page's Space show the site's
// notifications and the system lets Crest show them, and answers once the
// person clicks it or it will not show. Worker and extension notifications
// belong to their profile instead, and cannot appear for a private profile.
class EngineNotifications final {
 public:
  using Present = base::RepeatingCallback<void(engine::EnginePresentation)>;

  explicit EngineNotifications(Present present);
  EngineNotifications(const EngineNotifications&) = delete;
  EngineNotifications& operator=(const EngineNotifications&) = delete;
  ~EngineNotifications();

  // Chromium's display service, through the bridge CreateNotificationBridge
  // makes: a notification to show, and one to take down.
  void Display(NotificationHandler::Type type,
               Profile* profile,
               const message_center::Notification& notification);
  void Close(Profile* profile, const std::string& notification_id);
  // The notifications of `profile`'s documents the platform was asked to
  // show, all of them or only `origin`'s.
  std::set<std::string> Displayed(Profile* profile,
                                  const std::optional<GURL>& origin) const;
  // The display service of `profile` is shutting down, or every one when it
  // is null.
  void ShutDown(Profile* profile);

  // What became of a notification the platform was asked to show, which the
  // document that posted it hears. False when the page no longer has it.
  bool Answer(const engine::AnswerWebNotification& answer);
  bool Answer(const engine::AnswerProfileNotification& answer);
  // The page is gone, and the notifications its documents posted with it.
  void Forget(const engine::Guid& page);

 private:
  // A notification presented to the platform, until the platform answers or
  // Chromium takes it down.
  struct Posted {
    std::optional<engine::Guid> page;
    engine::Guid profile_id;
    NotificationHandler::Type type;
    std::string notification;
    base::WeakPtr<Profile> profile;
    GURL origin;
  };

  std::vector<Posted>::iterator Find(Profile* profile,
                                     const std::string& notification_id);
  void Withdraw(const Posted& posted);
  bool Answer(std::vector<Posted>::iterator found,
              engine::WebNotificationAnswer answer);

  const Present present_;
  std::vector<Posted> posted_;
};

// The platform bridge Chromium's notification display service uses while
// Crest hosts the engine.
std::unique_ptr<NotificationPlatformBridge> CreateNotificationBridge();

}  // namespace crest

#endif  // CHROME_BROWSER_UI_CREST_CREST_ENGINE_NOTIFICATIONS_H_
