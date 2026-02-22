import UIKit
import Social
import UniformTypeIdentifiers

/// Share Extension that receives URLs from Spotify, Apple Music, etc.
/// Saves them to the shared App Group container so the main app can play them.
class ShareViewController: UIViewController {

    private let appGroupID = "group.com.hyggedash.app"
    private let storageKey = "savedStations"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.06, alpha: 0.95) // HyggeTheme.background

        handleIncomingItems()
    }

    private func handleIncomingItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                // Try URL first
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, error in
                        if let url = data as? URL {
                            self?.saveURL(url.absoluteString, title: item.attributedContentText?.string)
                        } else if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            self?.saveURL(url.absoluteString, title: item.attributedContentText?.string)
                        }
                    }
                    return
                }

                // Try plain text (might contain a URL)
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, error in
                        if let text = data as? String {
                            // Extract URL from text
                            let url = self?.extractURL(from: text) ?? text
                            self?.saveURL(url, title: item.attributedContentText?.string)
                        }
                    }
                    return
                }
            }
        }

        // Nothing useful found
        close()
    }

    private func extractURL(from text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if let match = matches?.first, let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }

    private func saveURL(_ urlString: String, title: String?) {
        let defaults = UserDefaults(suiteName: appGroupID)

        // Load existing stations
        var stations: [ShareStation] = []
        if let data = defaults?.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ShareStation].self, from: data) {
            stations = decoded
        }

        // Check for duplicates
        if stations.contains(where: { $0.url == urlString }) {
            DispatchQueue.main.async { [weak self] in
                self?.showConfirmation(message: "Already in library!")
            }
            return
        }

        // Detect source
        let source = detectSource(from: urlString)
        let contentType = detectContentType(from: urlString)
        let name = title ?? defaultName(source: source, contentType: contentType)

        // Create new station
        let newStation = ShareStation(
            id: UUID().uuidString,
            name: name,
            url: urlString,
            source: source,
            contentType: contentType,
            addedAt: ISO8601DateFormatter().string(from: Date())
        )

        // Prepend (newest first)
        stations.insert(newStation, at: 0)

        // Save back
        if let encoded = try? JSONEncoder().encode(stations) {
            defaults?.set(encoded, forKey: storageKey)
        }

        DispatchQueue.main.async { [weak self] in
            self?.showConfirmation(message: "Added to HyggeDash!")
        }
    }

    private func showConfirmation(message: String) {
        let banner = UIView()
        banner.backgroundColor = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1) // accent green
        banner.layer.cornerRadius = 16
        banner.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        icon.tintColor = .black
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.textColor = .black
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(stack)
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: banner.leadingAnchor, constant: 20),

            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            banner.heightAnchor.constraint(equalToConstant: 56),
            banner.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])

        banner.alpha = 0
        banner.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            banner.alpha = 1
            banner.transform = .identity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            UIView.animate(withDuration: 0.2) {
                banner.alpha = 0
            } completion: { _ in
                self?.close()
            }
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - Detection helpers (duplicated from ShareLinkParser since extensions can't share app code easily)

    private func detectSource(from url: String) -> String {
        let lower = url.lowercased()
        if lower.contains("spotify.com") || lower.hasPrefix("spotify:") { return "spotify" }
        if lower.contains("music.apple.com") { return "apple_music" }
        if lower.contains("tidal.com") || lower.hasPrefix("tidal:") { return "tidal" }
        if lower.contains("deezer.com") || lower.hasPrefix("deezer:") { return "deezer" }
        return "stream"
    }

    private func detectContentType(from url: String) -> String {
        let lower = url.lowercased()
        if lower.contains("/track/") || lower.contains(":track:") { return "track" }
        if lower.contains("/album/") || lower.contains(":album:") { return "album" }
        if lower.contains("/playlist/") || lower.contains(":playlist:") { return "playlist" }
        if lower.contains("/show/") || lower.contains(":show:") { return "show" }
        if lower.contains("/episode/") || lower.contains(":episode:") { return "episode" }
        return "unknown"
    }

    private func defaultName(source: String, contentType: String) -> String {
        let sourceName: String
        switch source {
        case "spotify": sourceName = "Spotify"
        case "apple_music": sourceName = "Apple Music"
        case "tidal": sourceName = "TIDAL"
        case "deezer": sourceName = "Deezer"
        default: sourceName = "Stream"
        }
        if contentType != "unknown" {
            return "\(sourceName) \(contentType.capitalized)"
        }
        return "\(sourceName) Link"
    }
}

// MARK: - Lightweight station struct for the extension (matches main app's Codable format)

/// Must match the main app's Station Codable format exactly
private struct ShareStation: Codable {
    let id: String
    let name: String
    let url: String
    let source: String
    let contentType: String
    let addedAt: String
}
