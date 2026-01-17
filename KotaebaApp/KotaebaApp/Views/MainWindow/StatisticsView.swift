import SwiftUI
import SwiftData

/// Statistics display view
struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stats: AggregatedStats = .empty
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Text("Statistics")
                    .font(.headline)
                    .foregroundColor(Constants.UI.textSecondary)
                
                Spacer()
                
                Button(action: refreshStats) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Constants.UI.textSecondary)
                }
                .buttonStyle(.plain)
            }
            
            // Stats Grid
            VStack(spacing: 0) {
                StatRowView(
                    icon: "text.bubble.fill",
                    label: "Words spoken",
                    value: formatNumber(stats.totalWords)
                )
                
                Divider()
                    .background(Constants.UI.backgroundDark)
                
                StatRowView(
                    icon: "clock.fill",
                    label: "Time talking",
                    value: stats.formattedDuration
                )
                
                Divider()
                    .background(Constants.UI.backgroundDark)
                
                StatRowView(
                    icon: "bolt.fill",
                    label: "Time saved",
                    value: "~\(stats.formattedTimeSaved)",
                    valueColor: Constants.UI.successGreen
                )
                
                Divider()
                    .background(Constants.UI.backgroundDark)
                
                StatRowView(
                    icon: "chart.bar.fill",
                    label: "Sessions",
                    value: "\(stats.sessionCount)"
                )
            }
            .padding(16)
            .background(Constants.UI.surfaceDark)
            .cornerRadius(12)
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

// MARK: - Stat Row

struct StatRowView: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = Constants.UI.textPrimary
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Constants.UI.accentOrange)
                .frame(width: 24)
            
            // Label
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Constants.UI.textSecondary)
            
            Spacer()
            
            // Value
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    StatisticsView()
        .padding()
        .background(Constants.UI.backgroundDark)
}
