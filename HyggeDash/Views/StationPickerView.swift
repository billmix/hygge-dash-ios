import SwiftUI

struct StationPickerView: View {
    @ObservedObject var stationsService: StationsService
    @ObservedObject var sonosService: SonosService
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var stationToEdit: Station?

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
                mainList
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search playlists")
        }
        .sheet(isPresented: $showingAddSheet) {
            StationFormView(stationsService: stationsService)
        }
        .sheet(item: $stationToEdit) { station in
            StationFormView(stationsService: stationsService, station: station)
        }
    }

    private var mainList: some View {
        List {
            // Sonos Favorites section
            if !sonosService.favorites.isEmpty {
                Section("Sonos Favorites") {
                    ForEach(filteredFavorites) { favorite in
                        Button(action: {
                            Task {
                                await sonosService.playFavorite(favorite)
                                isPresented = false
                            }
                        }) {
                            HStack {
                                if let imageUrl = favorite.imageUrl, let url = URL(string: imageUrl) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image(systemName: "music.note")
                                            .foregroundColor(HyggeTheme.accent)
                                    }
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(6)
                                } else {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.orange)
                                        .frame(width: 40, height: 40)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(favorite.name)
                                        .font(.body)
                                        .foregroundColor(HyggeTheme.textPrimary)

                                    if let service = favorite.service {
                                        Text(service)
                                            .font(.caption)
                                            .foregroundColor(HyggeTheme.textSecondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "play.circle")
                                    .foregroundColor(HyggeTheme.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Custom stations section
            if !stationsService.stations.isEmpty {
                Section("Custom Streams") {
                    ForEach(filteredStations) { station in
                        Button(action: {
                            Task {
                                await sonosService.playStation(station)
                                isPresented = false
                            }
                        }) {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(HyggeTheme.accent)
                                    .frame(width: 40, height: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(.body)
                                        .foregroundColor(HyggeTheme.textPrimary)

                                    Text(station.url)
                                        .font(.caption)
                                        .foregroundColor(HyggeTheme.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "play.circle")
                                    .foregroundColor(HyggeTheme.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                stationsService.deleteStation(station)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                stationToEdit = station
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(HyggeTheme.accent)
                        }
                    }
                    .onMove { source, destination in
                        stationsService.moveStations(from: source, to: destination)
                    }
                }
            }

            // Empty state
            if sonosService.favorites.isEmpty && stationsService.stations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(HyggeTheme.textSecondary)
                    Text("No Playlists")
                        .font(.headline)
                    Text("Your Sonos favorites will appear here, or tap + to add a stream URL.")
                        .font(.subheadline)
                        .foregroundColor(HyggeTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .task {
            await sonosService.fetchFavorites()
        }
    }

    private var filteredFavorites: [SonosFavorite] {
        if searchText.isEmpty {
            return sonosService.favorites
        }
        return sonosService.favorites.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

// MARK: - Add / Edit Form

struct StationFormView: View {
    @ObservedObject var stationsService: StationsService
    @Environment(\.dismiss) private var dismiss

    let station: Station?
    @State private var name: String
    @State private var url: String

    init(stationsService: StationsService, station: Station? = nil) {
        self.stationsService = stationsService
        self.station = station
        _name = State(initialValue: station?.name ?? "")
        _url = State(initialValue: station?.url ?? "")
    }

    private var isEditing: Bool { station != nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !url.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Stream URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let station {
                                stationsService.deleteStation(station)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Playlist")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Playlist" : "Add Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
                        if let station {
                            stationsService.updateStation(station, name: trimmedName, url: trimmedURL)
                        } else {
                            stationsService.addStation(name: trimmedName, url: trimmedURL)
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

#Preview {
    StationPickerView(
        stationsService: StationsService(),
        sonosService: SonosService(),
        isPresented: .constant(true)
    )
}
