import SwiftUI

struct ContentView: View {
    @AppStorage("hideExplore") private var hideExplore = true
    @AppStorage("selectedPlatform") private var selectedRaw = Platform.instagram.rawValue
    @State private var loaded: Set<Platform> = []
    @State private var showSettings = false

    private var selected: Platform { Platform(rawValue: selectedRaw) ?? .instagram }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            // Each site stays alive once opened, so switching back is instant.
            ForEach(Platform.allCases) { platform in
                if loaded.contains(platform) {
                    BlockingWebView(platform: platform, settings: BlockerSettings(hideExplore: hideExplore))
                        .id("\(platform.rawValue)-\(hideExplore)")
                        .opacity(platform == selected ? 1 : 0)
                        .scaleEffect(platform == selected ? 1 : 0.97)
                        .allowsHitTesting(platform == selected)
                }
            }

            FloatingSwitcher(selected: selected, onSelect: select, onSettings: { showSettings = true })
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: selectedRaw)
        .onAppear { loaded.insert(selected) }
        .sheet(isPresented: $showSettings) {
            SettingsView(hideExplore: $hideExplore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func select(_ platform: Platform) {
        loaded.insert(platform)
        selectedRaw = platform.rawValue
    }
}

// MARK: - Floating, draggable app switcher

struct FloatingSwitcher: View {
    let selected: Platform
    let onSelect: (Platform) -> Void
    let onSettings: () -> Void

    @State private var isOpen = false
    @State private var dragOffset: CGSize = .zero
    @AppStorage("bubbleX") private var savedX: Double = -1
    @AppStorage("bubbleY") private var savedY: Double = -1

    private let bubbleSize: CGFloat = 50
    private let spacing: CGFloat = 60
    private let edgeMargin: CGFloat = 14

    private enum Item: Hashable { case site(Platform), settings }
    private var items: [Item] { Platform.allCases.map { Item.site($0) } + [.settings] }

    var body: some View {
        GeometryReader { geo in
            let base = basePosition(in: geo.size)
            let center = CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
            let opensUp = base.y > geo.size.height / 2

            ZStack {
                if isOpen {
                    // Tap anywhere else to close.
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture { toggle(false) }
                        .transition(.opacity)
                }

                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let distance = CGFloat(index + 1) * spacing
                    menuButton(item)
                        .scaleEffect(isOpen ? 1 : 0.3)
                        .opacity(isOpen ? 1 : 0)
                        .offset(y: isOpen ? 0 : (opensUp ? distance : -distance))
                        .animation(.spring(response: 0.35, dampingFraction: 0.75)
                                    .delay(isOpen ? Double(index) * 0.04 : 0), value: isOpen)
                        .allowsHitTesting(isOpen)
                        .position(x: center.x, y: center.y + (opensUp ? -distance : distance))
                }

                bubble
                    .onTapGesture { toggle(!isOpen) }
                    .gesture(dragGesture(in: geo.size))
                    .position(center)
            }
        }
    }

    // MARK: Pieces

    private var bubble: some View {
        Image(systemName: isOpen ? "xmark" : selected.systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isOpen ? Color.primary : Color(uiColor: selected.uiTint))
            .frame(width: bubbleSize, height: bubbleSize)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .scaleEffect(dragOffset == .zero ? 1 : 1.12)
            .contentShape(Circle())
    }

    @ViewBuilder
    private func menuButton(_ item: Item) -> some View {
        switch item {
        case .site(let platform):
            circle(icon: platform.systemImage,
                   tint: Color(uiColor: platform.uiTint),
                   highlighted: platform == selected)
                .onTapGesture {
                    toggle(false)
                    onSelect(platform)
                }
        case .settings:
            circle(icon: "gearshape.fill", tint: .gray, highlighted: false)
                .onTapGesture {
                    toggle(false)
                    onSettings()
                }
        }
    }

    private func circle(icon: String, tint: Color, highlighted: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : tint)
            .frame(width: bubbleSize, height: bubbleSize)
            .background(highlighted ? AnyShapeStyle(tint) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .contentShape(Circle())
    }

    // MARK: Behaviour

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if isOpen { toggle(false) }
                dragOffset = value.translation
            }
            .onEnded { value in
                let base = basePosition(in: size)
                let end = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let margin = bubbleSize / 2 + edgeMargin
                // Stick to whichever side edge is closer.
                let snappedX = end.x < size.width / 2 ? margin : size.width - margin
                let target = clamp(CGPoint(x: snappedX, y: end.y), in: size)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    savedX = Double(target.x)
                    savedY = Double(target.y)
                    dragOffset = .zero
                }
                haptic()
            }
    }

    private func basePosition(in size: CGSize) -> CGPoint {
        let fallback = CGPoint(x: size.width - bubbleSize / 2 - edgeMargin, y: size.height * 0.62)
        guard savedX >= 0, savedY >= 0 else { return fallback }
        return clamp(CGPoint(x: savedX, y: savedY), in: size)
    }

    private func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let margin = bubbleSize / 2 + edgeMargin
        let minY = margin + 40
        let maxY = max(minY, size.height - margin - 60)
        let maxX = max(margin, size.width - margin)
        return CGPoint(x: min(max(point.x, margin), maxX),
                       y: min(max(point.y, minY), maxY))
    }

    private func toggle(_ open: Bool) {
        guard open != isOpen else { return }
        haptic()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isOpen = open }
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Binding var hideExplore: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Blocked") {
                    Label("Instagram Reels", systemImage: "film.stack")
                    Label("YouTube Shorts", systemImage: "play.square.stack")
                    Toggle(isOn: $hideExplore) {
                        Label("Instagram Explore feed", systemImage: "square.grid.3x3")
                    }
                }
                Section {
                    Text("Search, DMs, profiles, posting and normal videos still work.")
                    Text("Drag the floating button to either edge. Tap it to switch apps.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Reel Blocker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
