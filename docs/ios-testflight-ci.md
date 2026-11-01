# iOS builds to TestFlight (GitHub Actions)

Workflow: `.github/workflows/ios-testflight.yml` ("Upload iOS to TestFlight").

- **Runs on:** every push to `main`, every push to the `testflight` branch, and by hand (Actions → Upload iOS to TestFlight → Run workflow; GitHub lists it only once this workflow is on `main`). `release-candidate` itself does not upload. To send it to TestFlight: `git push -f origin origin/release-candidate:refs/heads/testflight`.
- **API key:** it must have the **Admin** role (key `47N3T93HJQ`). `Z88DY2A8KA` is App Manager and cannot use cloud signing. No `.cer`, `.p12` or `.mobileprovision` is needed.
- **No iPhone registered?** The archive step falls back to an unsigned archive and the export signs it. Not yet proven on a real run.
- **Off until set up:** while the `ASC_KEY_ID` secret is empty, the run skips every step and ends green with a notice.
- **App:** bundle ID `com.fitflexafrica.app`, team `UT3M2LB58H` (Nassor Mohammed), App Store Connect app ID 6828055385. The Xcode project gets these from fitflex-mobile#243. Until #243 is merged, the workflow stops with an error. Android stays `com.fitflexafrica.mobile`.
- **Version:** the version name comes from `pubspec.yaml` (`version: 1.0.1+2` gives `1.0.1`). The build number is `IOS_BUILD_NUMBER_OFFSET` (default 100) plus the workflow run number, so it goes up with every run.
- **Signing:** Xcode automatic signing with cloud-managed certificates, through the App Store Connect API key. No certificates or provisioning profiles are stored in GitHub.

## Owner's one-time steps

### 1. Create an App Store Connect API key
1. In App Store Connect, go to **Users and Access → Integrations → App Store Connect API → Team Keys**, then press **+**.
2. Name it something like `GitHub Actions TestFlight`. Choose the **Admin** role, because cloud-managed signing needs Admin.
3. Download the `.p8` file. Apple lets you download it only once, so keep it somewhere safe.
4. Write down the **Key ID** (shown in the key's row) and the **Issuer ID** (shown above the table).

### 2. Add the secrets and variables in GitHub
Go to fahamutech/fitflex-mobile → **Settings → Secrets and variables → Actions**.

Secrets:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | The Key ID from step 1. Setting this turns the workflow on. |
| `ASC_ISSUER_ID` | The Issuer ID from step 1. |
| `ASC_KEY_P8` | The full contents of the `.p8` file, either as-is (including the `-----BEGIN PRIVATE KEY-----` lines) or base64 (`base64 -i AuthKey_XXXX.p8 \| pbcopy`). |
| `IOS_GOOGLE_SERVICE_INFO_PLIST` | The contents of `ios/Runner/GoogleService-Info.plist`, as-is or base64. The file is gitignored, but the build needs it. |

Variables (all optional):

| Name | Use |
|---|---|
| `IOS_API_BASE` | Backend address built into the iOS app. If it is not set, the workflow uses `API_BASE`, and then the live server. |
| `IOS_BUILD_NUMBER_OFFSET` | Starting point for build numbers. The default is 100. Only ever raise it. |
| `SHOP_HOME_V2`, `PHOTO_HERO_UI`, `PHOTO_FOOTER_UI` | The same app switches as the Android and web builds. |

Firebase: the Firebase iOS app (and `lib/firebase_options.dart`) is still registered for `com.example.fitflexmobile`. Before relying on Firebase sign-in or push on iOS, register an iOS app for `com.fitflexafrica.app` in the Firebase console. Then use its `GoogleService-Info.plist` for the secret and update `firebase_options.dart` (a separate change).

### 3. First upload by hand from Xcode
Do this once on a Mac, after #243 is merged:
1. Sign in to Xcode with the Apple ID on team UT3M2LB58H (**Xcode → Settings → Accounts**).
2. Run `flutter build ios --release` and open `ios/Runner.xcworkspace`.
3. Plug in an iPhone and run the app on it once. This registers the device with the team, and automatic signing needs at least one registered device to make the development profile used when archiving.
4. Choose **Product → Archive**, then **Distribute App → App Store Connect → Upload**.
5. In App Store Connect, open the app (6828055385), go to **TestFlight**, and answer any questions about export compliance or test information.

The hand upload uses the pubspec build number (for example 2). CI builds start at 101, so they always sort after it.

### 4. Start a build
- Merge to `main` (only with the owner's go-ahead), or
- Go to **Actions → Upload iOS to TestFlight → Run workflow** and pick a branch.

The build shows up in App Store Connect → TestFlight after Apple has processed it, usually 5–30 minutes. Add internal testers there.

## Encryption declaration
`ios/Runner/Info.plist` sets `ITSAppUsesNonExemptEncryption = false`. The app only uses standard HTTPS/TLS (through the system and Firebase) and the transitive `crypto` package for hashing, so it qualifies for the exemption. If the app ever adds its own encryption (for example, encrypting stored data with a custom algorithm), review this setting again.

## Known gaps
- Nobody has run this workflow on a macOS runner yet. The first real run is the end-to-end test.
- Automatic signing on a fresh runner may create a new "Apple Development" certificate each run. If Apple's certificate limit is reached, revoke old ones under Certificates, Identifiers & Profiles.
- iOS push needs the Push Notifications capability (an `aps-environment` entitlement) and an APNs key in Firebase. Neither is set up yet, so push will not reach iPhones.
- Camera, location, step counting and push need a check on a real device through TestFlight.
