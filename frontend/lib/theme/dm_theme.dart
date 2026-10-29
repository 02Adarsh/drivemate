import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'appearance.dart';
export 'appearance.dart';

/// DriveMate design tokens.
///
/// Single source of truth for colour, radius and text styling so every screen
/// stays consistent with the reference design.
///
/// Fonts: Poppins is **bundled** in `assets/fonts` (OFL licensed). Nothing is
/// downloaded at runtime, which removes the first-run lag that `google_fonts`
/// network fetching caused.
///
/// Original brand palette — deep near-black surfaces with a red accent.

// V9: high-contrast monochrome surfaces, blue navigation accent. No runtime
// font/image download. Palette getters are read whenever the app rebuilds.
Color get navy => DmAppearance.instance.dark
    ? const Color(0xFF08090B)
    : const Color(0xFFFFFFFF);
Color get navyDeep => DmAppearance.instance.dark
    ? const Color(0xFF030405)
    : const Color(0xFFF8F9FB);
Color get panel => DmAppearance.instance.dark
    ? const Color(0xFF14161A)
    : const Color(0xFFF4F5F7);
Color get panel2 => DmAppearance.instance.dark
    ? const Color(0xFF202329)
    : const Color(0xFFEBEDF0);
Color get panel3 => DmAppearance.instance.dark
    ? const Color(0xFF0E1013)
    : const Color(0xFFF9FAFB);
const Color red = Color(0xFF276EF1);
const Color redDeep = Color(0xFF164EAD);
Color get softWhite => DmAppearance.instance.dark
    ? const Color(0xFFF7F8FA)
    : const Color(0xFF101114);
Color get muted => DmAppearance.instance.dark
    ? const Color(0xFFABB1BC)
    : const Color(0xFF5B626D);
Color get hairline => DmAppearance.instance.dark
    ? const Color(0xFF30343B)
    : const Color(0xFFDEE1E6);
const Color success = Color(0xFF168A60);
const Color warning = Color(0xFFAD6B06);
const Color danger = Color(0xFFD93445);
const Color info = Color(0xFF276EF1);

// --- Radii -----------------------------------------------------------------
const double radiusField = 14;
const double radiusCard = 20;
const double radiusButton = 15;

/// Default page padding used by every auth screen.
const EdgeInsets screenPadding = EdgeInsets.fromLTRB(23, 8, 23, 26);

const String dmFontFamily = 'Poppins';

/// Text theme built from the bundled Poppins files.
TextTheme dmTextTheme() {
  const base = TextTheme(
    displayLarge: TextStyle(
        fontFamily: dmFontFamily,
        fontSize: 57,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5),
    displayMedium: TextStyle(
        fontFamily: dmFontFamily,
        fontSize: 45,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5),
    displaySmall: TextStyle(
        fontFamily: dmFontFamily, fontSize: 36, fontWeight: FontWeight.w700),
    headlineLarge: TextStyle(
        fontFamily: dmFontFamily, fontSize: 32, fontWeight: FontWeight.w700),
    headlineMedium: TextStyle(
        fontFamily: dmFontFamily, fontSize: 28, fontWeight: FontWeight.w700),
    headlineSmall: TextStyle(
        fontFamily: dmFontFamily, fontSize: 24, fontWeight: FontWeight.w700),
    titleLarge: TextStyle(
        fontFamily: dmFontFamily, fontSize: 20, fontWeight: FontWeight.w700),
    titleMedium: TextStyle(
        fontFamily: dmFontFamily, fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(
        fontFamily: dmFontFamily, fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontFamily: dmFontFamily, fontSize: 15),
    bodyMedium: TextStyle(fontFamily: dmFontFamily, fontSize: 13.5),
    bodySmall: TextStyle(fontFamily: dmFontFamily, fontSize: 12),
    labelLarge: TextStyle(
        fontFamily: dmFontFamily, fontSize: 13.5, fontWeight: FontWeight.w700),
    labelMedium: TextStyle(
        fontFamily: dmFontFamily, fontSize: 12, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(
        fontFamily: dmFontFamily, fontSize: 11, fontWeight: FontWeight.w600),
  );
  return base.apply(
      fontFamily: dmFontFamily, bodyColor: softWhite, displayColor: softWhite);
}

ThemeData buildDriveMateTheme() {
  final scheme = ColorScheme(
    brightness: DmAppearance.instance.dark ? Brightness.dark : Brightness.light,
    primary: red,
    onPrimary: Colors.white,
    secondary: red,
    onSecondary: Colors.white,
    surface: panel,
    onSurface: softWhite,
    error: danger,
    onError: Colors.white,
  );

  // `fontFamily` only exists on the ThemeData constructor, not on copyWith,
  // so the base theme is created with it here.
  final base = ThemeData(
    brightness: DmAppearance.instance.dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
    fontFamily: dmFontFamily,
    colorScheme: scheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: navy,
    colorScheme: scheme,
    // Bundled Poppins: zero network fetch, so text paints on the first frame.
    textTheme: dmTextTheme(),
    primaryTextTheme: dmTextTheme(),
    // Swipe-from-edge back gesture + smooth slide transition everywhere.
    // This is what makes "swipe back" work on Android as well as iOS.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: softWhite,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      isDense: false,
      hintStyle: const TextStyle(
          fontFamily: dmFontFamily, color: Color(0xFF6B7280), fontSize: 13.5),
      labelStyle: TextStyle(fontFamily: dmFontFamily, color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusField),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusField),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusField),
        borderSide: const BorderSide(color: red, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusField),
        borderSide: const BorderSide(color: danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusField),
        borderSide: const BorderSide(color: danger, width: 1.5),
      ),
      errorStyle: const TextStyle(
          fontFamily: dmFontFamily, color: danger, fontSize: 11.5),
      prefixIconColor: muted,
      suffixIconColor: muted,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: panel2,
      contentTextStyle:
          TextStyle(fontFamily: dmFontFamily, color: softWhite, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: softWhite,
        foregroundColor: navy,
        disabledBackgroundColor: panel2,
        disabledForegroundColor: muted,
        textStyle: const TextStyle(
            fontFamily: dmFontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 15),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton)),
        minimumSize: const Size.fromHeight(54),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: softWhite,
        side: BorderSide(color: hairline),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusField)),
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(
            fontFamily: dmFontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: red,
        textStyle: const TextStyle(
            fontFamily: dmFontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 12.5),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: Color(0xFF454B55), width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? red : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: red),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: panel,
      selectedItemColor: red,
      unselectedItemColor: muted,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: panel,
      indicatorColor: red.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
            fontFamily: dmFontFamily,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: softWhite.withValues(alpha: 0.9)),
      ),
      iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 22)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle:
          TextStyle(fontFamily: dmFontFamily, color: softWhite, fontSize: 14),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(panel2),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusField),
            side: BorderSide(color: hairline),
          ),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

// --- Reusable text styles --------------------------------------------------
TextStyle dmHeading({double size = 30, double height = 1.12}) => TextStyle(
      fontFamily: dmFontFamily,
      fontSize: size,
      height: height,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: softWhite,
    );

TextStyle dmSubtitle({double size = 13.5}) => TextStyle(
      fontFamily: dmFontFamily,
      fontSize: size,
      height: 1.5,
      color: softWhite.withValues(alpha: 0.78),
    );

TextStyle dmCaption({double size = 11.5}) => TextStyle(
      fontFamily: dmFontFamily,
      fontSize: size,
      color: muted,
      height: 1.45,
    );

TextStyle dmSectionLabel() => const TextStyle(
      fontFamily: dmFontFamily,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
      color: red,
    );
