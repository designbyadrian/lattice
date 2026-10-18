# Security

## Reporting

Please report security issues privately to the maintainers (GitHub Security Advisories preferred). Do not open a public issue for exploitable bugs.

## Permissions

Lattice requires **Accessibility** to manage windows. **Screen Recording** is optional (overview previews). Lattice aims to avoid **Input Monitoring**; see `docs/input-matrix.md` for OS-version results.

## Secrets

Never commit Developer ID certificates, notarization credentials, or Sparkle EdDSA private keys. Those live in 1Password and GitHub Actions secrets.
