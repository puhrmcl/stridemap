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
        finish: FrameFinish?,
        onPhase: (Phase) -> Void
    ) async throws -> URL {
        let geometry = size.geometry
        guard size.deviceRenderable else { throw OrderError.resolutionTooLow(size) }

        onPhase(.rendering)
        var printRequest = request
        printRequest.printAspect = geometry.aspect
        printRequest.outputSize = .poster
        let longEdge = max(geometry.trimPixels.width, geometry.trimPixels.height)
        guard
            let image = await StudioRenderer.printImage(for: printRequest, longEdgePixels: longEdge),
            let data = image.pngData()
        else { throw OrderError.renderFailed }

        onPhase(.uploading)
        let assetID = UUID().uuidString.lowercased()
        try await upload(data, assetID: assetID, creationID: creationID, image: image)

        onPhase(.openingCheckout)
        let variant = try await ShopifyStorefront.variant(
            sku: size.shopifySKU(finish: finish),
            productHandle: product.shopifyHandle
        )
        return try await ShopifyStorefront.checkoutURL(
            variantID: variant.id,
            quantity: 1,
            attributes: [
                "_etch_asset_id": assetID,
                "_etch_creation_id": creationID,
                "_etch_sku": size.prodigiSKU,
                "_etch_frame": finish?.prodigiAttribute ?? "",
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

    private static func upload(
        _ data: Data, assetID: String, creationID: String, image: UIImage
    ) async throws {
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let pixels = CGSize(width: image.size.width * image.scale,
                            height: image.size.height * image.scale)

        var request = URLRequest(url: CommerceConfig.workerBase.appendingPathComponent("assets/\(assetID)"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(CommerceConfig.uploadToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.setValue(checksum, forHTTPHeaderField: "X-Checksum-SHA256")
        request.setValue(creationID, forHTTPHeaderField: "X-Creation-ID")
        request.setValue(AppInfo.changeTag, forHTTPHeaderField: "X-Renderer-Version")
        request.setValue("\(Int(pixels.width))x\(Int(pixels.height))", forHTTPHeaderField: "X-Pixel-Size")
        request.timeoutInterval = 180  // print files are tens of megabytes on cellular

        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let reason = String(data: body, encoding: .utf8) ?? "HTTP \(status)"
            throw OrderError.uploadFailed(reason)
        }
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
