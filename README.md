# Proton Mail Bridge for Home Assistant OS

A local add-on that runs Proton Mail Bridge (base image
[`dancwilliams/protonmail-bridge`](https://github.com/dancwilliams/protonmail-bridge-docker), a maintained fork of
shenxn/protonmail-bridge-docker) so the IMAP integration can read a Proton mailbox. This is a Supervisor add-on,
not a HACS integration.

## Install
Copy `protonmail_bridge/` to `/addons/` on your HA OS host (e.g. via Terminal & SSH), then
Settings → Add-ons → Add-on Store → ⋮ → Check for updates → *Local add-ons*.
Or push this repo to GitHub, update the `url` fields, and add it as an add-on repository.

See `protonmail_bridge/DOCS.md` for login and IMAP setup.
