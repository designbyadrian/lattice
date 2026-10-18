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

        # New windows tile by default when managed.
        default-tiling = true

        # Follow focus when an app activates (e.g. Cmd-Tab).
        follow-app-activation = true

        # Float normal windows that cannot go full-screen (unless a rule forces tiling).
        float-windows-without-fullscreen = true

        # Lattice extension: overview preview mode (auto | live | snapshots | off).
        overview-previews = 'auto'

        # Gaps between tiled windows (inner) and from the display edge (outer).
        # Each value may be a number or a { left, right, top, bottom } table.
        [gaps]
        inner = 0
        outer = 0

        # Which physical modifier key side counts in bindings (both | left | right).
        # Requires the active event tap; ignored under the Input safety net.
        [modifiers]
        alt = 'both'
        ctrl = 'both'
        cmd = 'both'
        shift = 'both'
        # Lattice extensions: chords held for modifier-drag and pinch-over-apps.
        drag-modifier = 'alt'
        pinch-modifier = 'ctrl-alt'

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
        [mode.main]
        alt-h = 'focus left'
        alt-j = 'focus down'
        alt-k = 'focus up'
        alt-l = 'focus right'
        alt-shift-h = 'move left'
        alt-shift-j = 'move down'
        alt-shift-k = 'move up'
        alt-shift-l = 'move right'
        alt-enter = 'split horizontal'
        alt-v = 'split vertical'
        alt-f = 'zoom window'
        alt-shift-f = 'zoom all'
        alt-o = 'overview'
        alt-tab = 'tab next'
        alt-shift-tab = 'tab prev'
        alt-1 = 'workspace 1'
        alt-2 = 'workspace 2'
        alt-3 = 'workspace 3'
        alt-4 = 'workspace 4'
        alt-5 = 'workspace 5'
        alt-6 = 'workspace 6'
        alt-7 = 'workspace 7'
        alt-8 = 'workspace 8'
        alt-9 = 'workspace 9'
        alt-shift-1 = 'move-window-to-workspace 1 --follow'
        alt-shift-2 = 'move-window-to-workspace 2 --follow'
        alt-shift-3 = 'move-window-to-workspace 3 --follow'
        alt-shift-4 = 'move-window-to-workspace 4 --follow'
        alt-shift-5 = 'move-window-to-workspace 5 --follow'
        alt-shift-6 = 'move-window-to-workspace 6 --follow'
        alt-shift-7 = 'move-window-to-workspace 7 --follow'
        alt-shift-8 = 'move-window-to-workspace 8 --follow'
        alt-shift-9 = 'move-window-to-workspace 9 --follow'
        alt-shift-q = 'float-all'
        alt-r = 'retile'
        alt-shift-space = ['layout floating', 'layout tiling']
        ctrl-alt-h = 'dock left'
        ctrl-alt-j = 'dock down'
        ctrl-alt-k = 'dock up'
        ctrl-alt-l = 'dock right'

        # Lattice extension: optional private-API paths (off by default; auto-disable on failure).
        [experimental]
        ax-window-id = false
        multitouch = false

        # Optional tables (defaults apply when omitted):
        # [animations] enabled = true, duration-ms = 300
        # [drag] placeholders = true
        # [hooks] startup / workspace-changing / workspace-changed / focus-changed / mode-changed
        # [workspace.1] tiling = true
        # [display.<pattern>] inner / outer gaps
        # [[rules]] app-id / app-name / title / kind + required run
        """
    }
}
