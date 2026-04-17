import SwiftUI

/// Compact statistics display view
struct StatisticsView: View {
    @EnvironmentObject private var stateManager: AppStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Statistics")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.UI.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button(action: refreshStats) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Constants.UI.textSecondary.opacity(0.6))
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
                    value: formatNumber(stateManager.aggregatedStats.totalWords),
                    label: "Words"
                )

                CompactStatCard(
                    icon: "clock.fill",
                    value: stateManager.aggregatedStats.formattedDurationShort,
                    label: "Time"
                )

                CompactStatCard(
                    icon: "bolt.fill",
                    value: stateManager.aggregatedStats.formattedTimeSavedShort,
                    label: "Saved",
                    accentColor: Constants.UI.successGreen
                )

                CompactStatCard(
                    icon: "chart.bar.fill",
                    value: "\(stateManager.aggregatedStats.sessionCount)",
                    label: "Sessions"
                )
            }
        }
        .task {
            refreshStats()
        }
    }

    // MARK: - Helpers

    private func refreshStats() {
        stateManager.refreshStatistics()
    }

    private func formatNumber(_ number: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
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
                    .foregroundStyle(accentColor.opacity(0.8))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.UI.textPrimary)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Constants.UI.textSecondary.opacity(0.7))
            }
        }
        .padding(12)
        .background(Constants.UI.surfaceDark, in: .rect(cornerRadius: 10))
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
        .environmentObject(AppStateManager.shared)
}
