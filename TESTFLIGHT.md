# Shipping BMS Manager to TestFlight

A practical runbook. Assumes you have a paid Apple Developer Program membership.

## One-time setup

### 1. Bundle ID
1. https://developer.apple.com/account → **Certificates, Identifiers & Profiles** → Identifiers → "+"
2. App IDs → App → Bundle ID `com.benwyrosdick.bmsmanager` (Explicit)
3. Capabilities: leave defaults. Bluetooth doesn't need a capability entitlement, just the Info.plist usage description.

### 2. App Store Connect record
1. https://appstoreconnect.apple.com → My Apps → "+" → New App
2. iOS, name "BMS Manager", primary language, SKU (any unique string), full access
3. Pick the Bundle ID you just registered

### 3. App icon
You **must** ship a 1024×1024 PNG (no alpha, no rounded corners — Apple rounds for you).
- Drop the file at `Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- File name must match the entry in `Contents.json`
- A quick way to make one: use SF Symbols → `bolt.batteryblock.fill` → File → Export → 1024×1024 PNG with a colored background

### 4. Privacy nutrition labels (in App Store Connect)
App Information → App Privacy → Get Started
- **Data Types Collected**: None (we keep everything local)
- If asked about Bluetooth: "App Functionality" purpose

### 5. Xcode signing
Open the project → BMSManager target → Signing & Capabilities
- ✓ Automatically manage signing
- Team: your paid Developer team (not "Personal")
- Bundle Identifier: `com.benwyrosdick.bmsmanager`

## For every build

### 1. Bump build number
Edit `project.yml`:
```yaml
settings:
  base:
    CURRENT_PROJECT_VERSION: "2"   # was "1"
```
Then regenerate:
```bash
xcodegen generate
```
Build numbers must monotonically increase per `CFBundleShortVersionString`. App Store Connect rejects duplicates.

### 2. Archive
1. Xcode → set destination to **"Any iOS Device (arm64)"** (NOT a connected device)
2. Product → Archive (~2-5 min)
3. Window → Organizer opens automatically

### 3. Upload
1. In Organizer: Distribute App → App Store Connect → Upload
2. Automatic signing → Next → Upload
3. Wait ~5 min for processing in App Store Connect
4. You'll get an email when the build is ready or rejected

### 4. TestFlight metadata (first build only)
appstoreconnect.apple.com → My Apps → BMS Manager → TestFlight tab
- **Test Information**: feedback email, marketing URL (optional), privacy policy URL (required for external testing)
- **What to Test**: describe what testers should poke at
- **Beta App Description**: short description

### 5. Add testers
- **Internal** (Apple-team-members only, up to 100): TestFlight → Internal Testing → "+" → pick from your team. They install immediately.
- **External** (up to 10,000, any email): TestFlight → External Testing → create a group → add testers. First build requires Beta App Review (~24h). Subsequent builds in the same group don't, unless you change "What to Test" significantly.

## Common rejection causes for a Bluetooth app

1. **No `NSBluetoothAlwaysUsageDescription`** — already in your Info.plist ✓
2. **Background mode declared but not implemented** — we removed `UIBackgroundModes` for this reason. If you re-add `bluetooth-central` later, you need `CBCentralManagerOptionRestoreIdentifierKey` and the central-manager state-restoration delegate.
3. **Missing Privacy Manifest** — `Sources/PrivacyInfo.xcprivacy` ✓
4. **Encryption export compliance not declared** — `ITSAppUsesNonExemptEncryption=false` is in Info.plist ✓
5. **Crashes on Bluetooth-permission denied** — we show a banner instead of crashing ✓

## Privacy policy URL

External TestFlight needs one. If you don't have a domain, a public GitHub repo with a `PRIVACY.md` rendered URL is acceptable. Minimal text:

> BMS Manager stores battery configuration locally on your device. We do not collect, transmit, or share any personal data. Bluetooth is used solely to read live data from your battery management systems.

## Bumping for first public release later

When you're ready to leave TestFlight:
- `MARKETING_VERSION` to `1.0.0`
- App Store Connect: Prepare for Submission → screenshots, description, keywords, support URL
- App Review for public release is stricter than Beta App Review — expect 1-2 day review with possible questions
