import 'package:flutter/material.dart';
import '../theme/dm_theme.dart';

class BrandMark extends StatelessWidget {
  final double size;
  final bool rounded;
  const BrandMark({super.key, this.size = 76, this.rounded = true});
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: softWhite,
            borderRadius: BorderRadius.circular(rounded ? size * .28 : 0)),
        alignment: Alignment.center,
        child: Text('D',
            style: TextStyle(
                color: navy,
                fontSize: size * .66,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -size * .05)));
  }
}
