import SwiftUI

struct SettingsView: View {
    @ObservedObject var sonosService: SonosService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("sonosServerIP") private var serverIP = "192.168.1.100"
    @AppStorage("sonosServerPort") private var serverPort = "5005"

    @State private var testingConnection = false
    @State private var connectionStatus: ConnectionStatus?

    enum ConnectionStatus {
        case success
        case failure(String)
    }

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
                Text("IP Address")
                Spacer()
                TextField("192.168.1.100", text: $serverIP)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
            }

            HStack {
                Text("Port")
                Spacer()
                TextField("5005", text: $serverPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .keyboardType(.numberPad)
            }

            Button(action: testConnection) {
                HStack {
                    if testingConnection {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "network")
                    }
                    Text("Test Connection")
                }
            }
            .disabled(testingConnection)

            if let status = connectionStatus {
                HStack {
                    switch status {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connection successful")
                            .foregroundColor(.green)
                    case .failure(let message):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Sonos Server (soco-cli-api)")
        } footer: {
            Text("Enter the IP address and port of your Raspberry Pi running the soco-cli REST API server.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }

            Link(destination: URL(string: "https://github.com/avantrec/soco-cli")!) {
                HStack {
                    Text("soco-cli Documentation")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("About")
        }
    }

    private func testConnection() {
        testingConnection = true
        connectionStatus = nil

        let urlString = "http://\(serverIP):\(serverPort)/speakers"

        guard let url = URL(string: urlString) else {
            connectionStatus = .failure("Invalid URL")
            testingConnection = false
            return
        }

        let task = URLSession.shared.dataTask(with: url) { _, response, error in
            DispatchQueue.main.async {
                testingConnection = false

                if let error = error {
                    connectionStatus = .failure(error.localizedDescription)
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        connectionStatus = .success
                        // Refresh speakers after successful connection test
                        Task {
                            await sonosService.fetchSpeakers()
                        }
                    } else {
                        connectionStatus = .failure("HTTP \(httpResponse.statusCode)")
                    }
                } else {
                    connectionStatus = .failure("Unknown error")
                }
            }
        }
        task.resume()
    }
}

#Preview {
    SettingsView(sonosService: SonosService())
}
