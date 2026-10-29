// Tests for the state → city data used by the registration forms.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drivemate/data/india_locations.dart';
import 'package:drivemate/screens/driver_personal_profile_screen.dart';
import 'package:drivemate/theme/dm_theme.dart';

void main() {
  test('every state has at least one city', () {
    expect(IndiaLocations.states, isNotEmpty);
    for (final state in IndiaLocations.states) {
      expect(IndiaLocations.stateCities[state], isNotEmpty,
          reason: '$state has no cities');
    }
  });

  test('expected states and cities are present', () {
    expect(IndiaLocations.states, contains('Uttar Pradesh'));
    expect(IndiaLocations.states, contains('Haryana'));
    expect(IndiaLocations.states, contains('Delhi'));

    expect(IndiaLocations.citiesFor('Uttar Pradesh'), contains('Lucknow'));
    expect(IndiaLocations.citiesFor('Haryana'), contains('Farrukhnagar'));
    expect(IndiaLocations.citiesFor('Maharashtra'), contains('Mumbai'));
    expect(IndiaLocations.citiesFor('Karnataka'), contains('Bengaluru'));
  });

  test('city lookup is safe for unknown or empty states', () {
    expect(IndiaLocations.citiesFor(null), isEmpty);
    expect(IndiaLocations.citiesFor(''), isEmpty);
    expect(IndiaLocations.citiesFor('Atlantis'), isEmpty);
  });

  test('city search returns state-qualified results', () {
    final results = IndiaLocations.searchCities('luck');
    expect(results, isNotEmpty);
    expect(results.first.toLowerCase(), contains('lucknow'));
    expect(results.first, contains('Uttar Pradesh'));
  });

  testWidgets(
      'step 2 shows state, city and PIN code, with city locked until a state is chosen',
      (tester) async {
    // Phone-sized surface so the form scrolls like it does on a real device.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
          theme: buildDriveMateTheme(),
          home: const DriverPersonalProfileScreen(name: 'Test Driver')),
    );
    await tester.pumpAndSettle();

    expect(find.text('State / Union Territory'), findsOneWidget);
    expect(find.text('Select a state first'),
        findsOneWidget); // city field disabled
    expect(find.text('PIN code (6 digits)'), findsOneWidget);

    // Open the state picker, use its search box and choose a state.
    await tester.ensureVisible(find.text('State / Union Territory'));
    await tester.tap(find.text('State / Union Territory'));
    await tester.pumpAndSettle();
    expect(find.text('Select state / union territory'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Search state'), 'Haryana');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Haryana').last);
    await tester.pumpAndSettle();

    // The state is filled in and the city field is now usable.
    expect(find.text('Haryana'), findsOneWidget);
    expect(find.text('Select a state first'), findsNothing);

    // City list for the chosen state is offered and only contains that state.
    await tester.ensureVisible(find.text('City'));
    await tester.tap(find.text('City'));
    await tester.pumpAndSettle();
    expect(find.text('Search city'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Search city'), 'Farrukhnagar');
    await tester.pumpAndSettle();
    expect(find.text('Farrukhnagar'), findsWidgets);
    expect(find.text('Mumbai'), findsNothing);

    await tester.tap(find.text('Farrukhnagar').last);
    await tester.pumpAndSettle();
    expect(find.text('Farrukhnagar'), findsOneWidget);
  });
}
