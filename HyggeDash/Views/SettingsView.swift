import SwiftUI

struct SettingsView: View {
    @ObservedObject var sonosService: SonosService
    @ObservedObject var authService: SonosAuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                sonosSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var sonosSection: some View {
        Section {
            HStack {
                Image(systemName: authService.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(authService.isAuthenticated ? .green : .red)
                Text(authService.isAuthenticated ? "Connected" : "Not Connected")
                    .foregroundColor(authService.isAuthenticated ? .primary : .secondary)
            }

            if authService.isAuthenticated {
                Button(role: .destructive) {
                    authService.logout()
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.square")
                        Text("Disconnect Sonos Account")
                    }
                }
            } else {
                Button {
                    authService.authenticate()
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Connect Sonos Account")
                    }
                }
            }
        } header: {
            Text("Sonos Account")
        } footer: {
            Text("Connect your Sonos account to control speakers directly from HyggeDash.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(HyggeTheme.textSecondary)
            }

            Link(destination: URL(string: "https://developer.sonos.com")!) {
                HStack {
                    Text("Sonos Developer Documentation")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(HyggeTheme.textSecondary)
                }
            }
        } header: {
            Text("About")
        }
    }
}

#Preview {
    SettingsView(sonosService: SonosService(), authService: SonosAuthService())
}
