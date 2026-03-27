import AppKit
import Foundation
@preconcurrency import UserNotifications

final class AppNotificationController: NSObject, UNUserNotificationCenterDelegate {
  private let center = UNUserNotificationCenter.current()

  func configure() {
    let center = center
    center.delegate = self
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }
  }

  func postReviewNotification(snapshot: ReviewJobSnapshot) {
    let title: String
    switch snapshot.status {
    case .queued, .running, .postingComments:
      title = "Review Started"
    case .completed:
      title = "Review Completed"
    case .failed:
      title = "Review Failed"
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = "PR: #\(snapshot.number)"
    if let targetURL = snapshot.filesURL?.absoluteString {
      content.userInfo["target_url"] = targetURL
    }

    let identifier = "review.\(snapshot.id)"
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    center.add(request)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard
      let rawURL = response.notification.request.content.userInfo["target_url"] as? String,
      let url = URL(string: rawURL)
    else {
      return
    }
    _ = await MainActor.run {
      NSWorkspace.shared.open(url)
    }
  }
}
