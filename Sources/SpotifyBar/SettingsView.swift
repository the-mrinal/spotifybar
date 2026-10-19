import AppKit
import ServiceManagement
import SpotifyBarCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var clientIDDraft = ""
    @State private var signingIn = false
    @State private var error: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showArtist") private var showArtist = true
    @AppStorage("maxTitleWidth") private var maxTitleWidth = 132.0

    var body: some View {
        Form {
            Section("Spotify") {
                TextField("Client ID", text: $clientIDDraft, prompt: Text("Paste your Spotify app's Client ID"))
                    .onSubmit(saveClientID)
                HStack {
                    if model.isSignedIn {
                        Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Sign Out") { model.signOut() }
                    } else {
                        Button(signingIn ? "Waiting for Spotify…" : "Sign in with Spotify", action: signIn)
                            .disabled(clientIDDraft.trimmingCharacters(in: .whitespaces).isEmpty || signingIn)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
                DisclosureGroup("How to get a Client ID") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Open developer.spotify.com/dashboard and create an app.")
                        Text("2. Add this Redirect URI and tick “Web API”:")
                        HStack {
                            Text(SpotifyAuth.redirectURI).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                            }
                        }
                        Text("3. Copy the app's Client ID here and sign in.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            Section("Menu bar") {
                Toggle("Show artist line", isOn: $showArtist)
                Stepper(value: $maxTitleWidth, in: 80...200, step: 4) {
                    Text("Max title width: \(Int(maxTitleWidth)) pt")
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin($1) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onAppear { clientIDDraft = model.clientID }
    }

    private func saveClientID() {
        let trimmed = clientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != model.clientID { model.clientID = trimmed }
    }

    private func signIn() {
        saveClientID()
        signingIn = true
        error = nil
        Task {
            do { try await model.signIn() } catch { self.error = "Sign-in failed: \(error.localizedDescription)" }
            signingIn = false
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Couldn't change login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Plain window for Settings so it opens reliably from a menu bar–only app.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "SpotifyBar Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
