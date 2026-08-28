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
    /// Whether Etch's own basemap archive is live in R2.
    ///
    /// Served rather than compiled because it is an *operational* fact — whether a 120 GB object
    /// finished uploading — not a property of the build. Flipping it turns the map editions from
    /// Apple snapshots (beautiful, unsellable) to Etch cartography (printable), and turns them
    /// back if a tile problem appears, neither of which should need an App Store release.
    /// Defaults false: a style pointed at a missing archive renders a blank rectangle, and a
    /// poster that silently loses its city is a defect the customer finds rather than us.
    var basemapReady: Bool = false
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

        /// How long an order takes to arrive, phrased for the product page — "Ships in 2–4
        /// business days", "Arrives by Dec 22".
        ///
        /// **Nil by default, and deliberately so.** This is the question every buyer asks before
        /// the button, and it is also the one number here that has never been measured: Prodigi's
        /// production time varies by lab and destination, and the range sheet quotes a target
        /// rather than an observed figure. Every other number in this file came from a live quote,
        /// so this one stays empty until real orders have been timed rather than shipping a guess
        /// the customer would hold us to. The row simply doesn't render while it's nil, and it
        /// costs a served-document edit — not a release — to turn on once the figure is real.
        var delivery: String?
    }

    struct Prices: Codable, Sendable, Equatable {
        /// Retail price in USD cents, keyed by Prodigi SKU — keyed rather than positional so a
        /// new size is a server edit, not a schema change. A SKU absent here keeps its
        /// compiled-in price.
        var bySKU: [String: Int]
        /// The Year Book's retail price in USD cents.
        var yearBookCents: Int
        /// The medal frame's retail price in USD cents.
        ///
        /// $249, set against a $150.90 landed cost — 36.4% after payment fees, the thinnest rung
        /// in the range. Still optional, because nil is the kill switch: clearing it unlists the
        /// product from the served document if UK shipping moves and the rung stops working.
        var medalFrameCents: Int?
        /// The Photo Wall's multi-photo frame, in USD cents.
        ///
        /// **Provisional.** Every other price here was set from a live Prodigi quote; this one is
        /// not, because the quote has not come back yet. It is compiled in so the product can be
        /// listed, and it is the first number to correct from the served document once the real
        /// landed cost lands. The reasoning behind it: the range sheet puts the entry size at £28
        /// wholesale, the 20 × 30" is roughly double that, and unlike the medal frame this one is
        /// made in the US — so no transatlantic shipping. $199 holds the range's margin against a
        /// landed cost around $90-110. Treat it as a placeholder with a rationale, not a quote.
        var photoWallCents: Int?
    }

    /// How much history an Archive style needs before it's offered. These are judgement calls
    /// made without real user data; being able to tune them against live behaviour is how they
    /// get right.
    struct ArchiveGates: Codable, Sendable, Equatable {
        var gridMinRoutedRuns: Int
        var ridgelineMinProfiles: Int
        var ringsMinRuns: Int
        // Unused since the style prune (Pulse, Bloom, Home Turf and Constellation were cut), but
        // kept in the schema: the served document still carries them, these fields are
        // non-optional, and dropping a key from a Codable struct is a config-format change that
        // would make older documents undecodable for no gain.
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
            closedDetail: "Printed to order on archival paper and shipped to your door. Secure checkout with Apple Pay.",
            delivery: nil
        ),
        prices: Prices(bySKU: [:], yearBookCents: 11900,
                       medalFrameCents: 24900, photoWallCents: 19900),
        basemapReady: false,
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
