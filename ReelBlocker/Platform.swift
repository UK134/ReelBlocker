import Foundation

struct BlockerSettings {
    var hideExplore: Bool
}

enum Platform: String, CaseIterable, Identifiable {
    case instagram
    case youtube

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        }
    }

    var systemImage: String {
        switch self {
        case .instagram: return "camera"
        case .youtube: return "play.rectangle"
        }
    }

    var homeURL: URL {
        switch self {
        case .instagram: return URL(string: "https://www.instagram.com/")!
        case .youtube: return URL(string: "https://m.youtube.com/")!
        }
    }

    /// Swift-side redirect for full page loads. Returns nil if the URL is allowed.
    func redirect(for url: URL, settings: BlockerSettings) -> URL? {
        let path = url.path
        switch self {
        case .instagram:
            guard url.host?.contains("instagram.com") == true else { return nil }
            if path.hasPrefix("/reels") { return homeURL }
            if settings.hideExplore && path.hasPrefix("/explore") { return homeURL }
            return nil

        case .youtube:
            guard url.host?.contains("youtube.com") == true, path.hasPrefix("/shorts") else { return nil }
            // /shorts/VIDEO_ID -> open it in the normal player (no swipe-to-next)
            let parts = url.pathComponents  // ["/", "shorts", "VIDEO_ID"]
            if parts.count >= 3 {
                return URL(string: "https://m.youtube.com/watch?v=\(parts[2])")
            }
            return homeURL
        }
    }

    /// JavaScript injected at document start.
    func blockerScript(settings: BlockerSettings) -> String {
        let platformPart: String
        switch self {
        case .instagram: platformPart = Self.instagramJS(hideExplore: settings.hideExplore)
        case .youtube: platformPart = Self.youtubeJS
        }
        return Self.wrapper(platformPart)
    }

    // MARK: - Scripts

    /// Each platform part must define: CSS (string), redirect() -> bool, sweep().
    private static func instagramJS(hideExplore: Bool) -> String {
        #"""
        var HIDE_EXPLORE = \#(hideExplore);
        var CSS = 'a[href^="/reels"]{display:none!important}' +
                  (HIDE_EXPLORE ? 'a[href^="/explore"]{display:none!important}' : '');

        function redirect() {
          var p = location.pathname;
          // "/reels/..." is the endless feed. "/reel/ID" (a single shared reel) is allowed.
          if (p.indexOf('/reels') === 0 || (HIDE_EXPLORE && p.indexOf('/explore') === 0)) {
            location.replace('/');
            return true;
          }
          return false;
        }

        function sweep() {}
        """#
    }

    private static let youtubeJS = #"""
        var CSS = [
          'ytm-reel-shelf-renderer',
          'ytm-shorts-lockup-view-model',
          'ytm-shorts-lockup-view-model-v2',
          'ytm-rich-section-renderer:has(ytm-shorts-lockup-view-model)',
          'ytm-rich-section-renderer:has(ytm-shorts-lockup-view-model-v2)',
          'ytm-rich-section-renderer:has(ytm-reel-shelf-renderer)',
          'ytm-pivot-bar-item-renderer:has(.pivot-shorts)',
          'a[href^="/shorts"]'
        ].join(',') + '{display:none!important}';

        function redirect() {
          var p = location.pathname;
          if (p.indexOf('/shorts') === 0) {
            var id = p.split('/')[2];
            location.replace(id ? '/watch?v=' + id : '/');
            return true;
          }
          return false;
        }

        // Hide whole video cards that link to a Short (CSS alone would leave an empty card).
        function sweep() {
          document.querySelectorAll('a[href^="/shorts/"]').forEach(function (a) {
            var card = a.closest('ytm-video-with-context-renderer, ytm-rich-item-renderer, ytm-compact-video-renderer, ytm-media-item');
            if (card) card.style.setProperty('display', 'none', 'important');
          });
        }
        """#

    /// Shared engine: injects CSS, watches for in-page navigation and new content.
    private static func wrapper(_ platformPart: String) -> String {
        #"""
        (function () {
          if (window.__reelBlocker) return;
          window.__reelBlocker = true;

          \#(platformPart)

          function addStyle() {
            if (document.getElementById('reel-blocker-style')) return;
            var s = document.createElement('style');
            s.id = 'reel-blocker-style';
            s.textContent = CSS;
            (document.head || document.documentElement).appendChild(s);
          }

          var queued = false;
          function run() {
            queued = false;
            if (redirect()) return;
            addStyle();
            sweep();
          }
          function schedule() {
            if (!queued) { queued = true; requestAnimationFrame(run); }
          }

          // Both sites are single-page apps: catch navigation that never reloads the page.
          ['pushState', 'replaceState'].forEach(function (fn) {
            var orig = history[fn];
            history[fn] = function () {
              var result = orig.apply(this, arguments);
              schedule();
              return result;
            };
          });
          window.addEventListener('popstate', schedule);

          // Re-check whenever the page adds new content (infinite scroll, tab switches).
          new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });

          run();
        })();
        """#
    }
}
