import SwiftUI
import PassKit
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

    // The Wallet pass, both directions: the buyer creates one to send, the recipient adds
    // their redeemed card to their own Wallet.
    @State private var passCodeField = ""
    @State private var passBusy = false
    @State private var passError: String?
    @State private var lastRedeemedCode: String?
    @State private var addingPass: PKPass?

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
        .sheet(item: Binding(
            get: { addingPass.map(IdentifiablePass.init) },
            set: { if $0 == nil { addingPass = nil } }
        )) { wrapped in
            AddPassSheet(pass: wrapped.pass).ignoresSafeArea()
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

                        Divider().padding(.vertical, 2)

                        // The gift as a card, not an email: paste the code Shopify sent and
                        // send a signed Wallet pass — Messages and AirDrop hand a .pkpass
                        // straight to the recipient's Wallet, QR code, amount and all.
                        Text("Or send it as an Apple Wallet pass")
                            .font(.etch(.subheadline, weight: .semibold))
                        TextField("Paste the code from the email", text: $passCodeField)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.footnote, design: .monospaced))
                        Button {
                            Task { await sharePass() }
                        } label: {
                            HStack {
                                if passBusy { ProgressView().padding(.trailing, 6) }
                                Label(passBusy ? "Creating pass…" : "Create Wallet pass to send",
                                      systemImage: "wallet.pass")
                                    .font(.etch(.subheadline, weight: .semibold))
                            }
                        }
                        .disabled(passBusy
                                  || passCodeField.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let passError {
                            Text(passError).font(.footnote).foregroundStyle(.red)
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
            if let code = lastRedeemedCode {
                Button {
                    Task { await addOwnPass(code: code) }
                } label: {
                    HStack {
                        if passBusy { ProgressView().padding(.trailing, 6) }
                        Label("Add to Apple Wallet", systemImage: "wallet.pass.fill")
                            .font(.etch(.subheadline, weight: .semibold))
                    }
                }
                .disabled(passBusy)
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
            let code = codeField.trimmingCharacters(in: .whitespacesAndNewlines)
            try await wallet.redeem(code)
            codeField = ""
            lastRedeemedCode = code
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

    // MARK: Wallet passes

    /// Buyer: create a signed pass around the emailed code and hand it to the share sheet —
    /// a .pkpass sent over Messages or AirDrop opens straight into the recipient's Wallet.
    private func sharePass() async {
        passBusy = true
        defer { passBusy = false }
        do {
            let data = try await GiftPassService.pass(
                code: passCodeField.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: selected.map { price($0.amountCents) }
            )
            // Validate before sharing: a pass PassKit can't parse would fail silently on the
            // recipient's phone, which is the worst place to find out.
            guard (try? PKPass(data: data)) != nil else {
                passError = GiftPassService.PassError.failed.errorDescription
                return
            }
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("Etch Gift Card.pkpass")
            try data.write(to: file)
            passError = nil
            AppShare.present([file])
        } catch {
            passError = (error as? LocalizedError)?.errorDescription
                ?? "The pass couldn't be created."
        }
    }

    /// Recipient: the redeemed card into their own Wallet.
    private func addOwnPass(code: String) async {
        passBusy = true
        defer { passBusy = false }
        do {
            let data = try await GiftPassService.pass(code: code, amount: nil)
            guard let pass = try? PKPass(data: data) else {
                redeemFailed = true
                redeemMessage = GiftPassService.PassError.failed.errorDescription
                return
            }
            addingPass = pass
        } catch {
            redeemFailed = true
            redeemMessage = (error as? LocalizedError)?.errorDescription
                ?? "The pass couldn't be created."
        }
    }
}

/// Wraps `PKAddPassesViewController` — the system "Add to Apple Wallet" sheet.
private struct AddPassSheet: UIViewControllerRepresentable {
    let pass: PKPass
    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

private struct IdentifiablePass: Identifiable {
    let pass: PKPass
    var id: String { pass.serialNumber }
}

private struct GiftCheckoutTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
