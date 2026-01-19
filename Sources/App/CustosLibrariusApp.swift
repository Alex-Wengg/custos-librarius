import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force the app to become active and accept keyboard input
        NSApp.activate(ignoringOtherApps: true)

        // Make sure we're a regular app (not accessory/background)
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure the main window becomes key
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct CustosLibrariusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project...") {
                    appState.showNewProjectSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Project...") {
                    appState.openProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
