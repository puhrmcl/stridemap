import SwiftUI

/// The brand sheet's UI elements, on one screen, so they can be photographed and held against
/// the reference.
///
/// Not a screen of the app. It exists because the project has no Mac and no test target: the
/// only way to know a component matches the sheet is for CI to render it and for a person to
/// compare the two pictures. `ETCH_PREVIEW=components` opens it.
struct ComponentSheetView: View {
    @State private var filter = "All"
    private let filters = ["All", "Runs", "Rides", "Hikes", "Races"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                group("Type hierarchy") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Every mile leaves a mark.")
                            .font(.etchDisplay(30))
                            .foregroundStyle(Theme.Ink.primary)
                        Text("Your journey. Your story. Etched forever.")
                            .font(.etchEditorial(21))
                            .foregroundStyle(Theme.Ink.primary)
                        Text("Etch automatically records your activities and transforms them "
                             + "into lasting achievements and beautiful artwork.")
                            .font(.etchBody(15))
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                }

                group("Metadata") {
                    EtchMetaColumns(columns: [
                        ("Location", "PHOENIX, ARIZONA"),
                        ("Date / data", "MAY 14, 2026"),
                    ])
                    EtchMetaColumns(columns: [
                        ("Stats", "26.2 MI  ·  3:48:12  ·  8:42 /MI"),
                    ])
                }

                group("Buttons") {
                    HStack(spacing: 14) {
                        Button("View activity") {}
                            .buttonStyle(.etchPrimary)
                        EtchCircleButton(systemName: "arrow.right") {}
                        Button("Share") {}
                            .buttonStyle(.etchSecondary)
                    }
                }

                group("Segmented control") {
                    EtchSegmentedControl(selection: $filter, options: filters) { $0 }
                }

                group("Activity card") {
                    EtchActivityCard(
                        title: "Morning Run",
                        symbol: "figure.run",
                        metrics: ["5.2 mi", "8:42 /mi", "45:18"],
                        context: ["May 14, 2026", "Phoenix, AZ"]
                    ) {
                        // A stand-in for the route tile: the sheet's card shows a warm map with
                        // the route drawn on it, and this screen has no run to snapshot.
                        ZStack {
                            Theme.Artwork.paper
                            Capsule()
                                .stroke(Theme.accent, lineWidth: 2)
                                .frame(width: 26, height: 58)
                                .rotationEffect(.degrees(-24))
                        }
                    }
                }

                group("Statistics") {
                    EtchStatStrip(stats: [
                        ("Total miles", "1,247"),
                        ("Achievements", "37"),
                        ("States", "18"),
                    ])
                    HStack(spacing: 12) {
                        StatTile(value: "1,247", label: "Total miles", systemName: "figure.run",
                                 accent: true)
                        StatTile(value: "37", label: "Achievements", systemName: "rosette")
                    }
                }

                group("Card") {
                    EtchCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Celebrate achievements.")
                                .font(.etchHeadline())
                                .foregroundStyle(Theme.Ink.primary)
                            Text("Collect memories.")
                                .font(.etchBody(15))
                                .foregroundStyle(Theme.Ink.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.Surface.background)
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .etchLabelStyle(10)
                .foregroundStyle(Theme.Ink.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
