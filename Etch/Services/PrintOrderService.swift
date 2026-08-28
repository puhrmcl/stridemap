import Foundation
import UIKit
import CryptoKit

/// The order-time pipeline: render the piece at print resolution on-device, freeze it into the
/// fulfilment worker's asset store, and open a Shopify checkout whose line carries the hidden
/// properties that let the worker place the Prodigi order after payment.
///
///   render (StudioRenderer, 300 DPI)
///     → PUT {worker}/assets/{uuid}   (SHA-256 verified; immutable once ordered)
///     → cartCreate                   (_etch_asset_id / _etch_creation_id / _etch_sku / _etch_frame)
///     → Checkout Sheet Kit           (payment, address, receipt — all Shopify's)
///
/// The device holds no Prodigi or Shopify Admin credential; the upload token grants uploads
/// and nothing else.
@MainActor
enum PrintOrderService {

    static var isConfigured: Bool { CommerceConfig.isConfigured }

    enum OrderError: Error, LocalizedError {
        case renderFailed
        case resolutionTooLow(PrintSize)
        case uploadFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                return "The print file couldn't be rendered. Try again."
            case .resolutionTooLow(let size):
                return "\(size.label) can't be printed from this device yet."
            case .uploadFailed(let reason):
                return "The print file couldn't be uploaded. \(reason)"
            }
        }
    }

    /// Runs the whole pre-checkout pipeline and returns the URL to hand to Checkout Sheet Kit.
    /// `onPhase` reports progress so the order button can narrate what's happening.
    static func beginCheckout(
        request: StudioRenderer.Request,
        creationID: String,
        product: PrintProduct,
        size: PrintSize,
        finish: PrintFinish,
        onPhase: (Phase) -> Void
    ) async throws -> ShopifyStorefront.Cart {
        let geometry = size.geometry

        onPhase(.rendering)
        var printRequest = request
        printRequest.printAspect = geometry.aspect
        printRequest.outputSize = .poster

        // A hung print is the same artwork on a sheet whose top and bottom 15mm the wood covers,
        // so the artwork clears that band and the sheet around it is the piece's own ground.
        var reserve: CGFloat = 0
        if case .hanger = finish {
            reserve = (PosterHangerCatalog.hangerCoverMM / 25.4) / CGFloat(size.height)
        }

        // Streamed to disk a band at a time — the finished sheet is never one allocation, which
        // is what lets a 7200 × 10800 print exist on a phone at all.
        let fileURL = try await StudioRenderer.printFile(
            for: printRequest, geometry: geometry, reserveFraction: reserve
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        return try await checkout(
            fileAt: fileURL, pixels: geometry.trimPixels, creationID: creationID,
            shopifySKU: size.shopifySKU(finish: finish), prodigiSKU: size.prodigiSKU,
            productHandle: product.shopifyHandle, finishAttribute: finish.prodigiAttribute,
            onPhase: onPhase
        )
    }

    /// Uploads a print file that is already rendered and opens a cart for it.
    ///
    /// The poster path renders and then calls this; the Photo Wall renders a different way — its
    /// own grid at the frame's own resolution — and calls it directly. What matters is that both
    /// arrive here, so an order carries the same hidden line attributes whatever composed it, and
    /// the fulfilment worker has one shape of order to understand rather than two.
    static func checkout(
        fileAt fileURL: URL,
        pixels: CGSize,
        creationID: String,
        shopifySKU: String,
        prodigiSKU: String,
        productHandle: String,
        finishAttribute: String,
        contentType: String = "image/png",
        onPhase: (Phase) -> Void
    ) async throws -> ShopifyStorefront.Cart {
        onPhase(.uploading)
        let assetID = UUID().uuidString.lowercased()
        try await upload(fileAt: fileURL, assetID: assetID, creationID: creationID,
                         pixels: pixels, contentType: contentType)

        onPhase(.openingCheckout)
        let variant = try await ShopifyStorefront.variant(
            sku: shopifySKU, productHandle: productHandle
        )
        return try await ShopifyStorefront.cart(
            variantID: variant.id,
            quantity: 1,
            attributes: [
                "_etch_asset_id": assetID,
                "_etch_creation_id": creationID,
                "_etch_sku": prodigiSKU,
                "_etch_frame": finishAttribute,
            ]
        )
    }

    enum Phase {
        case rendering, uploading, openingCheckout

        var label: String {
            switch self {
            case .rendering:       return "Rendering your print…"
            case .uploading:       return "Preparing your order…"
            case .openingCheckout: return "Opening checkout…"
            }
        }
    }

    /// Uploads the print file straight from disk.
    ///
    /// Reading it into a `Data` first would undo what the banded renderer just achieved — a
    /// 24×36 PNG is tens of megabytes and the point was never to hold the whole sheet. The
    /// checksum is folded over the file in chunks for the same reason, and `upload(for:fromFile:)`
    /// streams the body rather than materialising it.
    /// `contentType` is a parameter rather than a constant because not every product ships a
    /// PNG. The Year Book is a multi-page PDF — the lab needs the file typed correctly to
    /// rasterise it, and the worker stores whatever is declared here and serves it back to
    /// Prodigi under the same type.
    private static func upload(
        fileAt url: URL, assetID: String, creationID: String, pixels: CGSize,
        contentType: String = "image/png"
    ) async throws {
        let checksum = try streamedSHA256(of: url)

        var request = URLRequest(url: CommerceConfig.workerBase.appendingPathComponent("assets/\(assetID)"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(CommerceConfig.uploadToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(checksum, forHTTPHeaderField: "X-Checksum-SHA256")
        request.setValue(creationID, forHTTPHeaderField: "X-Creation-ID")
        request.setValue(AppInfo.changeTag, forHTTPHeaderField: "X-Renderer-Version")
        request.setValue("\(Int(pixels.width))x\(Int(pixels.height))", forHTTPHeaderField: "X-Pixel-Size")
        request.timeoutInterval = 180  // print files are tens of megabytes on cellular

        let (body, response) = try await URLSession.shared.upload(for: request, fromFile: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let reason = String(data: body, encoding: .utf8) ?? "HTTP \(status)"
            throw OrderError.uploadFailed(reason)
        }
    }

    /// SHA-256 of a file, read in 1 MB chunks so the digest never costs more than a chunk.
    private static func streamedSHA256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Placed orders

/// The customer's orders, kept on-device (there is no account system — the phone is the record).
/// Written the moment Shopify reports checkout complete; status updates come from the worker's
/// `/orders/by-shopify/{id}` as the app revisits.
@MainActor
final class OrderStore {
    static let shared = OrderStore()

    private(set) var orders: [PrintOrder] = []

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("etch-orders.json")
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([PrintOrder].self, from: data) {
            orders = stored
        }
    }

    func record(_ order: PrintOrder) {
        orders.removeAll { $0.id == order.id }
        orders.insert(order, at: 0)
        persist()
    }

    /// Refreshes every non-terminal order from the worker. Quietly best-effort.
    func refreshActive() async {
        for (index, order) in orders.enumerated() where order.status.isActive {
            guard let shopifyID = order.shopifyOrderID else { continue }
            let url = CommerceConfig.workerBase.appendingPathComponent("orders/by-shopify/\(shopifyID)")
            guard
                let (data, response) = try? await URLSession.shared.data(from: url),
                (response as? HTTPURLResponse)?.statusCode == 200,
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            var updated = order
            if let raw = payload["status"] as? String, let status = PrintOrderStatus(rawValue: raw) {
                updated.status = status
            }
            if let tracking = payload["trackingURL"] as? String { updated.trackingURL = URL(string: tracking) }
            if let carrier = payload["carrier"] as? String { updated.carrier = carrier }
            orders[index] = updated
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(orders) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
