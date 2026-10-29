# DriveMate V22 — GitHub APK update prompt

This source update is built on V21. Finish V19, V20 and V21 in order before applying and committing V22. Merge carefully; do not overwrite later local changes blindly. This package is source, not a ready APK.

The Android app checks the latest public stable release of `02Adarsh/drivemate` after startup navigation/session restoration and when it returns to the foreground. A release qualifies only if its tag has the exact form `vMAJOR.MINOR.PATCH+BUILD`, its build is greater than the installed Android build number, and it has a fully uploaded asset named exactly `app-release.apk`. The release must not be a draft or prerelease. GitHub errors, offline access and rate limits are ignored, with another check on a future opening. The prompt can be dismissed using Later; it will check again on the next opening. Update opens the trusted GitHub release page in a browser: the user must download and install the signed APK manually. No automatic install or Play Store is involved.

**Bootstrapping:** Currently installed V21 and older versions do not have this check. First build and distribute V22 (`1.7.9+17`) to users manually. Only after they install V22 can they receive later update prompts. An already-existing release with tag `v1.0.0` does not meet the required tag format and is ignored. A normal source-code commit or push is not a GitHub Release and does not notify users.

## Make a later update

1. For example, change `frontend/pubspec.yaml` version to `1.8.0+18`. Increase the number after `+` on *every* new Android release. Android compares version codes, not just the visible version name. Commit the change and build a release APK using the same release signing key as the installed app.
2. In GitHub, open repository `02Adarsh/drivemate` > Releases > Draft a new release. Create/tag `v1.8.0+18` (the tag MUST match the version and build in the actual APK). Upload `frontend/build/app/outputs/flutter-apk/app-release.apk` as the release asset without changing its filename. Publish as a normal release, not a draft or prerelease; ensure this is the latest release. Never publish a higher tag with an older APK, or the prompt will keep appearing after install.
3. On a device that already has V22 installed, open DriveMate online and check the popup. Select Later, background the app, then reopen: the popup should reappear. Select Update to open GitHub; download and install the APK and grant Android's install-from-this-source permission if prompted. Reopen and confirm the prompt no longer appears with build 18 installed. Android may reject the update if signed with a different key. Test this on a real Android device; it has not been tested here.

The public GitHub API can be temporarily unavailable or rate-limited and phones may have no internet; in those cases there is no popup until a later successful check. A released APK is publicly downloadable, so never include secrets in it. Download and installation remain user controlled.

## Commit V22 separately

In PowerShell, after merging V22 into the project and ensuring V19–V21 are already committed:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate
git add frontend/pubspec.yaml frontend/pubspec.lock frontend/lib/main.dart
git add frontend/lib/screens/splash_screen.dart frontend/lib/screens/session_resume_screen.dart
git add frontend/lib/services/app_update.dart frontend/lib/widgets/app_update_watcher.dart frontend/test/app_update_test.dart docs/UPDATE_V22_README.md
git --no-pager diff --cached --stat
git --no-pager diff --cached
git -c user.name="YuvrajKumar-005" -c user.email="Yuvrajkumar799129@gmail.com" commit -m "Add GitHub APK update prompt"
git push origin main
```

Review the staged diff; don't use `git add .`. Never stage release keys, key.properties, `.env`, local.properties, local databases or private uploads. GitHub associates a commit with a user only if its email is verified on that GitHub account. This update doesn't change the backend or run a database migration. Deferred backups and Render Free's ephemeral local uploads remain risks.

## Build V22 APK

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\frontend
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://drivemate-api-02adarsh.onrender.com/api
```

APK: `frontend\build\app\outputs\flutter-apk\app-release.apk`. Keep using the existing release keystore and do not share it or its password.

Verification performed: Flutter analysis clean; 140 Flutter tests passed, including mocked update parsing, lifecycle, errors and re-prompt tests. Android SDK, APK installation, a live new GitHub Release and device behavior were not tested here. No production GitHub Release was created.
