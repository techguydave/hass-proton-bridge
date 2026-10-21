# Changelog

## 3.27.1-4.13
- Fix the IMAP-security change: wait for the CLI's yes/no question before answering (a leftover prompt made the script answer it with the next command, i.e. "no").
- When changing IMAP security does not take effect, log the CLI output.

## 3.27.1-4.12
- The server name is read from the Supervisor at runtime (stable hostname, never an IP); docs no longer hard-code one.
- "Show Bridge credentials" shows the real server and port (not Bridge's internal 127.0.0.1:1143).
- IMAP-security step retries `info` until the account has loaded.

## 3.27.1-4.11
- Docs and status page show the real add-on hostname (and warn against 127.0.0.1:1143).
- Fix the IMAP-security step (and post-login wait): the CLI prints sync progress after its prompt, so no pattern may require the prompt at the end of the output.

## 3.27.1-4.10
- If the settings run gives no IMAP_SECURITY result, print its output for diagnosis.

## 3.27.1-4.9
- Log the result of the IMAP-security settings run (the filter was dropping it) and show the CLI output if it fails.

## 3.27.1-4.8
- Apply IMAP security correctly: read the IMAP block's Security line from `info`, run `change imap-security` when it differs, and log the result.
- Never send Bridge's `clear` command (it is a group of destructive commands); use Ctrl-L.
- Credentials button shows only the latest `info` block.
- Answer "no" to the CLI's "use a security key?" question so TOTP login proceeds.

## 3.27.1-4.7
- "Show Bridge credentials" shows just the IMAP address, port, username, password and security (falls back to the full `info` output if the format is not recognised).

## 3.27.1-4.6
- Console is embedded in the status page and Proton verification links refresh automatically beneath it, so you never leave the page (leaving closed the console connection).

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
