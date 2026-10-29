/// App configuration.
///
/// ---------------------------------------------------------------------------
/// Set Server connection in the app, or use the USB/LAN helper to select a backend.
/// ---------------------------------------------------------------------------
/// Android emulator            : http://10.0.2.2:8000/api
/// Physical phone (USB cable)  : http://127.0.0.1:8000/api
///                               (needs `adb reverse tcp:8000 tcp:8000` once)
/// Physical phone (same Wi-Fi) : http://<YOUR-COMPUTER-LAN-IP>:8000/api
///                               e.g. http://192.168.1.20:8000/api
/// iOS simulator               : http://127.0.0.1:8000/api
///
/// Find your computer's LAN IP:
///   Windows : ipconfig        (look for "IPv4 Address")
///   macOS   : ipconfig getifaddr en0
///   Linux   : hostname -I
/// Then run the backend so phones can reach it:
///   python manage.py runserver 0.0.0.0:8000
/// and allow port 8000 in your computer's firewall.
const String apiDefaultBaseUrl = 'http://127.0.0.1:8000/api';

/// Optional build-time address. Runtime settings can pin a trusted server too.
const String apiBaseUrl =
    String.fromEnvironment('API_BASE_URL', defaultValue: apiDefaultBaseUrl);

/// Public-health discovery candidates before sign-in. A selected custom URL
/// and an authenticated session are pinned: private calls do not fail over to
/// a guessed host. 127.0.0.1 needs adb reverse; 10.0.2.2 is emulator-only.
const List<String> apiFallbackBaseUrls = <String>[
  'http://127.0.0.1:8000/api',
  'http://10.0.2.2:8000/api',
];

/// Short timeout used while *testing* an address. A dead address is skipped
/// quickly instead of freezing a screen for the full request timeout.
const Duration apiProbeTimeout = Duration(seconds: 4);

/// Shown as a small badge on screens that still use prototype behaviour
/// (no live GPS, no real payment gateway). Keep it visible - never present
/// simulated data as real.
const bool demoMode = false;

/// Readable name of the environment, used in the demo badge.
const String environmentLabel = 'DEVELOPMENT V9';

/// Placeholder support address shown in the app. Replace it with the real
/// support mailbox before publishing.
const String supportEmail = 'support@drivemate.local';

/// Network timeout for regular API calls.
const Duration apiTimeout = Duration(seconds: 25);

/// Network timeout for file uploads (documents/photos can be a few MB).
const Duration uploadTimeout = Duration(seconds: 60);
