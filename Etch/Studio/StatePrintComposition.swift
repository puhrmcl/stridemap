import SwiftUI

/// The single-state print: the state's map fills the page, with the state name and the enabled
/// metrics floating over a soft bottom scrim. When no metrics are enabled the map fills the whole
/// poster with nothing over it.
struct StatePrintComposition: View {
    var panelImage: UIImage
    var title: String
    var metrics: [(label: String, value: String)]
    var size: CGSize

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: panelImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()

            if !metrics.isEmpty {
                LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)

                VStack(spacing: 22) {
                    Text(title.uppercased())
                        .font(.etch(size: 56, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)

                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 46)
                            }
                            tile(item.label, item.value)
                        }
                    }
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 64)
                .padding(.top, 40)
                .frame(width: size.width)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Theme.Artwork.inkGround)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.etch(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.etch(size: 16, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}
