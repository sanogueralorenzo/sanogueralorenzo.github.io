import SwiftUI
import UIKit

/// UIKit owns the standard vertical page-control geometry and interaction on
/// touch platforms. This adapter only translates its page index into the widget
/// runtime's stable instance identity.
struct BrowserSidebarWidgetVerticalPageControl: UIViewRepresentable {
    let numberOfPages: Int
    let currentPage: Int
    let selectPage: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selectPage: selectPage)
    }

    func makeUIView(context: Context) -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.direction = .topToBottom
        pageControl.backgroundStyle = .minimal
        pageControl.allowsContinuousInteraction = true
        let dotImage = UIImage(
            systemName: "circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: BrowserSidebarWidgetDeckStyle.indicatorDotDiameter,
                weight: .regular
            )
        )
        pageControl.preferredIndicatorImage = dotImage
        pageControl.preferredCurrentPageIndicatorImage = dotImage
        pageControl.pageIndicatorTintColor = .secondaryLabel.withAlphaComponent(0.3)
        pageControl.currentPageIndicatorTintColor = .label.withAlphaComponent(0.72)
        pageControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:)),
            for: .valueChanged
        )
        return pageControl
    }

    func updateUIView(_ pageControl: UIPageControl, context: Context) {
        context.coordinator.selectPage = selectPage
        pageControl.numberOfPages = numberOfPages
        pageControl.currentPage = min(max(currentPage, 0), max(numberOfPages - 1, 0))
        pageControl.hidesForSinglePage = true
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectPage: (Int) -> Void

        init(selectPage: @escaping (Int) -> Void) {
            self.selectPage = selectPage
        }

        @objc func selectionChanged(_ sender: UIPageControl) {
            selectPage(sender.currentPage)
        }
    }
}
