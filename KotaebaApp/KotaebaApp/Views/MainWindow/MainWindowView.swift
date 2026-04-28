import SwiftUI

/// Main application window with sidebar navigation
struct MainWindowView: View {
    @State private var selection: SidebarItem? = .home
    @AppStorage(Constants.UserDefaultsKeys.showDiagnosticsUI) private var showDiagnosticsUI = Constants.FeatureFlags.defaultDiagnosticsUI

    private var diagnosticsEnabled: Bool {
        Constants.FeatureFlags.showDiagnosticsUI
    }

    private var visibleSidebarItems: [SidebarItem] {
        var items: [SidebarItem] = [.home]
        items.append(.history)
        if diagnosticsEnabled {
            items.append(.diagnostics)
        }
        items.append(.settings)
        return items
    }

    var body: some View {
        NavigationSplitView {
            List(visibleSidebarItems, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection ?? .home {
            case .home:
                HomeDashboardView()
            case .history:
                TranscriptionHistoryView()
            case .diagnostics:
                if diagnosticsEnabled {
                    DiagnosticsView()
                } else {
                    HomeDashboardView()
                }
            case .settings:
                SettingsDetailView()
            }
        }
        .frame(width: Constants.UI.mainWindowWidth, height: Constants.UI.mainWindowHeight)
        .preferredColorScheme(.dark)
        .onAppear {
            ensureValidSelection()
        }
        .onChange(of: showDiagnosticsUI) { _, _ in
            ensureValidSelection()
        }
    }

    private func ensureValidSelection() {
        if !diagnosticsEnabled, selection == .diagnostics {
            selection = .home
        }
        if selection == nil {
            selection = .home
        }
    }
}

// MARK: - Sidebar

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"
    case diagnostics = "Test App"
    case settings = "Settings"

    static var visibleCases: [SidebarItem] {
        var items: [SidebarItem] = [.home]
        items.append(.history)
        if Constants.FeatureFlags.showDiagnosticsUI {
            items.append(.diagnostics)
        }
        items.append(.settings)
        return items
    }

    var id: String { rawValue }

    var title: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.arrow.circlepath"
        case .diagnostics: return "hammer.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Background Wrapper

struct AppBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Constants.UI.backgroundDark,
                    Color(hex: "151517")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
        }
    }
}

// MARK: - Home

struct HomeDashboardView: View {
    var body: some View {
        AppBackground {
            ScrollView(.vertical) {
                VStack(spacing: 20) {
                    HeaderView()
                        .padding(.top, 16)

                    ServerControlView()

                    StatisticsView()

                    Spacer(minLength: 12)

                    FooterView()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Test App

struct DiagnosticsView: View {
    var body: some View {
        AppBackground {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Test App")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Constants.UI.textPrimary)
                        .padding(.top, 16)

                    PermissionStatusView()
                    SimpleTestView()
                    TranscriptionTestView()

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Settings Detail

struct SettingsDetailView: View {
    var body: some View {
        AppBackground {
            SettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Constants.UI.accentOrange,
                                Constants.UI.accentOrange.opacity(0.7)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Kotaeba")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Constants.UI.textPrimary)

                Text("Voice-to-Text Assistant")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Constants.UI.textSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    var body: some View {
        HStack {
            Text("v\(Constants.appVersion)")
                .font(.caption2)
                .foregroundStyle(Constants.UI.textSecondary.opacity(0.6))

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    MainWindowView()
        .environmentObject(AppStateManager.shared)
}
