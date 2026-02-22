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
            station.name.localizedCaseInsensitiveContains(searchText) ||
            station.source.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            mainList
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { isPresented = false }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search library")
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
            // Sonos Favorites
            if !sonosService.favorites.isEmpty {
                Section {
                    ForEach(filteredFavorites) { favorite in
                        Button {
                            Task {
                                await sonosService.playFavorite(favorite)
                                isPresented = false
                            }
                        } label: {
                            favoriteRow(favorite)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label("Sonos Favorites", systemImage: "star.fill")
                }
            }

            // Music service links (Spotify, Apple Music, etc.)
            let serviceStations = filteredStations.filter { $0.source != .stream }
            if !serviceStations.isEmpty {
                Section {
                    ForEach(serviceStations) { station in
                        Button {
                            Task {
                                await sonosService.playStation(station)
                                isPresented = false
                            }
                        } label: {
                            stationRow(station)
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
                } header: {
                    Label("Saved Links", systemImage: "link")
                }
            }

            // Direct streams
            let streamStations = filteredStations.filter { $0.source == .stream }
            if !streamStations.isEmpty {
                Section {
                    ForEach(streamStations) { station in
                        Button {
                            Task {
                                await sonosService.playStation(station)
                                isPresented = false
                            }
                        } label: {
                            stationRow(station)
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
                } header: {
                    Label("Streams", systemImage: "antenna.radiowaves.left.and.right")
                }
            }

            // Empty state
            if sonosService.favorites.isEmpty && stationsService.stations.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(HyggeTheme.textSecondary)
                        Text("No Music")
                            .font(.headline)
                            .foregroundColor(HyggeTheme.textPrimary)
                        Text("Share a Spotify or Apple Music link here, add a stream URL, or your Sonos favorites will appear automatically.")
                            .font(.subheadline)
                            .foregroundColor(HyggeTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            await sonosService.fetchFavorites()
        }
    }

    // MARK: - Row Views

    private func favoriteRow(_ favorite: SonosFavorite) -> some View {
        HStack(spacing: 12) {
            if let imageUrl = favorite.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "music.note")
                        .foregroundColor(HyggeTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(HyggeTheme.cardBackgroundLight)
                        .cornerRadius(8)
                }
                .frame(width: 44, height: 44)
                .cornerRadius(8)
            } else {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                    .frame(width: 44, height: 44)
                    .background(HyggeTheme.cardBackgroundLight)
                    .cornerRadius(8)
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

            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundColor(HyggeTheme.accent.opacity(0.7))
        }
        .contentShape(Rectangle())
    }

    private func stationRow(_ station: Station) -> some View {
        HStack(spacing: 12) {
            sourceIcon(for: station.source)
                .frame(width: 44, height: 44)
                .background(sourceColor(for: station.source).opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.body)
                    .foregroundColor(HyggeTheme.textPrimary)
                Text(station.subtitle)
                    .font(.caption)
                    .foregroundColor(HyggeTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundColor(HyggeTheme.accent.opacity(0.7))
        }
        .contentShape(Rectangle())
    }

    private func sourceIcon(for source: StationSource) -> some View {
        Image(systemName: source.iconName)
            .font(.system(size: 18))
            .foregroundColor(sourceColor(for: source))
    }

    private func sourceColor(for source: StationSource) -> Color {
        switch source {
        case .spotify: return Color(red: 0.12, green: 0.84, blue: 0.38)  // Spotify green
        case .appleMusic: return Color(red: 0.98, green: 0.34, blue: 0.38)  // Apple red
        case .tidal: return Color(red: 0.0, green: 0.78, blue: 0.85)  // Tidal cyan
        case .deezer: return Color(red: 0.63, green: 0.29, blue: 0.88)  // Deezer purple
        case .stream: return HyggeTheme.accent
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
    @State private var detectedSource: StationSource = .stream

    init(stationsService: StationsService, station: Station? = nil) {
        self.stationsService = stationsService
        self.station = station
        _name = State(initialValue: station?.name ?? "")
        _url = State(initialValue: station?.url ?? "")
        _detectedSource = State(initialValue: station?.source ?? .stream)
    }

    private var isEditing: Bool { station != nil }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // URL field first — auto-detects and fills name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL or Share Link")
                            .font(.caption)
                            .foregroundColor(HyggeTheme.textSecondary)
                        TextField("https://open.spotify.com/playlist/...", text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onChange(of: url) { _, newValue in
                                onURLChanged(newValue)
                            }
                    }

                    if detectedSource != .stream {
                        HStack(spacing: 8) {
                            Image(systemName: detectedSource.iconName)
                                .foregroundColor(HyggeTheme.accent)
                            Text("\(detectedSource.displayName) link detected")
                                .font(.caption)
                                .foregroundColor(HyggeTheme.accent)
                        }
                        .padding(.vertical, 2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.caption)
                            .foregroundColor(HyggeTheme.textSecondary)
                        TextField("My Playlist", text: $name)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text(isEditing ? "Edit Link" : "Add Music")
                } footer: {
                    Text("Paste a Spotify, Apple Music, or TIDAL link. Or enter a direct stream URL for internet radio.")
                }

                // Paste from clipboard
                if !isEditing {
                    Section {
                        Button {
                            pasteFromClipboard()
                        } label: {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        }
                    }
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
                                Text("Delete")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit" : "Add Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                // Auto-detect on edit
                if isEditing {
                    detectedSource = StationSource.detect(from: url)
                }
            }
        }
    }

    private func onURLChanged(_ newURL: String) {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        detectedSource = StationSource.detect(from: trimmed)

        // Auto-fill name if empty
        if name.trimmingCharacters(in: .whitespaces).isEmpty && detectedSource != .stream {
            if let parsed = ShareLinkParser.parse(trimmed) {
                name = "\(detectedSource.displayName) \(parsed.type.capitalized)"
            }
        }
    }

    private func pasteFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string else { return }
        let trimmed = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        url = trimmed
        onURLChanged(trimmed)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let station {
            stationsService.updateStation(station, name: trimmedName, url: trimmedURL)
        } else {
            stationsService.addStation(name: trimmedName, url: trimmedURL)
        }
        dismiss()
    }
}

#Preview {
    StationPickerView(
        stationsService: StationsService(),
        sonosService: SonosService(),
        isPresented: .constant(true)
    )
}
