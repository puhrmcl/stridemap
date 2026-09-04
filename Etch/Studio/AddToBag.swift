import SwiftUI
import ShopifyCheckoutSheetKit
import ShopifyAcceleratedCheckouts

/// Where a finished composition goes when the reader commits to it.
///
/// Every product editor renders and uploads the same way and then does one of two things with the
/// result, so the fork is a parameter rather than a second copy of the render path. A line that was
/// bagged and a line that was bought carry identical attributes — the fulfilment worker cannot tell
/// them apart, and does not have to.
enum StudioOrderDestination {
    case checkout, bag
}

/// The bag action, beside a product's order button.
///
/// One view rather than five copies of the same capsule. The Print Shop had this button for a
/// while and nothing else did, so five of the eight products in Studio could only be bought one at
/// a time — you could compose a book and a photo wall and then had to pay two shipping charges to
/// own both. The chrome here is the Print Shop's, unchanged, so the control means the same thing
/// wherever it appears.
struct AddToBagButton: View {
    var isWorking: Bool
    var isDisabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Adding…")
                    }
                } else {
                    Label("Add to Bag", systemImage: "bag.badge.plus")
                }
            }
            .font(.etch(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isWorking)
    }
}

/// The payment step, once a prepared cart exists: Apple Pay and Shop Pay natively, with the
/// hosted checkout behind "Other ways to pay".
///
/// The Print Shop grew this first and the other editors kept opening the hosted sheet directly,
/// which meant Apple Pay existed on one product page out of five. The two-step order it encodes
/// is deliberate: the artwork is rendered and frozen into the fulfilment worker *before* money
/// can move, so a paid order with no file behind it cannot exist — the wallet buttons appear
/// after preparation, never instead of it.
struct PreparedWalletPanel: View {
    let cart: ShopifyStorefront.Cart
    var onComplete: (CheckoutCompletedEvent) -> Void
    var onFail: (String) -> Void
    /// Opens the hosted checkout for the same cart — card, PayPal, whatever Shopify offers.
    var openHosted: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            AcceleratedCheckoutButtons(cartID: cart.id)
                .wallets([.applePay, .shopPay])
                .cornerRadius(14)
                .onComplete { event in onComplete(event) }
                .onFail { error in onFail(error.localizedDescription) }
                .environmentObject(ShopifyAcceleratedCheckouts.Configuration(
                    storefrontDomain: CommerceConfig.shopDomain,
                    storefrontAccessToken: CommerceConfig.storefrontToken
                ))
                .environmentObject(ShopifyAcceleratedCheckouts.ApplePayConfiguration(
                    merchantIdentifier: ApplePayConfig.merchantIdentifier,
                    contactFields: ApplePayConfig.requiresPhone ? [.email, .phone] : [.email],
                    supportedShippingCountries: ApplePayConfig.supportedShippingCountries
                ))
            Button(action: openHosted) {
                Text("Other ways to pay")
                    .font(.etch(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }
}

/// The served shipping line — "Free standard shipping" — wherever an order can start.
///
/// Served rather than compiled because it is a promise about money: if the store's shipping
/// zones change, the note has to change the same day, not the next release. Renders nothing
/// while the config carries no line.
struct DeliveryNote: View {
    var body: some View {
        if let delivery = EtchConfig.current.ordering.delivery, !delivery.isEmpty {
            Label(delivery, systemImage: "shippingbox")
                .font(.etch(.footnote, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
    }
}

/// The proof-approval gate, ahead of every order path.
///
/// A print is unreturnable in the way a t-shirt is not — it is the customer's own artwork, made
/// to order — so the buying flow asks them to look at exactly what will be printed and say so
/// before Order and Add to Bag unlock. Until approved this is the page's one call to action;
/// after, it collapses to a quiet confirmation with a way to look again. Every editor drops the
/// approval the moment the piece changes under it, the same rule as a prepared cart.
struct ProofGateButton: View {
    var approved: Bool
    var title: String = "Approve Your Artwork"
    /// Opens the proof (or, for the book, its acknowledgment dialog).
    var action: () -> Void
    /// Re-opens the proof after approval; nil hides the link.
    var viewAgain: (() -> Void)? = nil

    var body: some View {
        if approved {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Artwork approved")
                    .font(.etch(.subheadline, weight: .semibold))
                Spacer(minLength: 8)
                if let viewAgain {
                    Button("View artwork", action: viewAgain)
                        .font(.etch(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.green.opacity(0.10), in: .rect(cornerRadius: 14))
        } else {
            Button(action: action) {
                Label(title, systemImage: "doc.text.magnifyingglass")
                    .font(.etch(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }
}

/// The proof, full screen, with the one question that matters.
///
/// The image is the piece as composed — the same recipe the print file renders from — shown in
/// the dark inspection room with pinch-zoom, so a name, a date or a route can actually be
/// checked rather than glanced at. Approving closes the room and unlocks the order; the close
/// button leaves without approving.
struct ProofApprovalView: View {
    let image: UIImage?
    var onApprove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ArtworkPreviewView(image: image)

            VStack(spacing: 10) {
                Text("Check the names, dates, route and spelling. The artwork you approve is exactly what we’ll print.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                Button {
                    onApprove()
                    dismiss()
                } label: {
                    Label("Approve artwork", systemImage: "checkmark.seal")
                        .font(.etch(.headline))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

/// The confirmation that follows a successful add: a capsule that drops in at the top of the
/// screen and takes itself away.
///
/// It matters more here than a toast usually would. Adding to a bag is the one action in Studio
/// whose result is invisible — the editor does not change, and the bag is on another screen — so
/// without this the button reads as having done nothing, and the reliable next thing someone does
/// is press it again.
private struct AddedToBagToast: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    Label("Added to your bag", systemImage: "checkmark.circle.fill")
                        .font(.etch(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.accent, in: .capsule)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: isPresented)
    }
}

extension View {
    func addedToBagToast(_ isPresented: Binding<Bool>) -> some View {
        modifier(AddedToBagToast(isPresented: isPresented))
    }
}
