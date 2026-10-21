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

## Security notes
- HA backups of this add-on include the Bridge session and keys. Keep backup encryption on.
- The web console is admin-only and reachable only through Home Assistant ingress.

## Troubleshooting
- Login failed: read the log line after `LOGIN_FAIL`, then retry from the Configuration tab or the console.
- Start over: in the console run `logout`/`login`, or uninstall the add-on to delete `/data`.
