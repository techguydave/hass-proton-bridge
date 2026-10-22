# Proton Mail Bridge

Runs Proton Mail Bridge so Home Assistant's built-in **IMAP** integration can read your Proton mailbox.
No ports are published; the add-on is reachable only on the internal Home Assistant network at
the hostname shown on the add-on's sidebar page (for example `d5655e8e-protonmail-bridge`). The Supervisor assigns it: it stays the same across restarts, updates and reinstalls, but differs between installs from different repositories or a copy placed in `/addons/` (`local-protonmail-bridge`), so always copy it from the sidebar page. Never use the container's IP address; that changes.

## One-time login
1. Open the add-on **Configuration** tab and fill in **Proton username**, **Proton password**, the
   **2FA code** (and **Mailbox password** if your account uses two-password mode).
2. Click **Save**, then **Restart** straight away: 2FA codes expire after about 30 seconds.
3. Check the **Log** tab for `LOGIN_OK`. The password, mailbox password and 2FA fields are cleared automatically
   after every attempt (success or failure), so a wrong password is never retried on restart.
4. Open **Proton Bridge** in the sidebar and click **Show Bridge credentials**. Copy the Bridge-generated
   **username and password** into the IMAP integration; these are *not* your Proton password.

CAPTCHA/human verification and security-key 2FA cannot be scripted: use the optional console link on the sidebar page and run `login` there.
The session lives in the add-on's `/data` folder and survives restarts and updates.

## Home Assistant IMAP integration
- Server: the hostname from the sidebar page, port `143`. Do **not** use `127.0.0.1:1143`: that is Bridge's private listener inside the add-on and Home Assistant cannot reach it
- Username / password from `info`
- Folder `INBOX`
- **Verify SSL certificate: off** (Bridge uses a self-signed certificate; turn on Advanced mode in your user profile to see this option)

Keep **IMAP security** on `ssl`: HA's IMAP integration does not support STARTTLS.

## Mailbox sync
Bridge downloads your mailbox before mail apps (and Home Assistant) can see all of it. The sidebar page's **Mailbox sync** card shows whether a sync is running (with progress and time left), when the last one finished and how long it took, or whether a restart interrupted it, plus the last error Bridge logged. A full sync runs when Bridge starts (quick once the mailbox is already downloaded), when its connection to Proton comes back, or when Proton requests a resync. There are no smaller syncs: between them, Bridge checks Proton for changes (new mail, read flags, moves) every 20–40 seconds. The card shows when the last check ran, whether it failed, and when the last change arrived. It also warns if no check has run for over 3 minutes or if Bridge has lost its connection to Proton. These times come from Bridge's own debug log files in the add-on's data folder; only timestamps are read, never message details.

## Logs
With **Forward Bridge logs** on (the default), Bridge's warnings, errors and sync progress from the console also appear in the add-on's **Log** tab, prefixed `[bridge]`. Only lines Bridge's logger prints are forwarded; `info` output, typed codes and verification links stay in the console.

## Security notes
- HA backups of this add-on include the Bridge session and keys. Keep backup encryption on.
- The web console is admin-only and reachable only through Home Assistant ingress.

## Troubleshooting
- Login failed: read the log line after `LOGIN_FAIL`, then retry from the Configuration tab or the console.
- Start over: in the console run `logout`/`login`, or uninstall the add-on to delete `/data`.
