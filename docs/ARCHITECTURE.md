# Architecture

## Boundaries

`HASensorBarCore` contains Codable/Sendable models, versioned configuration,
field/date resolution, discovery, a URLSession-injectable REST client,
Keychain abstraction, atomic persistence, and a cancellable refresh loop.
Its framework dependencies are Foundation and Security.

`HASensorBarApp` uses SwiftUI for the panel and Settings, AppKit for
`NSStatusItem`, `NSPopover`, windows and `NSVisualEffectView`, and
ServiceManagement's `SMAppService.mainApp` for login registration.
`LSUIElement` and accessory activation keep it out of the Dock.
The AppKit application entry creates no implicit SwiftUI scenes or windows.
The main menu, command-comma shortcut, status menu, and panel route to one
AppKit-owned Settings window. Demo launch explicitly shows the popover.
Ultra-thin/thin material, a native popover visual effect, restrained highlights,
translucent borders, and shadows work on macOS 14 and Xcode 16.

## Refresh and bindings

`AppStore` is MainActor isolated. The scheduler refreshes immediately, awaits
completion, then sleeps. Manual refreshes coalesce with an active request.
Saving settings cancels previous work and rotates a generation identifier;
cancellation and generation checks stop stale responses replacing new data.
Failures retain the last snapshot with an explicit stale-data error banner.
Demo mode uses a separate in-memory layout and stops network activity.

Every quota, extra, and reset has its own `FieldBinding`. `ValuePath` reads
`state` or nested attributes, including numeric array indices. Resolution
returns an explicit unavailable value, percentage, currency, number, text,
or date. It never converts an unknown value to zero.
Remaining fractions drive progress/color/summary; used percentages keep their
raw display plus a label. Reset parsing is opt-in and never uses HA update
timestamps. HA update time and client sync time are independent.

Discovery has no network/persistence side effects. Provider prefixes and window
suffixes propose cards, preserve separate legacy keys, attach extras to the
most specific matching account/model, and support weekly-only cards. The UI
starts with no selections and deduplicates identical confirmed cards.
Conflicting window candidates remain visible as labeled alternative extra
fields, with an explicit warning to review their bindings.

## Secrets and transport

`TokenStore` abstracts macOS Keychain. The implementation uses generic-password
items scoped by service and normalized server URL. It updates existing items
without delete/reinsert and disables synchronization on new entries.
The login Keychain works for ad-hoc builds without provisioning/access-group
entitlements. Failures are visible and never fall back to plaintext storage.
Closing Settings clears the draft SecureField.
`DraftToken` captures the normalized endpoint at entry. Editing the URL clears
the draft immediately; the client factory and save boundary validate the
binding independently before reading or writing credentials.

`AppConfiguration` has no token/password/authorization properties. Unknown
import properties are dropped on re-export. Validation rejects URL credentials,
queries, fragments, invalid IDs, unsupported versions, and unsafe intervals.
JSON uses atomic writes with mode 0600. A new server needs its own token.

The URLSession is ephemeral, disables cookies/caches, and refuses redirects.
Only read-only GET endpoints are used. Error messages omit response bodies,
headers, and credentials. HTTPS uses system trust; self-signed certificates
must be trusted through normal OS configuration.

`NSAllowsArbitraryLoads = true` supports user-specified HTTP servers with
custom DNS names as well as IP and `.local` addresses.
`NSAllowsLocalNetworking` is deliberately omitted: on supported macOS versions
its presence would override the arbitrary-load exception. HTTPS retains system
certificate verification. The Connection page explains cleartext HTTP.
HTTP requires explicit consent scoped to the normalized endpoint. Saved
configurations without consent cannot poll; importing through Settings clears
consent. The client also rejects HTTP unless consent is explicitly passed.
The production session sets both request and resource timeouts to the user's
validated 3–120 second limit. Cancellation remains a `CancellationError`.
The API connection test decodes a nonempty JSON `message`, rejecting proxy
login pages even when they return a successful HTTP status.

## Verification and limitations

XCTest covers realistic redacted independent sensor data, legitimate zero and
unavailable values, finite/ranged numbers, nested objects/arrays, units/currency,
used direction, fractional ISO/Unix dates, explicit resets, discovery/legacy
pairing, token-free imports/exports, invalid layouts, persistence, HTTP
authentication/status/decoding, Keychain lifecycle/isolation, and scheduler
cancellation/restart. App-store tests guard the actual request/save boundaries.
A real loopback HTTP server drips response bytes to verify the production
resource timeout and task cancellation.

CI selects Xcode 16.4 on `macos-15` arm64 with warnings as errors.
Distribution checks inspect both archive formats, bundle metadata, architecture,
and signatures. A foreground smoke test renders demo and Settings from a
temporary configuration, verifies normal startup has no visible normal
windows and demo startup shows its popover, captures PNGs, and exercises the
main-menu Settings shortcut and window reopening before exiting. It does not establish
live-server connectivity, login-item approval, or every interactive UI path;
those require manual Mac acceptance. Builds are ad-hoc signed, not notarized.

Release builds run with read-only repository access. A separate publish job
downloads the verified artifact, validates its checksum manifest, and uploads
only to a draft. It downloads and checks every asset before public release.
Same-version dispatches and tags share a concurrency group. Public releases
are checked without modification on reruns; an incomplete public release
fails without clobbering assets. Python tests cover successful publication,
interrupted uploads, corruption, draft retries, public reruns, invalid
artifacts, tag mismatches, and authentication errors.
