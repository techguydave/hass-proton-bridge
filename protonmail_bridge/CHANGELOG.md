# Changelog

## 3.27.1-4.5
- Status page lists Proton links (e.g. CAPTCHA/human-verification) found in the Bridge CLI output as clickable links.
- Console text can be selected normally (tmux mouse mode off).
- Drop stray null bytes from login output.

## 3.27.1-4.4
- Fix login timeout: prompt patterns no longer require the prompt at end of line (the CLI redraws it with escape codes).
- On failure, print the CLI output with escape codes stripped and secrets redacted.

## 3.27.1-4.3
- Sidebar panel is now a status page with an on-demand "Show Bridge credentials" button (nothing is logged); the web console moves to an optional `console/` link.
- Failed logins print a secret-redacted CLI transcript.

## 3.27.1-4.2
- Login script waits up to 5 minutes for the Bridge CLI (first-run GPG key generation) and logs its startup output for diagnosis.

## 3.27.1-4.1
- Fix image build: install ttyd from the pinned upstream static binary (not packaged in Debian bookworm).
- Move the base image into the Dockerfile and drop the deprecated `build.yaml`.

## 3.27.1-4.0
- Initial release: Proton Mail Bridge v3.27.1 (base image `dancwilliams/protonmail-bridge:v3.27.1-4`).
- Login from the Configuration tab, with secrets cleared after each attempt.
- Ingress web console for `info`, CAPTCHA/security-key logins and advanced settings.
- No ports published; IMAP/SMTP reachable only on the internal Home Assistant network.
