import SwiftUI

struct ContentView: View {
    @AppStorage("hideExplore") private var hideExplore = true

    private var settings: BlockerSettings {
        BlockerSettings(hideExplore: hideExplore)
    }

    var body: some View {
        TabView {
            ForEach(Platform.allCases) { platform in
                BlockingWebView(platform: platform, settings: settings)
                    // Rebuild the web view when a setting changes so the new script is injected.
                    .id("\(platform.rawValue)-\(hideExplore)")
                    .tabItem { Label(platform.title, systemImage: platform.systemImage) }
            }

            SettingsView(hideExplore: $hideExplore)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct SettingsView: View {
    @Binding var hideExplore: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Always blocked") {
                    Label("Instagram Reels tab & feed", systemImage: "xmark.circle")
                    Label("YouTube Shorts tab, shelves & player", systemImage: "xmark.circle")
                }
                Section("Optional") {
                    Toggle("Hide Instagram Explore", isOn: $hideExplore)
                }
                Section("Still works") {
                    Text("DMs, profiles, your feed, posting, search, normal YouTube videos, and single reels a friend sends you.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reel Blocker")
        }
    }
}
