import SwiftUI

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
