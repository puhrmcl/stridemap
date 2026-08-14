import SwiftUI

/// Browse Etch Studio's print formats and sizes. Editorial and calm — the object leads, the
/// spec follows. Checkout (Stripe/Apple Pay → Prodigi) plugs into the size screen once the
/// fulfilment backend is live; until then the final step names the piece and says so plainly.
struct PrintShopView: View {
    /// The name of the piece being printed, when opened from a composed artwork.
    var subjectTitle: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let subjectTitle {
                        header(subjectTitle)
                    }
                    ForEach(PrintProduct.allCases) { product in
                        NavigationLink {
                            PrintSizesView(product: product, subjectTitle: subjectTitle)
                        } label: {
                            productCard(product)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Printed at local labs and shipped worldwide. Checkout opens soon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .navigationTitle("Prints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func header(_ title: String) -> some View {
        VStack(spacing: 4) {
            Text("Make it lasting")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private func productCard(_ product: PrintProduct) -> some View {
        HStack(spacing: 16) {
            Image(systemName: product.symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(.headline, design: .rounded))
                Text(product.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }
}

/// Sizes for a chosen product; selecting one leads to the (soon) checkout.
private struct PrintSizesView: View {
    let product: PrintProduct
    var subjectTitle: String?

    var body: some View {
        List {
            Section {
                ForEach(product.sizes) { size in
                    NavigationLink {
                        PrintOrderView(product: product, size: size, subjectTitle: subjectTitle)
                    } label: {
                        HStack {
                            Text(size.label).font(.system(.body, design: .rounded).weight(.medium))
                            Spacer()
                        }
                    }
                }
            } header: {
                Text("\(product.name) · sizes")
            } footer: {
                Text(product.material)
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The order screen. Names the exact piece; checkout arrives with the fulfilment backend.
private struct PrintOrderView: View {
    let product: PrintProduct
    let size: PrintSize
    var subjectTitle: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: product.symbol)
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 30)

                VStack(spacing: 6) {
                    if let subjectTitle {
                        Text(subjectTitle)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)
                    }
                    Text("\(product.name) · \(size.label)")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(product.material)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    Label("Ordering opens soon", systemImage: "clock")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Secure checkout with Apple Pay, printed to order and shipped to your door.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 16))
            }
            .padding(20)
        }
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
    }
}
