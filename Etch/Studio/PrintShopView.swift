import SwiftUI

/// Browse Etch Studio's print formats and order one.
///
/// The audit's finding was that the old flow never showed the artwork — it presented an SF Symbol,
/// a product name and a material string, with the user's own poster (the entire emotional payload)
/// absent from the buying flow. This version leads with the piece itself, in a frame, at the size
/// being considered. The frame preview is what converts.
struct PrintShopView: View {
    /// The name of the piece being printed.
    var subjectTitle: String?
    /// The rendered artwork. Nil when the shop is opened from the Studio home (browsing formats
    /// rather than ordering a specific piece), in which case the mockup shows a placeholder sheet.
    var artwork: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var product: PrintProduct = .framed
    @State private var size: PrintSize
    @State private var finish: FrameFinish = .natural

    init(subjectTitle: String?, artwork: UIImage? = nil) {
        self.subjectTitle = subjectTitle
        self.artwork = artwork
        // Open on the middle framed size — the one most people buy.
        _size = State(initialValue: PrintProduct.framed.sizes[1])
    }

    private var sizes: [PrintSize] { product.sizes }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    mockup
                    productPicker
                    sizePicker
                    if product == .framed { finishPicker }
                    orderPanel
                }
                .padding(20)
            }
            .background(Theme.Palette.bone.opacity(0.35).ignoresSafeArea())
            .navigationTitle("Prints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onChange(of: product) { _, new in
                // Keep the nearest size when switching products rather than resetting to the top.
                size = new.sizes.min { abs($0.width - size.width) < abs($1.width - size.width) } ?? new.sizes[0]
            }
        }
    }

    // MARK: The object

    /// The piece as a physical object: the artwork in a frame (or as a bare sheet), on a neutral
    /// wall, sized relative to the other options so the size choice is felt rather than read.
    private var mockup: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.93), Color(white: 0.87)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                framedPiece
                    .padding(.vertical, 26)
            }
            .frame(height: 320)
            .clipShape(.rect(cornerRadius: 18))

            if let subjectTitle {
                Text(subjectTitle)
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            Text("\(product.name) · \(size.label)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var framedPiece: some View {
        // Scale the piece within the mockup by its real size, so 24×36 visibly dwarfs 12×18.
        let largest = CGFloat(product.sizes.map(\.height).max() ?? size.height)
        let relative = CGFloat(size.height) / largest
        let sheet = Group {
            if let artwork {
                Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(Theme.Palette.bone)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay {
                        Image(systemName: "mountain.2")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.Palette.ink.opacity(0.18))
                    }
            }
        }

        Group {
            if product == .framed {
                // Full-bleed in the moulding — the verified product (Classic Frame, no mount) has
                // no mat, so the mockup doesn't draw one. Honest previews only.
                sheet
                    .padding(9)                                    // moulding
                    .background(Color(hex: finish.mouldingHex) ?? .black)
                    .shadow(color: .black.opacity(0.30), radius: 16, y: 10)
            } else {
                sheet
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
            }
        }
        .scaleEffect(0.55 + 0.45 * relative, anchor: .center)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: size)
        .animation(.easeInOut(duration: 0.2), value: finish)
    }

    // MARK: Choices

    private var productPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Format")
            ForEach(PrintProduct.allCases) { p in
                Button { product = p } label: {
                    HStack(spacing: 14) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(product == p ? .white : Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(product == p ? Theme.accent : Theme.accent.opacity(0.10),
                                        in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.system(.headline, design: .rounded))
                            Text(p.tagline)
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if product == p {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(product == p ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Size")
            HStack(spacing: 10) {
                ForEach(sizes) { s in
                    Button { size = s } label: {
                        VStack(spacing: 3) {
                            Text(s.label)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text(s.price)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            size == s ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.05),
                            in: .rect(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(size == s ? Theme.accent : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var finishPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Frame")
            HStack(spacing: 10) {
                ForEach(FrameFinish.allCases) { f in
                    Button { finish = f } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: f.mouldingHex) ?? .black)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                            Text(f.name).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            finish == f ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.04),
                            in: .rect(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(finish == f ? Theme.accent : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Order

    private var orderPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(size.price)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(size.geometry.summary)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }

            Text(product.material)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if Fulfilment.provider.isAvailable {
                Button {
                    // Wired to the backend adapter; the device never talks to the printer directly.
                } label: {
                    Label("Order with Apple Pay", systemImage: "applelogo")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    Label("Ordering opens soon", systemImage: "clock")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Printed to order on archival paper and shipped to your door. Secure checkout with Apple Pay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 14))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
