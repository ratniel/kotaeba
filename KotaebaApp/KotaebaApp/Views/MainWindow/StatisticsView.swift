import SwiftUI
import SwiftData

/// Compact statistics display view
struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stats: AggregatedStats = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Statistics")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Constants.UI.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button(action: refreshStats) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(Constants.UI.textSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Compact 2x2 Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                CompactStatCard(
                    icon: "text.bubble.fill",
                    value: formatNumber(stats.totalWords),
                    label: "Words"
                )

                CompactStatCard(
                    icon: "clock.fill",
                    value: stats.formattedDurationShort,
                    label: "Time"
                )

                CompactStatCard(
                    icon: "bolt.fill",
                    value: stats.formattedTimeSavedShort,
                    label: "Saved",
                    accentColor: Constants.UI.successGreen
                )

                CompactStatCard(
                    icon: "chart.bar.fill",
                    value: "\(stats.sessionCount)",
                    label: "Sessions"
                )
            }
        }
        .onAppear {
            refreshStats()
        }
    }

    // MARK: - Helpers

    private func refreshStats() {
        let manager = StatisticsManager()
        stats = manager.getAggregatedStats()
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Compact Stat Card

struct CompactStatCard: View {
    let icon: String
    let value: String
    let label: String
    var accentColor: Color = Constants.UI.accentOrange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.8))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Constants.UI.textPrimary)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Constants.UI.textSecondary.opacity(0.7))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Constants.UI.surfaceDark)
        )
    }
}

// MARK: - Extensions

extension AggregatedStats {
    var formattedDurationShort: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(totalDuration))s"
        }
    }

    var formattedTimeSavedShort: String {
        let hours = Int(estimatedTimeSaved) / 3600
        let minutes = (Int(estimatedTimeSaved) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(estimatedTimeSaved))s"
        }
    }
}

#Preview {
    StatisticsView()
        .padding()
        .background(Constants.UI.backgroundDark)
}
