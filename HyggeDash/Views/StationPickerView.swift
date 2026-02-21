import SwiftUI

struct StationPickerView: View {
    @ObservedObject var stationsService: StationsService
    @ObservedObject var sonosService: SonosService
    @Binding var isPresented: Bool
    @State private var searchText = ""

    var filteredStations: [Station] {
        if searchText.isEmpty {
            return stationsService.stations
        }
        return stationsService.stations.filter { station in
            station.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if stationsService.isLoading && stationsService.stations.isEmpty {
                    loadingView
                } else if stationsService.stations.isEmpty {
                    emptyView
                } else {
                    stationsList
                }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search playlists")
        }
        .task {
            await stationsService.fetchStations()
        }
        .refreshable {
            await stationsService.fetchStations(forceRefresh: true)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading playlists...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Playlists Found")
                .font(.headline)

            if let error = stationsService.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Add playlists to your Google Sheet to see them here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Retry") {
                Task {
                    await stationsService.fetchStations(forceRefresh: true)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stationsList: some View {
        List(filteredStations) { station in
            Button(action: {
                Task {
                    await sonosService.playStation(station)
                    isPresented = false
                }
            }) {
                HStack {
                    Image(systemName: "music.note.list")
                        .foregroundColor(.green)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name)
                            .font(.body)
                            .foregroundColor(.primary)

                        Text(station.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "play.circle")
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
}

#Preview {
    StationPickerView(
        stationsService: StationsService(),
        sonosService: SonosService(),
        isPresented: .constant(true)
    )
}
