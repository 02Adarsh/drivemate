import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivemate/widgets/policy_sheet.dart';

void main() {
  testWidgets('terms and privacy can be opened and include important limits',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: Column(children: [
                  TextButton(
                      onPressed: () =>
                          showPolicySheet(context, PolicyDoc.terms),
                      child: const Text('Open terms')),
                  TextButton(
                      onPressed: () =>
                          showPolicySheet(context, PolicyDoc.privacy),
                      child: const Text('Open privacy')),
                ]),
              )),
    ));
    await tester.tap(find.text('Open terms'));
    await tester.pumpAndSettle();
    expect(find.text('Terms & Conditions'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}
