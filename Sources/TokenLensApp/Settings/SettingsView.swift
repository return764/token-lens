import SwiftUI

/// Wrapper view for the Dashboard window (opened via NSWindow by AppDelegate).
public struct SettingsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        SettingsTab(appState: appState)
            .padding()
            .frame(minWidth: 760, idealWidth: 820, minHeight: 650, idealHeight: 760)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
