import SwiftUI

struct SettingsView: View {
    @ObservedObject var sonosService: SonosService
    @ObservedObject var authService: SonosAuthService
    @ObservedObject var spotifyService: SpotifyService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                sonosSection
                spotifySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sonos

    private var sonosSection: some View {
        Section {
            HStack {
                Image(systemName: authService.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(authService.isAuthenticated ? HyggeTheme.accent : HyggeTheme.destructive)
                Text(authService.isAuthenticated ? "Connected" : "Not Connected")
            }

            if authService.isAuthenticated {
                Button(role: .destructive) {
                    authService.logout()
                } label: {
                    Label("Disconnect Sonos", systemImage: "arrow.right.square")
                }
            } else {
                Button {
                    authService.authenticate()
                } label: {
                    Label("Connect Sonos Account", systemImage: "link")
                }
            }
        } header: {
            Text("Sonos Account")
        } footer: {
            Text("Controls speakers, groups, and favorites.")
        }
    }

    // MARK: - Spotify

    private var spotifySection: some View {
        Section {
            HStack {
                Image(systemName: spotifyService.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(spotifyService.isAuthenticated ? Color(red: 0.12, green: 0.84, blue: 0.38) : HyggeTheme.textSecondary)
                Text(spotifyService.isAuthenticated ? "Connected" : "Not Connected")
            }

            if spotifyService.isAuthenticated {
                // Show available devices
                if !spotifyService.availableDevices.isEmpty {
                    ForEach(spotifyService.availableDevices) { device in
                        HStack {
                            Image(systemName: device.type == "Speaker" ? "hifispeaker.fill" : "desktopcomputer")
                                .foregroundColor(device.isActive ? HyggeTheme.accent : HyggeTheme.textTertiary)
                                .frame(width: 24)
                            Text(device.name)
                                .font(.subheadline)
                            Spacer()
                            if device.isActive {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundColor(HyggeTheme.accent)
                            }
                        }
                    }
                }

                Button {
                    Task { await spotifyService.fetchDevices() }
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    spotifyService.logout()
                } label: {
                    Label("Disconnect Spotify", systemImage: "arrow.right.square")
                }
            } else {
                Button {
                    spotifyService.authenticate()
                } label: {
                    Label("Connect Spotify Account", systemImage: "link")
                }
            }

            if let error = spotifyService.authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(HyggeTheme.destructive)
            }
        } header: {
            Text("Spotify Account")
        } footer: {
            Text("Enables playing Spotify links with full skip/seek control via Spotify Connect.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(HyggeTheme.textSecondary)
            }
        } header: {
            Text("About")
        }
    }
}

#Preview {
    SettingsView(sonosService: SonosService(), authService: SonosAuthService(), spotifyService: SpotifyService())
}
