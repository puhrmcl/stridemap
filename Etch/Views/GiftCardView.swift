import SwiftUI
import ShopifyCheckoutSheetKit

/// Gift cards: buy one for someone, or redeem the one someone bought for you.
///
/// The flow leans on Shopify's native gift cards rather than inventing a parallel ledger.
/// Buying goes through the same checkout as every print; Shopify then emails the code, and the
/// buyer forwards it (or uses the share text here, which explains the whole ritual: download
/// Etch, sync your runs, redeem the code). Redeeming stores the code on this phone — Etch has
/// no accounts — and from then on every cart gets the credit applied *before* payment, so an
/// order is paid, or part-paid, the moment it is created.
struct GiftCardView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var denominations: [ShopifyStorefront.GiftDenomination] = []
    @State private var selected: ShopifyStorefront.GiftDenomination?
    @State private var loadError: String?
    @State private var isBuying = false
    @State private var checkout: URL?
    @State private var purchased = false

    @State private var wallet = GiftCardWallet.shared
    @State private var codeField = ""
    @State private var redeeming = false
    @State private var redeemMessage: String?
    @State private var redeemFailed = false

    var body: some View {
        List {
            buySection
            redeemSection
            howItWorks
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Gift Cards")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDenominations() }
        .sheet(item: Binding(
            get: { checkout.map { GiftCheckoutTarget(url: $0) } },
            set: { if $0 == nil { checkout = nil } }
        )) { target in
            CheckoutSheet(checkout: target.url)
                .title("Gift Card")
                .colorScheme(.automatic)
                .tintColor(UIColor(Theme.accent))
                .onCancel { checkout = nil }
                .onComplete { _ in
                    checkout = nil
                    purchased = true
                }
                .onFail { _ in checkout = nil }
        }
    }

    // MARK: Buying

    @ViewBuilder private var buySection: some View {
        Section {
            if let loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if denominations.isEmpty {
                HStack { ProgressView(); Text("Loading amounts…").foregroundStyle(.secondary) }
            } else {
                Picker("Amount", selection: $selected) {
                    ForEach(denominations) { d in
                        Text(price(d.amountCents)).tag(Optional(d))
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    Task { await buy() }
                } label: {
                    HStack {
                        if isBuying { ProgressView().padding(.trailing, 6) }
                        Text(isBuying ? "Opening checkout…" : "Buy Gift Card")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isBuying || selected == nil)

                if purchased {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Gift card purchased", systemImage: "checkmark.seal.fill")
                            .font(.etch(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("The card and its code arrive by email — forward it to your runner, or send them the note below with it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ShareLink(item: inviteText) {
                            Label("Share the invite", systemImage: "square.and.arrow.up")
                                .font(.etch(.subheadline, weight: .semibold))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Give Etch")
        } footer: {
            Text("A gift card prepays their order — any print, frame, book or wall. Delivered to your email by the shop; you pass it on.")
        }
    }

    // MARK: Redeeming

    @ViewBuilder private var redeemSection: some View {
        Section {
            if wallet.hasCodes {
                Label {
                    Text("Gift card on this phone — its balance comes off every order at checkout.")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "giftcard.fill").foregroundStyle(Theme.accent)
                }
                Button("Remove gift cards from this phone", role: .destructive) {
                    wallet.removeAll()
                }
                .font(.footnote)
            }
            TextField("Code from the gift card email", text: $codeField)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
            Button {
                Task { await redeem() }
            } label: {
                HStack {
                    if redeeming { ProgressView().padding(.trailing, 6) }
                    Text(redeeming ? "Checking…" : "Redeem")
                        .fontWeight(.semibold)
                }
            }
            .disabled(redeeming || codeField.trimmingCharacters(in: .whitespaces).isEmpty)
            if let redeemMessage {
                Text(redeemMessage)
                    .font(.footnote)
                    .foregroundStyle(redeemFailed ? .red : Theme.accent)
            }
        } header: {
            Text("Have a code?")
        } footer: {
            Text("Redeeming keeps the card on this phone. When you order, its balance is applied first — a big enough card pays the whole order.")
        }
    }

    private var howItWorks: some View {
        Section("How gifting works") {
            VStack(alignment: .leading, spacing: 10) {
                step("1", "Buy a gift card — the code arrives in your email.")
                step("2", "Send it to your runner, with the app invite.")
                step("3", "They download Etch, sync their activities, and redeem the code here.")
                step("4", "Their order is prepaid up to the card — they only pay any difference.")
            }
            .padding(.vertical, 4)
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.etch(.footnote, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent.opacity(0.15)))
                .foregroundStyle(Theme.accent)
            Text(text).font(.footnote)
        }
    }

    /// What travels beside the forwarded code. Written so the recipient needs nothing else.
    private var inviteText: String {
        """
        I got you an Etch gift card! Etch turns your runs into printed art — race posters, \
        photo walls, a book of your year.

        1. Download Etch from the App Store
        2. Sync your activities
        3. In Bag → Gift Cards, redeem the code I'm sending you

        Your order is prepaid up to the card. Happy running!
        """
    }

    // MARK: Actions

    private func loadDenominations() async {
        guard denominations.isEmpty else { return }
        do {
            denominations = try await ShopifyStorefront
                .giftDenominations(productHandle: CommerceConfig.giftProductHandle)
            selected = denominations.first { $0.amountCents >= 5000 } ?? denominations.first
        } catch {
            loadError = "Gift cards aren't available just yet."
        }
    }

    private func buy() async {
        guard let selected else { return }
        isBuying = true
        defer { isBuying = false }
        do {
            let cart = try await ShopifyStorefront.cart(
                variantID: selected.id, quantity: 1, attributes: [:]
            )
            checkout = cart.checkoutURL
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? "The checkout couldn't be opened."
        }
    }

    private func redeem() async {
        redeeming = true
        defer { redeeming = false }
        do {
            try await wallet.redeem(codeField)
            codeField = ""
            redeemFailed = false
            redeemMessage = "Gift card added — its balance comes off your next order."
        } catch {
            redeemFailed = true
            redeemMessage = (error as? LocalizedError)?.errorDescription
                ?? "That code couldn't be redeemed."
        }
    }

    private func price(_ cents: Int) -> String {
        let dollars = Double(cents) / 100
        return dollars == dollars.rounded() ? "$\(Int(dollars))"
                                            : String(format: "$%.2f", dollars)
    }
}

private struct GiftCheckoutTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
