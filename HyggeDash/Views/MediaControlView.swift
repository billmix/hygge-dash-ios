import SwiftUI

struct MediaControlView: View {
    @ObservedObject var sonosService: SonosService
    @StateObject private var stationsService = StationsService()
    @State private var showingZonePicker = false
    @State private var showingStationPicker = false
    @State private var localVolume: Double = 20
    @State private var isSliderDragging = false

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader

                if sonosService.isLoading && sonosService.zones.isEmpty {
                    loadingView
                } else if sonosService.zones.isEmpty {
                    noZonesView
                } else if isLandscape {
                    // Landscape: player left, library right
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView {
                            VStack(spacing: 16) {
                                nowPlayingSection
                                controlsSection
                                volumeSection
                            }
                        }
                        .frame(maxWidth: .infinity)

                        librarySection
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // Portrait: player on top, library below
                    ScrollView {
                        VStack(spacing: 16) {
                            nowPlayingSection
                            controlsSection
                            volumeSection
                            librarySection
                        }
                    }
                }

                if let error = sonosService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(HyggeTheme.destructive)
                }
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
        .background(HyggeTheme.cardBackground)
        .cornerRadius(20)
        .task {
            await sonosService.fetchSpeakers()
            await sonosService.fetchPlaybackState()
            await sonosService.fetchFavorites()
            sonosService.startPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            stationsService.reload()
        }
        .onDisappear {
            sonosService.stopPolling()
        }
        .sheet(isPresented: $showingZonePicker) {
            ZonePickerView(sonosService: sonosService, isPresented: $showingZonePicker)
        }
        .sheet(isPresented: $showingStationPicker) {
            StationPickerView(
                stationsService: stationsService,
                sonosService: sonosService,
                isPresented: $showingStationPicker
            )
        }
    }

    private var sectionHeader: some View {
        HStack {
            Image(systemName: "hifispeaker.2.fill")
                .font(.title2)
                .foregroundColor(HyggeTheme.accent)
            Text("Music")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()

            if !sonosService.zones.isEmpty {
                Button(action: { showingZonePicker = true }) {
                    HStack(spacing: 4) {
                        Text(sonosService.selectedZone?.coordinator ?? "Select Room")
                            .font(.subheadline)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(HyggeTheme.textSecondary)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Connecting to Sonos...")
                .font(.subheadline)
                .foregroundColor(HyggeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var noZonesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hifispeaker.slash")
                .font(.system(size: 48))
                .foregroundColor(HyggeTheme.textSecondary)
            Text("No Speakers Found")
                .font(.headline)
            Text("Check that your Sonos account is connected in Settings and speakers are on your network.")
                .font(.subheadline)
                .foregroundColor(HyggeTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    await sonosService.fetchSpeakers()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var nowPlayingSection: some View {
        VStack(spacing: 8) {
            // Use trackInfo if available, fallback to playbackState
            if let trackInfo = sonosService.trackInfo {
                if let title = trackInfo.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                if let artist = trackInfo.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(HyggeTheme.textSecondary)
                        .lineLimit(1)
                }

                if let album = trackInfo.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundColor(HyggeTheme.textSecondary)
                        .lineLimit(1)
                }
                
            } else if let state = sonosService.playbackState {
                // Fallback to playback state if track info isn't available yet
                if let title = state.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                }

                if let artist = state.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(HyggeTheme.textSecondary)
                        .lineLimit(1)
                }

                if let album = state.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundColor(HyggeTheme.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Text("Not Playing")
                    .font(.headline)
                    .foregroundColor(HyggeTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(HyggeTheme.cardBackgroundLight)
        .cornerRadius(12)
    }

    // MARK: - Inline Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Library")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(HyggeTheme.textSecondary)
                Spacer()
                Button {
                    showingStationPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .font(.caption)
                    .foregroundColor(HyggeTheme.accent)
                }
            }

            if sonosService.favorites.isEmpty && stationsService.stations.isEmpty {
                libraryEmptyState
            } else {
                VStack(spacing: 6) {
                    // Sonos Favorites
                    ForEach(sonosService.favorites.prefix(8)) { favorite in
                        libraryFavoriteRow(favorite)
                    }

                    // Saved stations
                    ForEach(stationsService.stations.prefix(8)) { station in
                        libraryStationRow(station)
                    }

                    // "See All" if there's more
                    let totalCount = sonosService.favorites.count + stationsService.stations.count
                    if totalCount > 8 {
                        Button {
                            showingStationPicker = true
                        } label: {
                            Text("See All (\(totalCount))")
                                .font(.caption)
                                .foregroundColor(HyggeTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private var libraryEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.title3)
                .foregroundColor(HyggeTheme.textTertiary)
            Text("No music saved")
                .font(.caption)
                .foregroundColor(HyggeTheme.textTertiary)
            Text("Tap + to add, or share from Spotify")
                .font(.caption2)
                .foregroundColor(HyggeTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(HyggeTheme.cardBackgroundLight)
        .cornerRadius(10)
    }

    private func libraryFavoriteRow(_ favorite: SonosFavorite) -> some View {
        Button {
            Task {
                await sonosService.playFavorite(favorite)
            }
        } label: {
            HStack(spacing: 10) {
                if let imageUrl = favorite.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                            .frame(width: 36, height: 36)
                            .background(HyggeTheme.cardBackgroundLight)
                    }
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
                } else {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(width: 36, height: 36)
                        .background(HyggeTheme.cardBackgroundLight)
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(favorite.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HyggeTheme.textPrimary)
                        .lineLimit(1)
                    if let service = favorite.service {
                        Text(service)
                            .font(.caption2)
                            .foregroundColor(HyggeTheme.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.body)
                    .foregroundColor(HyggeTheme.accent.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(HyggeTheme.cardBackgroundLight)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func libraryStationRow(_ station: Station) -> some View {
        Button {
            Task {
                await sonosService.playStation(station)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: station.source.iconName)
                    .font(.caption)
                    .foregroundColor(sourceColor(for: station.source))
                    .frame(width: 36, height: 36)
                    .background(sourceColor(for: station.source).opacity(0.12))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(station.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HyggeTheme.textPrimary)
                        .lineLimit(1)
                    Text(station.subtitle)
                        .font(.caption2)
                        .foregroundColor(HyggeTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.body)
                    .foregroundColor(HyggeTheme.accent.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(HyggeTheme.cardBackgroundLight)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func sourceColor(for source: StationSource) -> Color {
        switch source {
        case .spotify: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .appleMusic: return Color(red: 0.98, green: 0.34, blue: 0.38)
        case .tidal: return Color(red: 0.0, green: 0.78, blue: 0.85)
        case .deezer: return Color(red: 0.63, green: 0.29, blue: 0.88)
        case .stream: return HyggeTheme.accent
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 24) {
            Spacer()

            MediaButton(systemImage: "backward.fill") {
                Task { await sonosService.sendCommand(.previous) }
            }

            MediaButton(
                systemImage: sonosService.playbackState?.isPlaying == true ? "pause.fill" : "play.fill",
                isLarge: true
            ) {
                Task {
                    await sonosService.sendCommand(.pausePlay)
                }
            }

            MediaButton(systemImage: "forward.fill") {
                Task { await sonosService.sendCommand(.next) }
            }

            Spacer()
        }
    }

    private var volumeSection: some View {
        HStack(spacing: 16) {
            MediaButton(systemImage: "speaker.minus.fill", isSmall: true) {
                Task { await sonosService.sendCommand(.volumeDown) }
            }

            VStack(spacing: 4) {
                Slider(
                    value: $localVolume,
                    in: 0...100,
                    step: 1,
                    onEditingChanged: { editing in
                        isSliderDragging = editing
                        if !editing {
                            // User released the slider - send the final volume
                            Task {
                                await sonosService.setGroupVolume(to: Int(localVolume))
                            }
                        }
                    }
                )
                .tint(HyggeTheme.accent)
                .onChange(of: sonosService.playbackState?.volume) { _, newVolume in
                    // Only sync from Sonos when not dragging
                    if !isSliderDragging, let volume = newVolume {
                        localVolume = Double(volume)
                    }
                }

                Text("\(Int(localVolume))%")
                    .font(.caption)
                    .foregroundColor(HyggeTheme.textSecondary)
            }

            MediaButton(systemImage: "speaker.plus.fill", isSmall: true) {
                Task { await sonosService.sendCommand(.volumeUp) }
            }
        }
        .onAppear {
            // Initialize local volume from Sonos state
            if let volume = sonosService.playbackState?.volume {
                localVolume = Double(volume)
            }
        }
    }
}

struct MediaButton: View {
    let systemImage: String
    var isLarge: Bool = false
    var isSmall: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(isLarge ? .title : isSmall ? .body : .title3)
                .frame(width: isLarge ? 64 : isSmall ? 36 : 44,
                       height: isLarge ? 64 : isSmall ? 36 : 44)
                .background(isLarge ? HyggeTheme.accent.opacity(0.15) : HyggeTheme.cardBackground)
                .foregroundColor(isLarge ? HyggeTheme.accent : HyggeTheme.textPrimary)
                .cornerRadius(isLarge ? 32 : isSmall ? 8 : 12)
        }
        .buttonStyle(.plain)
    }
}

struct ZonePickerView: View {
    @ObservedObject var sonosService: SonosService
    @Binding var isPresented: Bool
    @State private var isGrouping = false
    @State private var selectedPlayerIds: Set<String> = []
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                if isGrouping {
                    groupingSection
                } else {
                    selectSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(isGrouping ? "Group Speakers" : "Select Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isGrouping ? "Cancel" : "Done") {
                        if isGrouping {
                            isGrouping = false
                            selectedPlayerIds.removeAll()
                        } else {
                            isPresented = false
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isGrouping {
                        Button("Group") {
                            applyGrouping()
                        }
                        .fontWeight(.semibold)
                        .disabled(selectedPlayerIds.count < 2 || isWorking)
                    } else {
                        Button {
                            enterGroupingMode()
                        } label: {
                            Label("Group Speakers", systemImage: "hifispeaker.2")
                        }
                    }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView("Updating…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Normal select mode

    private var selectSection: some View {
        Section {
            ForEach(sonosService.zones) { zone in
                Button {
                    if sonosService.selectedZone?.id == zone.id {
                        // Already selected — enter grouping mode for this zone
                        selectedPlayerIds = Set(zone.memberIds)
                        isGrouping = true
                    } else {
                        sonosService.selectZone(zone)
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: zone.isGroup ? "hifispeaker.2.fill" : "hifispeaker.fill")
                            .foregroundColor(HyggeTheme.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(zone.coordinator)
                                .font(.headline)
                            if zone.isGroup {
                                Text(zone.members.joined(separator: " + "))
                                    .font(.caption)
                                    .foregroundColor(HyggeTheme.textSecondary)
                            }
                        }

                        Spacer()

                        if sonosService.selectedZone?.id == zone.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(HyggeTheme.accent)
                        }
                    }
                }
                .foregroundColor(HyggeTheme.textPrimary)
            }
        } header: {
            Text("Rooms & Groups")
        }
    }

    // MARK: - Grouping mode

    private var groupingSection: some View {
        Section {
            ForEach(sonosService.allPlayers) { player in
                Button {
                    togglePlayer(player.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedPlayerIds.contains(player.id)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedPlayerIds.contains(player.id) ? HyggeTheme.accent : HyggeTheme.textSecondary)
                            .font(.title3)
                            .frame(width: 28)

                        Image(systemName: "hifispeaker.fill")
                            .foregroundColor(selectedPlayerIds.contains(player.id) ? HyggeTheme.accent : HyggeTheme.textSecondary)
                            .frame(width: 24)

                        Text(player.name)
                            .font(.body)

                        Spacer()

                        // Show current group membership
                        if let zone = currentZone(for: player.id), zone.isGroup {
                            Text("in \(zone.coordinator)")
                                .font(.caption)
                                .foregroundColor(HyggeTheme.textSecondary)
                        }
                    }
                }
                .foregroundColor(HyggeTheme.textPrimary)
            }
        } header: {
            Text("Select speakers to group together")
        } footer: {
            if selectedPlayerIds.count < 2 {
                Text("Select at least 2 speakers to create a group.")
            } else {
                let names = selectedPlayerIds.compactMap { id in
                    sonosService.allPlayers.first { $0.id == id }?.name
                }
                Text("Will group: \(names.joined(separator: " + "))")
            }
        }
    }

    // MARK: - Helpers

    private func togglePlayer(_ id: String) {
        if selectedPlayerIds.contains(id) {
            selectedPlayerIds.remove(id)
        } else {
            selectedPlayerIds.insert(id)
        }
    }

    private func currentZone(for playerId: String) -> SonosZone? {
        sonosService.zones.first { $0.memberIds.contains(playerId) }
    }

    private func enterGroupingMode() {
        // Pre-select current group members if a zone is selected
        if let zone = sonosService.selectedZone {
            selectedPlayerIds = Set(zone.memberIds)
        } else {
            selectedPlayerIds.removeAll()
        }
        isGrouping = true
    }

    private func applyGrouping() {
        let playerIds = Array(selectedPlayerIds)
        guard playerIds.count >= 2 else { return }

        isWorking = true
        Task {
            await sonosService.createGroup(playerIds: playerIds)
            isWorking = false
            isGrouping = false
            selectedPlayerIds.removeAll()
        }
    }
}

#Preview {
    MediaControlView(sonosService: SonosService())
        .padding()
        .background(HyggeTheme.background)
}
