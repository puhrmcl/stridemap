import SwiftUI

/// The complication gallery — retuning a poster data slot the way a watch face slot is retuned.
///
/// Every data point the activity tracked is shown with its *live value* for this run, so the
/// choice is between real numbers, not abstract names. Metrics the run didn't record are greyed
/// rather than hidden — the full vocabulary stays visible, availability stays honest.
struct MetricPickerSheet: View {
    let run: Run
    let current: StatMetric
    /// Whether this slot can be removed entirely (data slots yes; the headline collapses to
    /// Blank instead, keeping the composition's slot count stable).
    let allowRemove: Bool
    var onPick: (StatMetric) -> Void
    var onRemove: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var metrics: [StatMetric] { StatMetric.allCases.filter { $0 != .none } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(metrics) { metric in
                        let available = metric.isAvailable(for: run)
                        Button {
                            onPick(metric)
                            dismiss()
                        } label: {
                            chip(metric, available: available, selected: metric == current)
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                    }
                }
                .padding(16)

                VStack(spacing: 10) {
                    Button {
                        onPick(.none)
                        dismiss()
                    } label: {
                        Label("Leave Blank", systemImage: "circle.dashed")
                            .font(.etch(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    if allowRemove, let onRemove {
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Label("Remove Data Point", systemImage: "minus.circle")
                                .font(.etch(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.red.opacity(0.10), in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .navigationTitle("Data Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func chip(_ metric: StatMetric, available: Bool, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Text(available ? (metric.value(for: run) ?? "—") : "—")
                .font(.etch(size: 16, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            HStack(spacing: 4) {
                Image(systemName: metric.icon).font(.system(size: 9, weight: .semibold))
                Text(metric.label)
                    .font(.etch(size: 9, weight: .semibold))
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .padding(.horizontal, 6)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2)
        }
        .opacity(available ? 1 : 0.35)
    }
}
