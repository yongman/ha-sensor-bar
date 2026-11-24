HA Sensor Bar — Installation

Requirements: Apple Silicon (arm64), macOS 14 or later.

1. Download the arm64 DMG or ZIP and SHA256SUMS.txt from the same release.
2. In Terminal, change to the download directory and verify:
   shasum -a 256 -c SHA256SUMS.txt
   Keep both downloaded packages there, or verify the relevant listed hash.
3. Open the DMG and drag HA Sensor Bar.app to Applications. For ZIP, extract the
   app and move it to Applications.
4. Open the app and find the stack icon in the menu bar (there is no Dock icon).
5. Explore Demo Mode, or connect to Home Assistant in Settings.

This build is ad-hoc signed and not notarized. If macOS blocks it, attempt to open
the app, then use System Settings > Privacy & Security > Open Anyway and confirm.
Only override Gatekeeper for a copy whose origin and checksum you have verified.

Connect using your Home Assistant base URL and a Long-Lived Access Token.
Tokens are saved only in macOS Keychain and never included in layout exports.
Use HTTPS when possible. HTTP is supported for trusted local networks.

For launch at login, install in Applications, then enable it in the app's
Appearance & Menu Bar settings. If approval is needed, allow it under macOS
System Settings > General > Login Items.

To quit, right-click the menu bar icon and choose Quit HA Sensor Bar.
To uninstall, disable launch at login, forget the token in Connection,
quit the app, and remove it from Applications. The optional layout is stored
under ~/Library/Application Support/HA Sensor Bar/.
