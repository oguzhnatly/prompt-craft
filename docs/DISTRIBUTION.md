# PromptCraft Distribution Guide

Complete guide for code signing, notarization, and distributing PromptCraft outside the Mac App Store.

## Prerequisites

### Apple Developer Program

1. Enroll at [developer.apple.com](https://developer.apple.com/programs/) ($99/year).
2. After enrollment, go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list).

### Required Certificates

You need a **Developer ID Application** certificate for signing apps distributed outside the App Store.

1. Open **Keychain Access** on your Mac.
2. From the menu: Keychain Access > Certificate Assistant > Request a Certificate from a Certificate Authority.
3. Enter your email, select "Saved to disk", click Continue.
4. Go to [Apple Developer Certificates](https://developer.apple.com/account/resources/certificates/add).
5. Select "Developer ID Application" and upload your CSR file.
6. Download and double-click to install the certificate in Keychain.

Verify installation:

```bash
security find-identity -v -p codesigning
# Should show: "Developer ID Application: Your Name (TEAM_ID)"
```

### App-Specific Password

For notarization, you need an app-specific password (not your Apple ID password):

1. Go to [appleid.apple.com](https://appleid.apple.com/).
2. Sign In > Security > App-Specific Passwords > Generate.
3. Name it "PromptCraft Notarization" and save the password.

## Build Configurations

| Configuration | Purpose | Optimization | Signing | Assertions |
|--------------|---------|-------------|---------|------------|
| Debug | Development | None (-Onone) | Ad-hoc | Enabled |
| Release | Testing | Full (-O) | Automatic | Disabled |
| Distribution | Shipping | Full (-O) | Developer ID (Manual) | Disabled |

## Code Signing Setup

### Xcode Configuration (Distribution)

The Distribution build configuration uses:
- **Code Sign Style**: Manual
- **Code Sign Identity**: Developer ID Application
- **Development Team**: Your Team ID
- **Hardened Runtime**: Enabled
- **Entitlements**: PromptCraft/PromptCraft.entitlements

### Entitlements

Current entitlements (`PromptCraft.entitlements`):

```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
```

- **App Sandbox**: Required for notarization.
- **Network Client**: Required for API calls to LLM providers.

### No Provisioning Profile Required

Developer ID distribution does not require provisioning profiles. Those are only needed for App Store distribution.

## Building for Distribution

### Quick Method (Script)

```bash
# Set credentials
export APPLE_ID="your@apple.id"
export APPLE_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password
export APPLE_TEAM_ID="XXXXXXXXXX"

# Build, sign, notarize, create DMG
./scripts/build.sh --notarize
```

### Manual Method

#### 1. Increment Build Number

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' PromptCraft/Info.plist) + 1 ))" PromptCraft/Info.plist
```

#### 2. Archive

```bash
xcodebuild archive \
    -project PromptCraft.xcodeproj \
    -scheme PromptCraft \
    -configuration Release \
    -archivePath build/PromptCraft.xcarchive \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual
```

#### 3. Verify Signature

```bash
codesign --verify --deep --strict \
    build/PromptCraft.xcarchive/Products/Applications/PromptCraft.app
```

#### 4. Notarize

```bash
# Create ZIP
ditto -c -k --keepParent \
    build/PromptCraft.xcarchive/Products/Applications/PromptCraft.app \
    build/PromptCraft.zip

# Submit
xcrun notarytool submit build/PromptCraft.zip \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

# Staple
xcrun stapler staple \
    build/PromptCraft.xcarchive/Products/Applications/PromptCraft.app
```

#### 5. Create DMG

```bash
# Install create-dmg if needed
brew install create-dmg

create-dmg \
    --volname "PromptCraft" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "PromptCraft.app" 180 180 \
    --hide-extension "PromptCraft.app" \
    --app-drop-link 480 180 \
    "build/PromptCraft-1.0.0.dmg" \
    build/export/
```

## Notarization Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "The signature of the binary is invalid" | Ensure Hardened Runtime is enabled |
| "The executable does not have the hardened runtime enabled" | Add `ENABLE_HARDENED_RUNTIME = YES` to build settings |
| "The binary uses an SDK older than the 10.9 SDK" | Update deployment target |
| "The signature does not include a secure timestamp" | Use `--timestamp` flag with codesign |
| "The executable requests the com.apple.security.get-task-allow entitlement" | Remove this entitlement for Release/Distribution builds |

### Getting Notarization Logs

```bash
# After a failed submission, get the submission ID from the output, then:
xcrun notarytool log <SUBMISSION_ID> \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID"
```

### Verifying Notarization

```bash
# Check Gatekeeper assessment
spctl --assess --type execute --verbose PromptCraft.app

# Check stapling
stapler validate PromptCraft.app
```

## Auto-Update System (Sparkle)

PromptCraft uses the [Sparkle](https://sparkle-project.org/) framework for automatic updates.

### Appcast URL

Updates are served from: `https://updates.promptcraft.app/appcast.xml`

### EdDSA Key Pair

Generate a key pair for signing updates:

```bash
# This generates a private key and prints the public key
# Store the PRIVATE key securely (GitHub secret: SPARKLE_PRIVATE_KEY)
# The PUBLIC key goes in Info.plist as SUPublicEDKey
./path/to/Sparkle/bin/generate_keys
```

### Release Process

1. Build new version with incremented version number.
2. Create DMG using `./scripts/build.sh --notarize`.
3. Sign the DMG with EdDSA:
   ```bash
   ./path/to/Sparkle/bin/sign_update build/PromptCraft-X.Y.Z.dmg
   ```
4. Update `appcast.xml` with the new version entry (size, signature, URL).
5. Upload DMG to your hosting server.
6. Upload updated `appcast.xml`.

### Appcast XML Format

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>PromptCraft Updates</title>
    <item>
      <title>Version X.Y.Z</title>
      <sparkle:version>BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description>Release notes here.</description>
      <pubDate>DATE</pubDate>
      <enclosure
        url="https://updates.promptcraft.app/PromptCraft-X.Y.Z.dmg"
        sparkle:edSignature="EDDSA_SIGNATURE"
        length="FILE_SIZE_BYTES"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

## GitHub Actions CI/CD

### Required Secrets

Set these in your GitHub repository settings (Settings > Secrets and variables > Actions):

| Secret | Description |
|--------|-------------|
| `APPLE_ID` | Your Apple ID email for notarization |
| `APPLE_PASSWORD` | App-specific password (not your Apple ID password) |
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID |
| `SIGNING_CERTIFICATE` | Base64-encoded .p12 certificate file |
| `CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for Sparkle update signing |

### Exporting Your Certificate

```bash
# Export from Keychain as .p12, then base64 encode:
base64 -i DeveloperIDApplication.p12 | pbcopy
# Paste into GitHub secret SIGNING_CERTIFICATE
```

### Workflows

- **build.yml**: Runs on every push to main and PRs. Builds and tests.
- **release.yml**: Runs when a tag `v*` is pushed. Builds, signs, notarizes, creates DMG, uploads to GitHub Release.

### Creating a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Then create a GitHub Release from the tag. The workflow will automatically build and attach the notarized DMG.

## Licensing Integration (Future)

See `PromptCraft/Services/LicensingService.swift` for the placeholder implementation and documentation of Gumroad and Paddle integration options.

### Free Trial
- 5 optimizations per day (limited trial)
- All styles available
- All providers supported

### Subscription (Licensed)
- Unlimited optimizations
- Priority support
- Access to future premium features
