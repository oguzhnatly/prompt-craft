import SwiftUI

private struct IsWindowModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isWindowMode: Bool {
        get { self[IsWindowModeKey.self] }
        set { self[IsWindowModeKey.self] = newValue }
    }
}
