# Changelog

All notable changes to Lattice are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — Unreleased

### Added

- Experimental flags (`[experimental]` in `lattice.toml`): optional `ax-window-id` (`_AXUIElementGetWindow` shortcut) and `multitouch` (raw MultitouchSupport path); both off by default with runtime auto-disable.
- Native permissions onboarding (Welcome → Accessibility → Input Monitoring note → optional Screen Recording → tutorial).
- Sparkle 2 updater integration (automatic checks toggle; EdDSA public key placeholder in Info.plist).
- GitHub Actions release workflow on version tags (arm64 build, release-strings gate; sign/notarize/DMG/appcast placeholders).
- Menu warning when Accessibility is revoked after onboarding.
- Native look pass: system materials, accent colour, SF Symbols menu icon, Reduce Motion / Transparency / Increase Contrast hooks on overlays.

### Notes

- Input Monitoring matrix (`docs/input-matrix.md`) remains pending VM sign-off (P5a).
- Do not commit Sparkle private keys or Developer ID credentials; see `SECURITY.md` and the release workflow comments.
