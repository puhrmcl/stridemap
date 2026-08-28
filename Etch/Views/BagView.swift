import SwiftUI

/// The Bag: what you have ordered, and — once the cart exists — what you are about to.
///
/// It is a tab rather than a screen reached from inside a product page because of who it is for.
/// The customer this shop is built around finishes a marathon and wants three things: the book of
/// the year, the framed print of the race, the medal on the wall. Those are assembled in three
/// different places — Studio, a piece's own print sheet, a frame's picker — and a bag reachable
/// only from inside one of them is a bag the other two never reach. A persistent tab with a count
/// on it is what makes a basket feel like a basket rather than three separate purchases.
///
/// The cart itself is not built yet, so today this is the order history the app already keeps.
/// `OrderStore` is on-device by design — Etch has no account system, and the phone is the record.
struct BagView: View {
    @State private var orders: [PrintOrder] = []
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            Group {
                if orders.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing in your bag", systemImage: "bag")
                    } description: {
                        Text("Pieces you order appear here, and stay here — you can follow one from the press to your door.")
                    }
                } else {
                    List {
                        Section("Orders") {
                            ForEach(orders) { order in orderRow(order) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Bag")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await refresh() }
            .task { await refresh() }
        }
    }

    private func orderRow(_ order: PrintOrder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(order.productName)
                    .font(.system(.headline, design: .rounded))
                Spacer(minLength: 8)
                Text(order.sizeLabel)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(order.status.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusTint(order.status).opacity(0.14), in: .capsule)
                    .foregroundStyle(statusTint(order.status))
                Text(order.placedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let tracking = order.trackingURL {
                Link(destination: tracking) {
                    Label(order.carrier.map { "Track with \($0)" } ?? "Track this order",
                          systemImage: "shippingbox")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Status carries colour as well as words, so a bag of several orders can be read at a glance
    /// rather than line by line. `failed` is the only one that earns a warning colour — everything
    /// else is progress, and colouring progress red teaches people to ignore the colour.
    private func statusTint(_ status: PrintOrderStatus) -> Color {
        switch status {
        case .delivered:            return .green
        case .failed:               return .orange
        case .cancelled:            return .secondary
        default:                    return Theme.accent
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await OrderStore.shared.refreshActive()
        orders = OrderStore.shared.orders
        isRefreshing = false
    }
}
