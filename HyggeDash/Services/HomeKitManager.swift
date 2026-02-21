import Foundation
import HomeKit
import Combine

@MainActor
class HomeKitManager: NSObject, ObservableObject {
    @Published var home: HMHome?
    @Published var rooms: [HMRoom] = []
    @Published var accessories: [HMAccessory] = []
    @Published var scenes: [HMActionSet] = []
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    private var homeManager: HMHomeManager?

    override init() {
        super.init()
    }

    func startHomeKit() {
        homeManager = HMHomeManager()
        homeManager?.delegate = self
    }

    func executeScene(_ scene: HMActionSet) {
        guard let home = home else { return }

        home.executeActionSet(scene) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Failed to execute scene: \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleAccessory(_ accessory: HMAccessory) {
        guard let characteristic = findPowerCharacteristic(for: accessory) else { return }

        let currentValue = characteristic.value as? Bool ?? false
        let newValue = !currentValue

        characteristic.writeValue(newValue) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Failed to toggle accessory: \(error.localizedDescription)"
                }
            }
        }
    }

    func setBrightness(_ accessory: HMAccessory, brightness: Int) {
        guard let characteristic = findBrightnessCharacteristic(for: accessory) else { return }

        characteristic.writeValue(brightness) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Failed to set brightness: \(error.localizedDescription)"
                }
            }
        }
    }

    func isAccessoryOn(_ accessory: HMAccessory) -> Bool {
        guard let characteristic = findPowerCharacteristic(for: accessory) else { return false }
        return characteristic.value as? Bool ?? false
    }

    func getBrightness(_ accessory: HMAccessory) -> Int? {
        guard let characteristic = findBrightnessCharacteristic(for: accessory) else { return nil }
        return characteristic.value as? Int
    }

    private func findPowerCharacteristic(for accessory: HMAccessory) -> HMCharacteristic? {
        for service in accessory.services {
            for characteristic in service.characteristics {
                if characteristic.characteristicType == HMCharacteristicTypePowerState {
                    return characteristic
                }
            }
        }
        return nil
    }

    private func findBrightnessCharacteristic(for accessory: HMAccessory) -> HMCharacteristic? {
        for service in accessory.services {
            for characteristic in service.characteristics {
                if characteristic.characteristicType == HMCharacteristicTypeBrightness {
                    return characteristic
                }
            }
        }
        return nil
    }

    func refreshAccessoryStates() {
        for accessory in accessories {
            for service in accessory.services {
                for characteristic in service.characteristics where characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                    characteristic.readValue { _ in }
                }
            }
        }
    }

    var lightAccessories: [HMAccessory] {
        accessories.filter { accessory in
            accessory.services.contains { service in
                service.serviceType == HMServiceTypeLightbulb
            }
        }
    }

    var switchAccessories: [HMAccessory] {
        accessories.filter { accessory in
            accessory.services.contains { service in
                service.serviceType == HMServiceTypeSwitch || service.serviceType == HMServiceTypeOutlet
            }
        }
    }
}

extension HomeKitManager: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.isAuthorized = true

            if let firstHome = manager.homes.first {
                self.home = firstHome
                self.rooms = firstHome.rooms
                self.accessories = firstHome.accessories
                self.scenes = firstHome.actionSets

                firstHome.delegate = self
                for accessory in firstHome.accessories {
                    accessory.delegate = self
                }

                self.refreshAccessoryStates()
            }
        }
    }
}

extension HomeKitManager: HMHomeDelegate {
    nonisolated func home(_ home: HMHome, didAdd accessory: HMAccessory) {
        Task { @MainActor in
            self.accessories = home.accessories
            accessory.delegate = self
        }
    }

    nonisolated func home(_ home: HMHome, didRemove accessory: HMAccessory) {
        Task { @MainActor in
            self.accessories = home.accessories
        }
    }

    nonisolated func home(_ home: HMHome, didAdd actionSet: HMActionSet) {
        Task { @MainActor in
            self.scenes = home.actionSets
        }
    }

    nonisolated func home(_ home: HMHome, didRemove actionSet: HMActionSet) {
        Task { @MainActor in
            self.scenes = home.actionSets
        }
    }
}

extension HomeKitManager: HMAccessoryDelegate {
    nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Task { @MainActor in
            self.objectWillChange.send()
        }
    }
}
