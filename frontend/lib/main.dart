import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/splash_screen.dart';
import 'theme/dm_theme.dart';
export 'theme/dm_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DmAppearance.instance.load();
  runApp(const DriveMateApp());
}

/// DriveMate: a professional driver for the customer's own car.
class DriveMateApp extends StatelessWidget {
  const DriveMateApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: DmAppearance.instance,
        builder: (context, _) {
          final dark = DmAppearance.instance.dark;
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: navy,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
          ));
          return MaterialApp(
            title: 'DriveMate',
            debugShowCheckedModeBanner: false,
            theme: buildDriveMateTheme(),
            locale: Locale(DmAppearance.instance.language),
            supportedLocales: const [Locale('en'), Locale('hi')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: const SplashScreen(),
            builder: (context, child) {
              final factor = DmAppearance.instance.largeText ? 1.15 : 1.0;
              final scale = MediaQuery.textScalerOf(context).scale(1) * factor;
              return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale.clamp(0.9, 1.5))),
                  child: child!);
            },
          );
        },
      );
}
