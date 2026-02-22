import Foundation

/// Direct local UPnP/SOAP commands to Sonos speakers.
/// This bypasses the Sonos Cloud API and speaks directly to speakers on the LAN.
/// Required for playing music service content (Spotify, Apple Music, etc.)
/// since the Cloud API doesn't support arbitrary content loading.
enum SonosUPnP {

    // MARK: - Public API

    /// Clear the queue, add a share link, and start playing
    static func playShareLink(
        speakerIP: String,
        speakerUID: String,
        shareLink: ShareLinkInfo
    ) async throws {
        let (shareType, encodedURI) = extractForService(shareLink)
        let magic = magicValues(for: shareType)

        let enqueueURI = magic.prefix + encodedURI

        let metadata = buildDIDLMetadata(
            itemId: magic.key + encodedURI,
            itemClass: magic.itemClass,
            serviceNumber: shareLink.serviceId
        )

        print("🔌 [UPnP] Speaker: \(speakerIP), UID: \(speakerUID)")
        print("🔌 [UPnP] Enqueue URI: \(enqueueURI)")
        print("🔌 [UPnP] Service ID: \(shareLink.serviceId)")
        print("🔌 [UPnP] Share type: \(shareType)")
        print("🔌 [UPnP] Metadata: \(metadata)")

        // Step 1: Clear the queue
        try await clearQueue(speakerIP: speakerIP)

        // Step 2: Add to queue
        let queuePosition = try await addURIToQueue(
            speakerIP: speakerIP,
            enqueuedURI: enqueueURI,
            metadata: metadata
        )
        print("🔌 [UPnP] ✅ Added to queue at position: \(queuePosition)")

        // Step 3: Set queue as transport URI and play
        try await playFromQueue(speakerIP: speakerIP, speakerUID: speakerUID, index: queuePosition - 1)
        print("🔌 [UPnP] ✅ Playing from queue")
    }

    // MARK: - SOAP Actions

    /// Clear the Sonos queue
    static func clearQueue(speakerIP: String) async throws {
        let body = soapEnvelope(
            action: "RemoveAllTracksFromQueue",
            serviceType: "AVTransport",
            arguments: "<InstanceID>0</InstanceID>"
        )

        let (_, status) = try await sendSOAP(
            to: speakerIP,
            path: "/MediaRenderer/AVTransport/Control",
            action: "AVTransport",
            actionName: "RemoveAllTracksFromQueue",
            body: body
        )
        print("🔌 [UPnP] ClearQueue response: \(status)")
    }

    /// Add a URI to the queue
    static func addURIToQueue(
        speakerIP: String,
        enqueuedURI: String,
        metadata: String,
        position: Int = 0,
        asNext: Bool = false
    ) async throws -> Int {
        let escapedURI = enqueuedURI.xmlEscaped
        let escapedMeta = metadata.xmlEscaped

        let arguments =
            "<InstanceID>0</InstanceID>" +
            "<EnqueuedURI>\(escapedURI)</EnqueuedURI>" +
            "<EnqueuedURIMetaData>\(escapedMeta)</EnqueuedURIMetaData>" +
            "<DesiredFirstTrackNumberEnqueued>\(position)</DesiredFirstTrackNumberEnqueued>" +
            "<EnqueueAsNext>\(asNext ? 1 : 0)</EnqueueAsNext>"

        let body = soapEnvelope(
            action: "AddURIToQueue",
            serviceType: "AVTransport",
            arguments: arguments
        )

        let (responseData, status) = try await sendSOAP(
            to: speakerIP,
            path: "/MediaRenderer/AVTransport/Control",
            action: "AVTransport",
            actionName: "AddURIToQueue",
            body: body
        )

        print("🔌 [UPnP] AddURIToQueue response: \(status)")

        if status >= 400 {
            throw UPnPError.soapFailed(status)
        }

        // Parse the queue position from response
        let responseStr = String(data: responseData, encoding: .utf8) ?? ""
        if let range = responseStr.range(of: "<FirstTrackNumberEnqueued>"),
           let endRange = responseStr.range(of: "</FirstTrackNumberEnqueued>") {
            let numberStr = String(responseStr[range.upperBound..<endRange.lowerBound])
            return Int(numberStr) ?? 1
        }
        return 1
    }

    /// Set the queue as transport source and play from a specific index
    static func playFromQueue(speakerIP: String, speakerUID: String, index: Int) async throws {
        // Set the queue as the current transport URI
        let setURIArgs =
            "<InstanceID>0</InstanceID>" +
            "<CurrentURI>x-rincon-queue:\(speakerUID)#0</CurrentURI>" +
            "<CurrentURIMetaData></CurrentURIMetaData>"

        let setURIBody = soapEnvelope(
            action: "SetAVTransportURI",
            serviceType: "AVTransport",
            arguments: setURIArgs
        )

        let (_, setStatus) = try await sendSOAP(
            to: speakerIP,
            path: "/MediaRenderer/AVTransport/Control",
            action: "AVTransport",
            actionName: "SetAVTransportURI",
            body: setURIBody
        )
        print("🔌 [UPnP] SetAVTransportURI response: \(setStatus)")

        // Seek to the right track
        if index > 0 {
            let seekArgs =
                "<InstanceID>0</InstanceID>" +
                "<Unit>TRACK_NR</Unit>" +
                "<Target>\(index + 1)</Target>"

            let seekBody = soapEnvelope(
                action: "Seek",
                serviceType: "AVTransport",
                arguments: seekArgs
            )

            let (_, seekStatus) = try await sendSOAP(
                to: speakerIP,
                path: "/MediaRenderer/AVTransport/Control",
                action: "AVTransport",
                actionName: "Seek",
                body: seekBody
            )
            print("🔌 [UPnP] Seek response: \(seekStatus)")
        }

        // Play
        let playArgs =
            "<InstanceID>0</InstanceID>" +
            "<Speed>1</Speed>"
        let playBody = soapEnvelope(
            action: "Play",
            serviceType: "AVTransport",
            arguments: playArgs
        )

        let (_, playStatus) = try await sendSOAP(
            to: speakerIP,
            path: "/MediaRenderer/AVTransport/Control",
            action: "AVTransport",
            actionName: "Play",
            body: playBody
        )
        print("🔌 [UPnP] Play response: \(playStatus)")
    }

    // MARK: - SOAP Envelope

    private static func soapEnvelope(action: String, serviceType: String, arguments: String) -> String {
        return "<?xml version=\"1.0\"?>" +
            "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"" +
            " s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">" +
            "<s:Body>" +
            "<u:\(action) xmlns:u=\"urn:schemas-upnp-org:service:\(serviceType):1\">" +
            arguments +
            "</u:\(action)>" +
            "</s:Body>" +
            "</s:Envelope>"
    }

    private static func sendSOAP(
        to ip: String,
        path: String,
        action: String,
        actionName: String,
        body: String
    ) async throws -> (Data, Int) {
        let url = URL(string: "http://\(ip):1400\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // SOAPACTION must be quoted per UPnP spec
        request.setValue(
            "\"urn:schemas-upnp-org:service:\(action):1#\(actionName)\"",
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 10

        print("🔌 [UPnP] POST \(url)")
        print("🔌 [UPnP] SOAP body:\n\(body.prefix(500))")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode >= 400 {
            let responseBody = String(data: data, encoding: .utf8) ?? "nil"
            print("🔌 [UPnP] ❌ HTTP \(statusCode) response:\n\(responseBody)")
        }

        return (data, statusCode)
    }

    // MARK: - Share Link Helpers (mirrors SoCo's ShareLinkPlugin)

    private static func extractForService(_ parsed: ShareLinkInfo) -> (String, String) {
        // For Spotify: objectId is like "spotify:playlist:abc123"
        // encodedURI = "spotify%3aplaylist%3aabc123"
        let shareType = parsed.type  // "playlist", "track", "album", etc.
        let encodedURI = parsed.objectId.replacingOccurrences(of: ":", with: "%3a")
        return (shareType, encodedURI)
    }

    private struct MagicValues {
        let prefix: String
        let key: String
        let itemClass: String
    }

    private static func magicValues(for shareType: String) -> MagicValues {
        switch shareType {
        case "album":
            return MagicValues(
                prefix: "x-rincon-cpcontainer:1004206c",
                key: "00040000",
                itemClass: "object.container.album.musicAlbum"
            )
        case "track":
            return MagicValues(
                prefix: "",
                key: "00032020",
                itemClass: "object.item.audioItem.musicTrack"
            )
        case "episode":
            return MagicValues(
                prefix: "",
                key: "00032020",
                itemClass: "object.item.audioItem.musicTrack"
            )
        case "show":
            return MagicValues(
                prefix: "x-rincon-cpcontainer:1006206c",
                key: "1006206c",
                itemClass: "object.container.playlistContainer"
            )
        case "playlist":
            return MagicValues(
                prefix: "x-rincon-cpcontainer:1006206c",
                key: "1006206c",
                itemClass: "object.container.playlistContainer"
            )
        default:  // "song" (Deezer)
            return MagicValues(
                prefix: "",
                key: "10032020",
                itemClass: "object.item.audioItem.musicTrack"
            )
        }
    }

    /// Build DIDL-Lite metadata matching SoCo's format exactly
    private static func buildDIDLMetadata(itemId: String, itemClass: String, serviceNumber: String) -> String {
        return "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\"" +
            " xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\"" +
            " xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\"" +
            " xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">" +
            "<item id=\"\(itemId)\" parentID=\"-1\" restricted=\"true\">" +
            "<dc:title></dc:title>" +
            "<upnp:class>\(itemClass)</upnp:class>" +
            "<desc id=\"cdudn\" nameSpace=\"urn:schemas-rinconnetworks-com:metadata-1-0/\">" +
            "SA_RINCON\(serviceNumber)_X_#Svc\(serviceNumber)-0-Token" +
            "</desc>" +
            "</item>" +
            "</DIDL-Lite>"
    }

    // MARK: - Errors

    enum UPnPError: LocalizedError {
        case unsupportedURI
        case soapFailed(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedURI: return "Unsupported music service URL"
            case .soapFailed(let code): return "Speaker communication failed (HTTP \(code))"
            }
        }
    }
}

// MARK: - XML Escaping

private extension String {
    var xmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
