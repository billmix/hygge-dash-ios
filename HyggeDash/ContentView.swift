import SwiftUI

struct ContentView: View {
    @StateObject private var homeKitManager = HomeKitManager()
    @StateObject private var sonosService = SonosService()
    @StateObject private var sonosAuthService = SonosAuthService()
    @StateObject private var quotesService = QuotesService()
    @StateObject private var weatherService = WeatherService()

    @State private var showingSettings = false

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    headerView

                    if isLandscape {
                        landscapeLayout
                    } else {
                        portraitLayout
                    }
                }

                if !sonosAuthService.isAuthenticated {
                    connectOverlay
                }
            }
        }
        .onAppear {
            homeKitManager.startHomeKit()
            weatherService.startWeatherUpdates()
            sonosService.configure(authService: sonosAuthService)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(sonosService: sonosService, authService: sonosAuthService)
        }
    }

    private var backgroundGradient: some View {
        Color(red: 0.96, green: 0.96, blue: 0.96)
            .ignoresSafeArea()
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hygge")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(dateString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .background(Color(.systemBackground).opacity(0.8))
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var connectOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Connect Your Sonos")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Sign in with your Sonos account to control your speakers.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    sonosAuthService.authenticate()
                } label: {
                    Text("Connect Sonos Account")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)

                Button("Skip for Now") {
                    // Dismiss by navigating to settings later
                    showingSettings = true
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(40)
            .background(Color(.systemBackground))
            .cornerRadius(24)
            .shadow(radius: 20)
            .padding(40)
        }
    }

    private var landscapeLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 20) {
                // Left side - Quotes (1/3 of screen)
                QuotesView(quotesService: quotesService)
                    .frame(width: geometry.size.width * 0.33)

                // Right side - 2x2 Grid of widgets (2/3 of screen)
                VStack(spacing: 20) {
                    // Top row: Clock and Weather (shorter)
                    HStack(spacing: 20) {
                        TimeWidgetView()
                            .frame(maxWidth: .infinity)

                        WeatherWidgetView(weatherService: weatherService)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: geometry.size.height * 0.40)

                    // Bottom row: HomeKit and Music (taller for controls)
                    HStack(spacing: 20) {
                        HomeKitView(homeKitManager: homeKitManager)
                            .frame(maxWidth: .infinity)

                        MediaControlView(sonosService: sonosService)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: geometry.size.height * 0.56)
                }
                .frame(width: geometry.size.width * 0.67 - 20)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quotes at top in portrait
                QuotesView(quotesService: quotesService)
                    .frame(minHeight: 250)

                // HomeKit section
                HomeKitView(homeKitManager: homeKitManager)

                // Media controls
                MediaControlView(sonosService: sonosService)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
}

#Preview {
    ContentView()
}
