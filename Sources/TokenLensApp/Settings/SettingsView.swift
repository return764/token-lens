import SwiftUI

/// Wrapper view for the Settings window (opened via NSWindow by AppDelegate).
/// Wraps SettingsTab in a scrollable, properly sized container.
public struct SettingsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView(.vertical) {
            SettingsTab(appState: appState)
                .padding()
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 650, idealHeight: 760)
    }
}
