HA Sensor Bar brings your Home Assistant sensors to an Apple Silicon menu bar
with a native frosted-glass panel.

- Multi-account Codex and Antigravity cards with independent 5h/7d bindings.
- Custom fields, nested attributes, percentages, balances, and reset dates.
- Searchable discovery with explicit selection, JSON layouts, and Keychain tokens.
- Demo mode, pinned panel, themes, status summaries, and login registration.

Requires **Apple Silicon (arm64)** and **macOS 14 or later**.

Download the DMG, drag **HA Sensor Bar.app** to **Applications**, and launch it.
The ZIP contains the same app. Verify downloads against `SHA256SUMS.txt` using
`shasum -a 256 -c SHA256SUMS.txt`.

This app is **ad-hoc signed and not notarized**. If macOS blocks your verified
download, use **System Settings → Privacy & Security → Open Anyway** and confirm.
The app lives in the menu bar and does not show a Dock icon.

Start with **Demo Mode** or enter your Home Assistant base URL and a Long-Lived
Access Token in Settings. Tokens stay in macOS Keychain and are excluded from
layout exports. HTTP works for trusted local networks; HTTPS is recommended.
