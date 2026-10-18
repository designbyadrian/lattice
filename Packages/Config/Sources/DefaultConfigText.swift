import Foundation

/// First-run `lattice.toml` body (Lattice-authored comments; Dinky-compatible keys).
public enum DefaultConfigText {
    /// Schema URL embedded in the `#:schema` directive for Taplo / editors.
    public static let schemaDirective =
        "#:schema https://raw.githubusercontent.com/designbyadrian/lattice/main/Packages/Config/Sources/Resources/lattice.schema.json"

    public static var fileContents: String {
        """
        \(schemaDirective)

        # Lattice configuration
        # Location: ~/.config/lattice/lattice.toml
        # Keys use kebab-case. Unknown keys are errors. A broken save keeps the last good config.
        # Format is compatible with Dinky by Mikkel Malmberg (MIT); Lattice extensions are noted below.

        # Launch Lattice when you log in.
        start-at-login = true

        # Number of workspaces (native Spaces) across all displays.
        workspaces = 1

        # New windows float in the desktop region until you dock them (ADDENDUM-2 D1).
        default-tiling = false

        # Follow focus when an app activates (e.g. Cmd-Tab).
        follow-app-activation = true

        # Float normal windows that cannot go full-screen (unless a rule forces tiling).
        float-windows-without-fullscreen = true

        # Menu-bar status controls (Lattice extension). Lattice's icon is always present.
        menu-bar-controls = ['back', 'forward', 'views', 'desktop', 'everything']

        # Gaps between tiled windows (inner) and from the display edge (outer).
        # Each value may be a number or a { left, right, top, bottom } table.
        [gaps]
        inner = 10
        outer = 10

        # Which physical modifier key side counts in bindings (both | left | right).
        # Requires the active event tap; ignored under the Input safety net.
        [modifiers]
        alt = 'both'
        ctrl = 'both'
        cmd = 'both'
        shift = 'both'
        # Lattice extensions: frame-rect drag and pinch-over-apps.
        frame-modifier = 'cmd-shift'
        pinch-modifier = 'alt'

        [mouse]
        double-click-desktop = 'zoom desktop --toggle'
        double-click-title = 'zoom window --toggle'

        [animations]
        enabled = true
        duration-ms = 450

        [layout]
        insert-takes-from = 'target'
        insert-ratio = 0.5
        close-gives-to = 'donor'
        live-visible-fraction = 0.99
        min-ratio = 0.02
        shrink-past-app-minimum = true
        tile-floor = [160, 100]
        fallback-min-size = [240, 160]
        drop-edge-fraction = 0.25
        screen-edge-band = 8

        [zoom]
        icon-tile-slack = 2
        group-tile-below = 100
        group-tile-above = 124
        still-timeout-ms = 600

        [tabs]
        tab-bar-height = 28
        tab-bar-ref-size = [400, 280]
        tab-bar-min-scale = 0.35
        tab-bar-hide-below = 12

        [desktop-area]
        min-size = [240, 160]
        reshow-ratio = 0.33
        drop-edge-fraction = 0.18
        drop-edge-max = 60
        float-max-fraction = 0.7
        float-margin = 12
        float-cascade = 24
        sole-float-fills = false
        float-nudge-in = true

        [window-sizing]
        ax-retries = 3
        ax-readback-delay-ms = 120
        ax-retry-interval-ms = 200
        ax-retry-window-ms = 2000
        ax-size-tolerance = 16
        ax-max-resolves = 3
        learn-minimums = true

        # Optional window borders (off by default in Lattice).
        [borders]
        enabled = false
        width = 4.0
        active-color = 'accent'
        inactive-color = '#494d64'
        order = 'below'
        exclude-apps = []

        # Focus-follows-mouse (off by default). accordion-edges is accepted but unused.
        [focus-follows-mouse]
        enabled = false
        delay-ms = 100
        accordion-edges = false
        # Lattice extension: bundle IDs that never receive FFM focus.
        exclude-apps = []

        # Key bindings (US-layout key names). Starting mode is main.
        # ADDENDUM-2 B11 Control-Option set.
        [mode.main]
        ctrl-alt-space = 'zoom all'
        ctrl-alt-up = 'zoom out'
        ctrl-alt-down = 'zoom in'
        ctrl-alt-left = 'pan left'
        ctrl-alt-right = 'pan right'
        ctrl-alt-shift-up = 'pan up'
        ctrl-alt-shift-down = 'pan down'
        ctrl-alt-left-bracket = 'history back'
        ctrl-alt-right-bracket = 'history forward'
        ctrl-alt-enter = 'zoom window --toggle'
        ctrl-alt-d = 'desktop-area toggle'
        ctrl-alt-n = 'split-new com.apple.finder'
        ctrl-alt-shift-1 = 'store-view 1'
        ctrl-alt-shift-2 = 'store-view 2'
        ctrl-alt-shift-3 = 'store-view 3'
        ctrl-alt-shift-4 = 'store-view 4'
        ctrl-alt-shift-5 = 'store-view 5'
        ctrl-alt-shift-6 = 'store-view 6'
        ctrl-alt-shift-7 = 'store-view 7'
        ctrl-alt-shift-8 = 'store-view 8'
        ctrl-alt-shift-9 = 'store-view 9'
        ctrl-alt-1 = 'recall-view 1'
        ctrl-alt-2 = 'recall-view 2'
        ctrl-alt-3 = 'recall-view 3'
        ctrl-alt-4 = 'recall-view 4'
        ctrl-alt-5 = 'recall-view 5'
        ctrl-alt-6 = 'recall-view 6'
        ctrl-alt-7 = 'recall-view 7'
        ctrl-alt-8 = 'recall-view 8'
        ctrl-alt-9 = 'recall-view 9'
        ctrl-alt-cmd-1 = 'workspace 1'
        ctrl-alt-cmd-2 = 'workspace 2'
        ctrl-alt-cmd-3 = 'workspace 3'
        ctrl-alt-cmd-4 = 'workspace 4'
        ctrl-alt-cmd-5 = 'workspace 5'
        ctrl-alt-cmd-6 = 'workspace 6'
        ctrl-alt-cmd-7 = 'workspace 7'
        ctrl-alt-cmd-8 = 'workspace 8'
        ctrl-alt-cmd-9 = 'workspace 9'
        ctrl-alt-cmd-shift-1 = 'move-window-to-workspace 1'
        ctrl-alt-cmd-shift-2 = 'move-window-to-workspace 2'
        ctrl-alt-cmd-shift-3 = 'move-window-to-workspace 3'
        ctrl-alt-cmd-shift-4 = 'move-window-to-workspace 4'
        ctrl-alt-cmd-shift-5 = 'move-window-to-workspace 5'
        ctrl-alt-cmd-shift-6 = 'move-window-to-workspace 6'
        ctrl-alt-cmd-shift-7 = 'move-window-to-workspace 7'
        ctrl-alt-cmd-shift-8 = 'move-window-to-workspace 8'
        ctrl-alt-cmd-shift-9 = 'move-window-to-workspace 9'

        # Lattice extension: optional private-API paths (off by default; auto-disable on failure).
        [experimental]
        ax-window-id = false
        multitouch = false

        # Optional tables (defaults apply when omitted):
        # [drag] placeholders = true
        # [hooks] startup / workspace-changing / workspace-changed / focus-changed / mode-changed
        # [workspace.1] tiling = true
        # [display.<pattern>] inner / outer gaps
        # [[rules]] app-id / app-name / title / kind + required run
        """
    }
}
