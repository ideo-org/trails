import Foundation
import Combine

@MainActor
final class TabChromeModel: ObservableObject {
    @Published private var hiddenReasons: Set<String> = []

    var isVisible: Bool {
        hiddenReasons.isEmpty
    }

    func hide(reason: String) {
        hiddenReasons.insert(reason)
    }

    func show(reason: String) {
        hiddenReasons.remove(reason)
    }
}
