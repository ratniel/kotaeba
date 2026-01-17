import SwiftUI

/// Animated audio visualizer with bars that respond to amplitude
///
/// Shows a series of vertical bars that animate based on microphone input.
/// Each bar has a different update frequency for a wave-like effect.
struct AudioVisualizerView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var barHeights: [CGFloat] = Array(repeating: 0.2, count: Constants.UI.visualizerBarCount)
    
    var body: some View {
        HStack(spacing: Constants.UI.visualizerBarSpacing) {
            ForEach(0..<Constants.UI.visualizerBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: Constants.UI.visualizerBarWidth / 2)
                    .fill(barColor(for: barHeights[index]))
                    .frame(
                        width: Constants.UI.visualizerBarWidth,
                        height: barHeights[index] * Constants.UI.visualizerMaxHeight
                    )
                    .animation(
                        .spring(response: 0.15, dampingFraction: 0.6),
                        value: barHeights[index]
                    )
            }
        }
        .frame(height: Constants.UI.visualizerMaxHeight)
        .onChange(of: stateManager.audioAmplitude) { _, newAmplitude in
            updateBarHeights(amplitude: newAmplitude)
        }
        .onAppear {
            // Start with a subtle idle animation
            startIdleAnimation()
        }
    }
    
    // MARK: - Bar Updates
    
    /// Update bar heights based on audio amplitude
    private func updateBarHeights(amplitude: Float) {
        let baseHeight = CGFloat(amplitude)
        
        // Each bar has a slightly different response for wave effect
        for i in 0..<Constants.UI.visualizerBarCount {
            let offset = sin(Double(i) * 0.5) * 0.3
            let randomVariation = CGFloat.random(in: 0.8...1.2)
            let height = max(0.2, min(1.0, baseHeight * randomVariation + CGFloat(offset) * 0.2))
            barHeights[i] = height
        }
    }
    
    /// Idle animation when no audio (subtle wave)
    private func startIdleAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard stateManager.audioAmplitude < 0.1 else { return }
            
            for i in 0..<Constants.UI.visualizerBarCount {
                let time = Date().timeIntervalSince1970
                let wave = sin(time * 2.0 + Double(i) * 0.5) * 0.15 + 0.2
                barHeights[i] = CGFloat(wave)
            }
        }
    }
    
    /// Color gradient based on bar height (more intense = brighter)
    private func barColor(for height: CGFloat) -> Color {
        let intensity = height
        return Color(
            red: 1.0,
            green: 0.42 + Double(intensity) * 0.2,
            blue: 0.21 + Double(intensity) * 0.1
        )
    }
}

#Preview {
    AudioVisualizerView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
