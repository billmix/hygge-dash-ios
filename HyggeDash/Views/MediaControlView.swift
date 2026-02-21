import SwiftUI

struct MediaControlView: View {
    @ObservedObject var sonosService: SonosService
    @StateObject private var stationsService = StationsService()
    @State private var showingZonePicker = false
    @State private var showingStationPicker = false
    @State private var localVolume: Double = 20
    @State private var isSliderDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader

            if sonosService.isLoading && sonosService.zones.isEmpty {
                loadingView
            } else if sonosService.zones.isEmpty {
                noZonesView
            } else {
                VStack(spacing: 20) {
                    nowPlayingSection
                    playlistButton
                    controlsSection
                    volumeSection
                }
            }

            if let error = sonosService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .task {
            await sonosService.fetchSpeakers()
            await sonosService.fetchPlaybackState()
            sonosService.startPolling()
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
                .foregroundColor(.green)
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
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Connecting to Sonos...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var noZonesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hifispeaker.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Speakers Found")
                .font(.headline)
            Text("Check that your Sonos account is connected in Settings and speakers are on your network.")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let album = trackInfo.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let album = state.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Not Playing")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var playlistButton: some View {
        Button(action: {
            showingStationPicker = true
        }) {
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundColor(.green)
                Text("Playlists")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
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
                .tint(.green)
                .onChange(of: sonosService.playbackState?.volume) { _, newVolume in
                    // Only sync from server when not dragging
                    if !isSliderDragging, let volume = newVolume {
                        localVolume = Double(volume)
                    }
                }

                Text("\(Int(localVolume))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            MediaButton(systemImage: "speaker.plus.fill", isSmall: true) {
                Task { await sonosService.sendCommand(.volumeUp) }
            }
        }
        .onAppear {
            // Initialize local volume from server state
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
                .background(isLarge ? Color.green.opacity(0.15) : Color(.secondarySystemBackground))
                .foregroundColor(isLarge ? .green : .primary)
                .cornerRadius(isLarge ? 32 : isSmall ? 8 : 12)
        }
        .buttonStyle(.plain)
    }
}

struct ZonePickerView: View {
    @ObservedObject var sonosService: SonosService
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(sonosService.zones) { zone in
                Button(action: {
                    sonosService.selectedZone = zone
                    Task {
                        await sonosService.fetchPlaybackState()
                    }
                    isPresented = false
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(zone.coordinator)
                                .font(.headline)
                            if !zone.members.isEmpty {
                                Text(zone.members.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if sonosService.selectedZone?.id == zone.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
            .navigationTitle("Select Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    MediaControlView(sonosService: SonosService())
        .padding()
        .background(Color(.systemGroupedBackground))
}
