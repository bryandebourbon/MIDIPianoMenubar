import SwiftUI
import AppKit

@main
struct MIDIPianoMenubarApp: App {
    // Initialize the AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Since this is a menu bar app without windows, we return an empty scene
        Settings {
            EmptyView()
        }
    }
}
