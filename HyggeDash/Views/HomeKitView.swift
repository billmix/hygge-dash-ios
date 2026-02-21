import SwiftUI
import HomeKit

struct HomeKitView: View {
    @ObservedObject var homeKitManager: HomeKitManager

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader

            if !homeKitManager.isAuthorized {
                authorizationPrompt
            } else if homeKitManager.home == nil {
                noHomeView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !homeKitManager.scenes.isEmpty {
                            scenesSection
                        }

                        if !homeKitManager.lightAccessories.isEmpty {
                            lightsSection
                        }

                        if !homeKitManager.switchAccessories.isEmpty {
                            switchesSection
                        }
                    }
                }
            }

            if let error = homeKitManager.errorMessage {
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
    }

    private var sectionHeader: some View {
        HStack {
            Image(systemName: "house.fill")
                .font(.title2)
                .foregroundColor(.orange)
            Text("Home")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            if let homeName = homeKitManager.home?.name {
                Text(homeName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var authorizationPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("HomeKit Access Required")
                .font(.headline)
            Text("Please allow HomeKit access in Settings to control your smart home devices.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var noHomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Home Found")
                .font(.headline)
            Text("Set up a home in the Apple Home app to get started.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenes")
                .font(.headline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(homeKitManager.scenes, id: \.uniqueIdentifier) { scene in
                    SceneButton(scene: scene) {
                        homeKitManager.executeScene(scene)
                    }
                }
            }
        }
    }

    private var lightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lights")
                .font(.headline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(homeKitManager.lightAccessories, id: \.uniqueIdentifier) { accessory in
                    AccessoryButton(
                        accessory: accessory,
                        isOn: homeKitManager.isAccessoryOn(accessory),
                        brightness: homeKitManager.getBrightness(accessory)
                    ) {
                        homeKitManager.toggleAccessory(accessory)
                    }
                }
            }
        }
    }

    private var switchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switches")
                .font(.headline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(homeKitManager.switchAccessories, id: \.uniqueIdentifier) { accessory in
                    AccessoryButton(
                        accessory: accessory,
                        isOn: homeKitManager.isAccessoryOn(accessory),
                        brightness: nil
                    ) {
                        homeKitManager.toggleAccessory(accessory)
                    }
                }
            }
        }
    }
}

struct SceneButton: View {
    let scene: HMActionSet
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: sceneIcon)
                    .font(.title2)
                Text(scene.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.orange.opacity(0.15))
            .foregroundColor(.orange)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    private var sceneIcon: String {
        let name = scene.name.lowercased()
        if name.contains("morning") || name.contains("sunrise") {
            return "sunrise.fill"
        } else if name.contains("night") || name.contains("sleep") || name.contains("bedtime") {
            return "moon.fill"
        } else if name.contains("movie") || name.contains("cinema") {
            return "tv.fill"
        } else if name.contains("away") || name.contains("leave") {
            return "figure.walk"
        } else if name.contains("arrive") || name.contains("home") {
            return "house.fill"
        } else if name.contains("dinner") || name.contains("cooking") {
            return "fork.knife"
        } else if name.contains("relax") || name.contains("evening") {
            return "sparkles"
        } else {
            return "lightbulb.fill"
        }
    }
}

struct AccessoryButton: View {
    let accessory: HMAccessory
    let isOn: Bool
    let brightness: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                    .font(.title2)

                Text(accessory.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let brightness = brightness, isOn {
                    Text("\(brightness)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isOn ? Color.yellow.opacity(0.2) : Color(.secondarySystemBackground))
            .foregroundColor(isOn ? .orange : .secondary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeKitView(homeKitManager: HomeKitManager())
        .padding()
        .background(Color(.systemGroupedBackground))
}
