import 'package:flutter/material.dart';
import '../main.dart';
import '../widgets/brand_mark.dart';
import 'auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final pager = PageController();
  int index = 0;
  final items = <({IconData icon, String title, String copy})>[
    (icon: Icons.route_rounded, title: 'Your ride,\nour priority.', copy: 'A professional driver comes to you and drives the car you own.'),
    (icon: Icons.verified_user_outlined, title: 'Your car.\nYour control.', copy: 'Choose your vehicle, plan your trip and stay in control from pickup to drop-off.'),
    (icon: Icons.nightlight_round, title: 'Move with\npeace of mind.', copy: 'Clear booking details, driver identity checks and trip updates in one place.'),
  ];
  void start() => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, animation, secondary) => const AuthScreen(), transitionsBuilder: (_, animation, secondary, child) => SlideTransition(position: Tween<Offset>(begin: const Offset(.1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: FadeTransition(opacity: animation, child: child)), transitionDuration: const Duration(milliseconds: 380)));

  @override
  void dispose() { pager.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: CinematicBackdrop()),
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 0), child: Row(children: [
            const BrandMark(size: 42), const SizedBox(width: 10),
            const Text('DriveMate', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const Spacer(), Text('${index + 1} / 3', style: const TextStyle(color: muted, fontSize: 12)),
          ])),
          Expanded(child: PageView.builder(
            controller: pager,
            itemCount: items.length,
            onPageChanged: (v) => setState(() => index = v),
            itemBuilder: (context, i) {
              final item = items[i];
              return Padding(padding: const EdgeInsets.fromLTRB(26, 34, 26, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Spacer(),
                Container(width: 54, height: 54, decoration: BoxDecoration(color: red.withOpacity(.13), borderRadius: BorderRadius.circular(17)), child: Icon(item.icon, color: red, size: 27)),
                const SizedBox(height: 24),
                Text(item.title, style: const TextStyle(fontSize: 39, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -1.3)),
                const SizedBox(height: 14),
                Text(item.copy, style: const TextStyle(color: Color(0xFFBBC0C9), fontSize: 15, height: 1.55)),
                const SizedBox(height: 28),
                Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white.withOpacity(.055), border: Border.all(color: Colors.white.withOpacity(.1)), borderRadius: BorderRadius.circular(18)), child: const Row(children: [Icon(Icons.directions_car_filled_rounded, color: red), SizedBox(width: 11), Expanded(child: Text('We provide the driver. The car is always yours.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))])),
                const Spacer(flex: 2),
              ]));
            },
          )),
          Padding(padding: const EdgeInsets.fromLTRB(25, 4, 25, 20), child: index < 2
              ? Row(children: [
                  ...List.generate(3, (i) => AnimatedContainer(duration: const Duration(milliseconds: 220), margin: const EdgeInsets.only(right: 6), width: i == index ? 24 : 7, height: 7, decoration: BoxDecoration(color: i == index ? red : Colors.white24, borderRadius: BorderRadius.circular(9)))),
                  const Spacer(),
                  TextButton(onPressed: start, child: const Text('Skip', style: TextStyle(color: muted))),
                  const SizedBox(width: 6),
                  FilledButton(onPressed: () => pager.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOut), style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white, shape: const CircleBorder(), padding: const EdgeInsets.all(15)), child: const Icon(Icons.arrow_forward_rounded)),
                ])
              : _SlideToStart(onComplete: start)),
        ])),
      ]),
    );
  }
}

class _SlideToStart extends StatefulWidget {
  final VoidCallback onComplete;
  const _SlideToStart({required this.onComplete});
  @override
  State<_SlideToStart> createState() => _SlideToStartState();
}

class _SlideToStartState extends State<_SlideToStart> {
  double value = 0;
  bool started = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final max = constraints.maxWidth - 56;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        setState(() => value = ((details.localPosition.dx - 24) / max).clamp(0, 1));
        if (value > .88 && !started) { started = true; widget.onComplete(); }
      },
      onHorizontalDragEnd: (_) { if (value < .88) setState(() => value = 0); },
      child: Container(height: 58, decoration: BoxDecoration(color: panel2, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)), child: Stack(alignment: Alignment.center, children: [
        const Text('SLIDE TO GET STARTED', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        Positioned(left: value * max, child: IgnorePointer(child: Container(width: 48, height: 48, decoration: BoxDecoration(color: red, borderRadius: BorderRadius.circular(26)), child: const Icon(Icons.double_arrow_rounded, color: Colors.white)))),
      ])),
    );
  });
}

class CinematicBackdrop extends StatefulWidget {
  const CinematicBackdrop({super.key});
  @override
  State<CinematicBackdrop> createState() => _CinematicBackdropState();
}

class _CinematicBackdropState extends State<CinematicBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  void initState() { super.initState(); controller = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat(reverse: true); }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) => ClipRect(child: Stack(fit: StackFit.expand, children: [
      Transform.scale(scale: 1.04 + controller.value * .035, child: Image.asset('assets/images/night_drive.jpg', fit: BoxFit.cover)),
      Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xCC080A0D), const Color(0x75080A0D), const Color(0xEA080A0D)], stops: const [0, .42, 1]))),
      Container(color: red.withOpacity(.035 + controller.value * .025)),
    ])),
  );
}
