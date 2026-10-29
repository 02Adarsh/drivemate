# Smooth app: performance + animation notes

This update removed the "laggy" feeling and added animation everywhere. Here is
what was changed and how to test it correctly.

---

## 1. First: test with a release build

A `flutter run` debug build is **JIT-compiled**, ships with asserts and
instrumentation, and on a mid-range Android phone it can feel 2–4× slower than
the same code in release. Before judging performance, always compare with:

```bash
flutter run --release                 # USB, like a real user experience
# or
flutter build apk --release           # installable APK
flutter build apk --release --split-per-abi   # smaller per-device APKs
```

If it is smooth in `--release` and jumpy only in debug, the app is fine.

---

## 2. What was actually making it slow

| Cause | Fix in this build |
|---|---|
| `google_fonts` fetched Poppins over the network on first run and re-rendered text when it arrived | Poppins is now **bundled** in `assets/fonts` (SIL OFL) and declared in `pubspec.yaml`; the dependency was removed entirely |
| The onboarding/background photo was scaled **every frame** by a looping `AnimationController` behind a full-screen `Image.asset` | Backgrounds are now static and wrapped in `RepaintBoundary`; the idle repaint loop is gone |
| The 768×1376 JPEG was decoded at full size on every screen that showed it | `cacheWidth` decodes it once at screen resolution (`HeroBand`, `CinematicBackdrop`) |
| Continuous animation + gradients (shadows) on many cards | Shadows kept only on the primary button; per-item animation is a single short controller |
| Text/image work inside `AnimatedBuilder` | Animation builders only animate tiny proxies; the expensive child is passed via the `child:` parameter |

Net effect: fewer frames with real work, no network fetch on first launch, and no
permanent background animation.

---

## 3. Animations that were added

| Where | Animation |
|---|---|
| All navigation (`dmRoute`) | Slide + fade via `CupertinoPageTransitionsBuilder`, **plus swipe-from-edge back on Android and iOS** |
| Forms (login, register, every driver step) | Staggered fade + slide-up entrance per field (`DmEntrance`, 60–90 ms apart) |
| Dashboard cards | Same staggered entrance through `dmStagger()` |
| Cards / chips / photo picker | Press scale feedback (`DmTapScale`) |
| Status changes, step swaps | Cross-fade + slide (`DmSlideSwitcher`) |
| Driver verification status | Soft pulsing indicator (`DmPulse`, `RepaintBoundary`-wrapped) |
| Slide-to-start | Progress fill follows the thumb, springs back when released, haptic feedback on completion |

Design rules used so animation never costs smoothness:

* one short controller per item, no infinite loops except the tiny status pulse;
* the delay is an `Interval` on a single controller, not a `Timer` per item
  (no pending timers, no stray rebuilds, and it is testable with `pumpAndSettle`);
* durations 110–380 ms, all `easeOutCubic`/`easeOut`.

---

## 4. Colour pass (darker, higher contrast)

The palette was deepened for a premium dark look while keeping text contrast
comfortable (target ≥ 4.5:1 for body text):

| Token | Before | Now |
|---|---|---|
| `navy` (background) | `#080A0D` | `#05070A` |
| `panel` (cards/fields) | `#14171D` | `#0F1318` |
| `panel2` (secondary) | `#1B2028` | `#151A21` |
| `panel3` (pill track) | `#111318` | `#0A0D11` |
| `hairline` (borders) | `#24272E` | `#1E232B` |
| `red` (accent) | `#F04444` | `#F2403F` |

Login and register use the same background treatment as the reference design:
deep near-black with a soft red glow in the corners, and the night-drive banner
only on the login screen.

---

## 5. Quick performance checklist before you ship

* `flutter analyze` clean and `flutter test` green (both are, in this update).
* Test on the **lowest-spec phone** you support, in `--release`.
* Keep the debug banner off (already off) and avoid heavy shadows in lists.
* Only animate what changes; pass unchanged subtrees as `child:`.
* For the booking phase (live GPS), throttle location updates (for example one
  every 4–5 seconds, or every 15 m) — the update frequency must be configurable,
  which is already part of the plan in the project brief.
