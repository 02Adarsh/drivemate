import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 76});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/drivemate_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF171A20),
          borderRadius: BorderRadius.circular(size * .24),
        ),
        child: const Icon(Icons.route_rounded, color: Color(0xFFF04444)),
      ),
    );
  }
}
