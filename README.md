# HA Sensor Bar

A quiet, frosted-glass Home Assistant companion for the Apple Silicon menu bar.
Track Codex accounts, Antigravity models, balances, and your own sensors without
opening a dashboard.

**Apple Silicon · macOS 14+ · Native SwiftUI/AppKit · No third-party dependencies**

## Install and connect

1. Download the arm64 DMG or ZIP from **GitHub Releases**. Drag **HA Sensor
   Bar.app** into **Applications**, launch it, and find the stack icon in the
   menu bar. There is no Dock icon.
2. Explore **Demo Mode**, or click **Connect Home Assistant**.
3. Enter a base URL such as `http://homeassistant.local:8123` and a Long-Lived
   Access Token from your Home Assistant profile's Security page.
4. For HTTP, explicitly enable **Allow unencrypted HTTP for this server**.
   **Test Connection**, then **Save Changes**.
5. Under **Cards & Sensors**, choose **Discover Sensors**, check the cards you
   want, **Add Selected**, and save. Recommendations start unselected.

Releases are ad-hoc signed, not notarized. If macOS blocks your verified
download, use **System Settings → Privacy & Security → Open Anyway** and confirm.
See [installation details and checksums](docs/INSTALL.md).
PR reviewers can also download packages from CI workflow artifacts.

## Make it yours

- Create groups, collapse them in the panel, and drag group headings to reorder.
  Settings provides card sorting, editing, and deletion.
- Give cards a title, SF Symbol, and optional plan label. A card can have 5h,
  7d, optional reset, and unlimited extra fields. Weekly-only cards work.
- Each field has an independent `FieldBinding(entityID:valuePath:)`. Read
  `sensor.magpie_codex_account_a_5h_remaining` at `state`, another sensor for 7d,
  or nested `attributes.windows.weekly.remaining`. Numeric array components
  such as `attributes.models.0.remaining` work too.
- Automatic formatting follows the HA unit or a unit override. `%` uses a
  progress bar; `CNY`/`USD` use currency formatting. You can explicitly choose
  percent, number, currency, text, date, or countdown.
- Percentages are 0–100. Select remaining or used semantics; progress, colors,
  and the menu bar summary describe remaining capacity. Raw used values have a
  visible "used" label.
- Unavailable, unknown, null, missing paths, malformed numbers, and out-of-range
  percentages display **—**. Real `0` and `0.0` display **0%**.
- Reset fields are opt-in. ISO8601 with fractional seconds/time zones, Unix
  seconds/milliseconds, and plain text work. HA `last_updated` is never treated
  as reset time. Client sync time and the latest configured HA update are
  separate footer indicators.
- Pin the panel, refresh manually, use the right-click menu, set a 30s/1m/2m/5m
  interval, choose light/dark/system appearance and glass style, and enable
  launch at login.
- Import/export the complete layout as JSON. Imports are validated and remain
  editable until saved. Tokens never appear in exports.

Discovery prioritizes `sensor.magpie_codex_*` / `sensor.magpie_antigravity_*`,
pairs independent 5h/7d entities, and attaches matching extras. Legacy
`sensor.codex_*` / `sensor.antigravity_*` suggestions remain separate for review.
Currency entities are never inferred to be quota windows. **All Sensors**
supports search and custom names. Demo data never replaces your saved layout.
When multiple sensors match a quota window, discovery displays a warning and
retains each alternative as a labeled extra field. Review the window binding
and alternatives in **Cards & Sensors** before saving.

## Build, test, and package

Select a full Xcode installation with its macOS SDK, then run:

```bash
swift test --enable-code-coverage -Xswiftc -warnings-as-errors
python3 -m unittest discover -s scripts/tests -v
./scripts/build-app.sh 1.0.0
./scripts/package-release.sh 1.0.0
./scripts/verify-release.sh 1.0.0
./scripts/smoke-test.sh
open "dist/HA Sensor Bar.app"
```

The arm64 build targets macOS 14, uses APIs available to Xcode 16 / Swift 6,
and works with newer SDKs without depending on new glass symbols.
AppKit and `iconutil` generate the full 16–1024px glass icon set.
Packaging uses native macOS tools only, including `hdiutil` and `ditto`.

Outputs in `dist/`:

- `HA Sensor Bar.app`
- `HA-Sensor-Bar-1.0.0-arm64.dmg` (app, Applications shortcut, installation notes)
- `HA-Sensor-Bar-1.0.0-arm64.zip`
- `SHA256SUMS.txt` and `HA-Sensor-Bar-1.0.0-arm64.sha256`
- `demo-preview.png` after the smoke test

The scripts are repeatable and verify the requested version. Run the app with
`--demo` to immediately open the demo popover. Normal startup remains in the
menu bar without opening a window. The app menu's **Settings…**, **⌘,**, and
the panel's Settings button open the same four-tab settings window.
The smoke script checks both normal and demo startup, renders isolated demo
snapshots, exercises the Settings menu action and reopening, then exits.

## Automation

**CI** runs on PRs and pushes to `main`, on `macos-15` arm64 with Xcode 16.4.
It treats warnings as errors, runs unit tests and coverage, builds/signs the app,
packages both formats, mounts the DMG, extracts the ZIP, verifies metadata,
architecture, signatures and hashes, and renders a demo/settings smoke test.
Artifacts include packages, a PNG preview, and LCOV coverage.

**Release** runs on `v<major>.<minor>.<patch>` tags or manually with a numeric
version. A read-only macOS build job tests and verifies the packages, then
uploads a workflow artifact. A separate publish job with repository write
permission validates the downloaded artifact, creates or resumes a draft, and
uploads the DMG, ZIP, both checksum manifests, and English installation notes.
It downloads every uploaded asset and verifies hashes and sizes against the
build before publishing the draft. Tag and manual runs for the same version
share one concurrency group. A complete public version is verified and
preserved on reruns; an incomplete public version fails without replacing its
assets. Manual releases refuse to reuse a tag pointing at another commit.

## Architecture and privacy

See [architecture](docs/ARCHITECTURE.md) for boundaries and the test strategy.
Configuration is saved atomically to
`~/Library/Application Support/HA Sensor Bar/configuration.json`.
Tokens live only in the macOS login Keychain under
`com.hasensorbar.app.homeassistant`, scoped to the server URL.

Draft tokens are bound to the normalized server endpoint when entered and are
cleared when editing the URL or closing Settings. Connection, discovery, and
saving independently reject a draft for a different endpoint.

The app uses only read-only Home Assistant GET endpoints. Its ephemeral
URLSession disables caching/cookies and refuses redirects. HTTP is supported for
user-specified IPs, `.local`, and custom DNS hostnames via an explicit ATS
exception. HTTPS retains normal certificate validation. HTTP sends credentials
without encryption; use it only on trusted local networks and explicitly
approve it in Connection settings. Approval is scoped to the normalized
endpoint and required before testing, discovery, saving an HTTP connection,
or background polling. Imports require fresh HTTP approval. Enter the final
server URL, and prefer HTTPS where available. The configured 3–120 second
timeout limits both inactivity and total response transfer time.

Exports omit credentials but contain server URLs and entity IDs; review them
before sharing. No analytics or telemetry is collected.

## License

MIT. See [LICENSE](LICENSE).
