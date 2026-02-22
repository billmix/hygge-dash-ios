import SwiftUI

struct ContentView: View {
    @StateObject private var homeKitManager = HomeKitManager()
    @StateObject private var sonosService = SonosService()
    @StateObject private var sonosAuthService = SonosAuthService()
    @StateObject private var quotesService = QuotesService()
    @StateObject private var weatherService = WeatherService()

    @State private var showingSettings = false
    @State private var selectedTab = 0

    private let tabs: [(icon: String, label: String)] = [
        ("clock.fill", "Time"),
        ("quote.opening", "Quotes"),
        ("hifispeaker.2.fill", "Music"),
        ("house.fill", "Home"),
    ]

    var body: some View {
        ZStack {
            HyggeTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                // Carousel
                TabView(selection: $selectedTab) {
                    // Time & Weather
                    timeWeatherPage
                        .tag(0)

                    // Quotes
                    QuotesView(quotesService: quotesService)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .tag(1)

                    // Music
                    MediaControlView(sonosService: sonosService)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .tag(2)

                    // Home
                    HomeKitView(homeKitManager: homeKitManager)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Tab bar
                tabBar
            }

            if !sonosAuthService.isAuthenticated {
                connectOverlay
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

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hygge")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(HyggeTheme.textPrimary)
                Text(dateString)
                    .font(.caption)
                    .foregroundColor(HyggeTheme.textSecondary)
            }

            Spacer()

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundColor(HyggeTheme.textSecondary)
                    .padding(10)
                    .background(HyggeTheme.cardBackground)
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 20))
                        Text(tabs[index].label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(selectedTab == index ? HyggeTheme.accent : HyggeTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(HyggeTheme.background)
    }

    // MARK: - Time & Weather Page

    private var timeWeatherPage: some View {
        VStack(spacing: 16) {
            TimeWidgetView()
                .frame(maxHeight: .infinity)

            WeatherWidgetView(weatherService: weatherService)
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .tag(0)
    }

    // MARK: - Connect Overlay

    private var connectOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(HyggeTheme.accent)

                Text("Connect Your Sonos")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(HyggeTheme.textPrimary)

                Text("Sign in with your Sonos account to control your speakers.")
                    .font(.subheadline)
                    .foregroundColor(HyggeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    sonosAuthService.authenticate()
                } label: {
                    Text("Connect Sonos Account")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(HyggeTheme.accent)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)

                if let error = sonosAuthService.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(HyggeTheme.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button("Skip for Now") {
                    showingSettings = true
                }
                .font(.subheadline)
                .foregroundColor(HyggeTheme.textSecondary)
            }
            .padding(40)
            .background(HyggeTheme.cardBackground)
            .cornerRadius(24)
            .padding(40)
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
