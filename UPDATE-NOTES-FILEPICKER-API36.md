# Android file picker compatibility patch

The build log now confirms the app is compileSdk 36, but `:file_picker` itself remains at file_picker 8.3.7 and compiles its module against Android 34. Upgrade the plugin to 13.1.0 and migrate its breaking API.

Extract this patch into the existing project root and replace files. It updates `frontend/pubspec.yaml` to `file_picker: ^13.1.0` and uses the new `FilePicker.pickFile()` API.

If you added the `BaseExtension` / `subprojects afterEvaluate` snippet to `android/app/build.gradle.kts` (the build log showed that file warning around line 55), remove that manually-added block from the **app** file. Keep `compileSdk = 36` inside its `android {}` block. Do not paste the workaround inside app/build.gradle.kts.

Then from `frontend`:
```powershell
flutter clean
flutter pub get
flutter pub deps | Select-String file_picker
flutter run -d ZA223BDMZP
```
Confirm output resolves `file_picker 13.1.0`. Keep API 36 installed in Android SDK. No database change.
