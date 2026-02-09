import AppKit
import SwiftUI

/// Window controller for the recording bar overlay
///
/// Creates a floating panel at the bottom of the screen that displays:
/// - Audio visualizer (animated bars)
/// - Live transcription text
class RecordingBarWindowController: NSObject {
    
    private var window: NSPanel?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupWindow()
    }
    
    // MARK: - Window Setup
    
    private func setupWindow() {
        // Get main screen dimensions
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        // Calculate window frame (bottom of screen)
        let barWidth = screenFrame.width * 0.6  // 60% of screen width
        let barHeight = Constants.UI.recordingBarHeight
        let barX = (screenFrame.width - barWidth) / 2 + screenFrame.minX
        let barY = screenFrame.minY + 20  // 20pt from bottom
        
        let windowFrame = NSRect(
            x: barX,
            y: barY,
            width: barWidth,
            height: barHeight
        )
        
        // Create panel with special properties
        let panel = NSPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel appearance
        panel.isFloatingPanel = true
        panel.level = .floating  // Always on top
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]  // Present on all spaces
        panel.ignoresMouseEvents = false  // Allow mouse interaction (for future features)
        
        // Create SwiftUI view
        let contentView = RecordingBarView()
            .environmentObject(AppStateManager.shared)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        
        panel.contentView = hostingView
        
        self.window = panel
    }
    
    // MARK: - Show/Hide
    
    /// Show the recording bar with animation
    func showBar() {
        guard let window = window else { return }
        
        // Reset position (in case screen changed)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let barWidth = screenFrame.width * 0.6
            let barX = (screenFrame.width - barWidth) / 2 + screenFrame.minX
            let barY = screenFrame.minY + 20
            
            let newFrame = NSRect(
                x: barX,
                y: barY,
                width: barWidth,
                height: Constants.UI.recordingBarHeight
            )
            
            window.setFrame(newFrame, display: false)
        }
        
        // Fade in animation
        window.alphaValue = 0
        window.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }
    
    /// Hide the recording bar with animation
    func hideBar() {
        guard let window = window else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}
