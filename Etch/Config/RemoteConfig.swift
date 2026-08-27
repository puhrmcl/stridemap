import Foundation

/// The values Etch can change without shipping a build — prices, what's orderable, the curation
/// thresholds, and seasonal copy. Everything here is *data*, never code: Apple forbids
/// downloading code that changes an app's behaviour, but a commerce app that can't correct a
/// price or a shipping deadline without a review cycle is a business risk.
///
/// The app always has a complete, working configuration compiled in (`defaults`). A fetched
/// document replaces it; a failed fetch changes nothing. Unknown fields are ignored and missing
/// ones fall back, so the server can add keys without breaking older installs.
struct EtchRemoteConfig: Codable, Sendable, Equatable {

    /// Bumped by whoever edits the served document — surfaced in Settings so a support
    /// conversation can establish which configuration a device is actually running.
    var version: Int

    var ordering: Ordering
    var prices: Prices
    var archive: ArchiveGates
    /// Nil when there's nothing seasonal to say.
    var seasonal: Seasonal?

    struct Ordering: Codable, Sendable, Equatable {
        /// A kill switch: false presents the shop as "opening soon" even with tokens configured,
        /// so a fulfilment problem can be contained without an App Store release.
        var enabled: Bool
        /// Shown in place of the order button when `enabled` is false.
        var closedTitle: String
        var closedDetail: String
    }

    struct Prices: Codable, Sendable, Equatable {
        /// Retail price in USD cents, keyed by Prodigi SKU — keyed rather than positional so a
        /// new size is a server edit, not a schema change. A SKU absent here keeps its
        /// compiled-in price.
        var bySKU: [String: Int]
        /// The Year Book's retail price in USD cents.
        var yearBookCents: Int
        /// The medal frame's retail price in USD cents. Optional because the rung isn't set
        /// until a real quote lands — its wholesale is the highest in the range and it ships
        /// from the UK, so guessing it would be guessing at a loss.
        var medalFrameCents: Int?
        /// The Photo Wall's multi-photo frame, in USD cents. Optional for the same reason as
        /// the medal frame: no rung until a real quote lands.
        var photoWallCents: Int?
    }

    /// How much history an Archive style needs before it's offered. These are judgement calls
    /// made without real user data; being able to tune them against live behaviour is how they
    /// get right.
    struct ArchiveGates: Codable, Sendable, Equatable {
        var gridMinRoutedRuns: Int
        var ridgelineMinProfiles: Int
        var ringsMinRuns: Int
        var pulseMinRuns: Int
        var constellationMinCells: Int
        var bloomMinRoutedRuns: Int
    }

    /// A dated message — the Christmas shipping deadline being the case that matters, since the
    /// date moves and a wrong one is worse than none.
    struct Seasonal: Codable, Sendable, Equatable {
        var message: String
        /// ISO-8601 date; the message hides itself after this instant.
        var expires: Date?

        var isActive: Bool {
            guard let expires else { return !message.isEmpty }
            return !message.isEmpty && expires > .now
        }
    }

    /// The configuration compiled into the binary: correct as shipped, and the floor the app
    /// falls back to when the network is unavailable or the document is malformed.
    static let defaults = EtchRemoteConfig(
        version: 0,
        ordering: Ordering(
            enabled: true,
            closedTitle: "Ordering opens soon",
            closedDetail: "Printed to order on archival paper and shipped to your door. Secure checkout with Apple Pay."
        ),
        prices: Prices(bySKU: [:], yearBookCents: 11900,
                       medalFrameCents: nil, photoWallCents: nil),
        archive: ArchiveGates(
            gridMinRoutedRuns: 20,
            ridgelineMinProfiles: 12,
            ringsMinRuns: 30,
            pulseMinRuns: 30,
            constellationMinCells: 4,
            bloomMinRoutedRuns: 50
        ),
        seasonal: nil
    )
}

/// Holds the configuration in force. Reads happen from renderers, catalogues and views on
/// several actors, so access is lock-guarded rather than actor-isolated — the same shape as
/// `USStateBoundaries`.
final class RemoteConfigStore: @unchecked Sendable {
    static let shared = RemoteConfigStore()

    private let lock = NSLock()
    private var stored = EtchRemoteConfig.defaults

    private init() {}

    var config: EtchRemoteConfig {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Convenience: `EtchConfig.current.prices…` anywhere.
enum EtchConfig {
    static var current: EtchRemoteConfig { RemoteConfigStore.shared.config }

    /// Retail price in cents for a SKU — the served price when one exists, else the catalogue's
    /// compiled default.
    static func priceCents(sku: String, default fallback: Int) -> Int {
        current.prices.bySKU[sku] ?? fallback
    }
}

/// Fetches the served configuration and caches it on disk, so a launch with no network still
/// runs the last known-good document rather than reverting to build-time values.
enum RemoteConfigService {

    private static var cacheURL: URL? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return directory.appendingPathComponent("etch-config.json")
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Loads the cached document synchronously. Called before the first view renders, so the
    /// catalogue never briefly shows a stale compiled price and then flips.
    static func loadCached() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let config = try? decoder.decode(EtchRemoteConfig.self, from: data) else { return }
        RemoteConfigStore.shared.config = config
    }

    /// Fetches the current document and adopts it. Silent on failure — the app keeps whatever
    /// it already had.
    static func refresh() async {
        let endpoint = CommerceConfig.workerBase.appendingPathComponent("config")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let config = try? decoder.decode(EtchRemoteConfig.self, from: data) else { return }
        RemoteConfigStore.shared.config = config
        if let cacheURL { try? data.write(to: cacheURL, options: .atomic) }
    }
}
