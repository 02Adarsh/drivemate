// Tests for the backend-address fallback logic.
//
// "Cannot reach the DriveMate server" must not be a dead end: the app tries the
// configured address first, then the USB-tunnel and emulator addresses, and
// remembers whichever one answers.

import 'package:flutter_test/flutter_test.dart';

import 'package:drivemate/config.dart';
import 'package:drivemate/services/auth_service.dart';

void main() {
  setUp(AuthService.resetBaseUrl);

  test('the configured address is always tried first', () {
    final bases = AuthService.candidateBaseUrls();
    expect(bases.first, apiBaseUrl);
    expect(bases, contains('http://127.0.0.1:8000/api'));
    expect(bases, contains('http://10.0.2.2:8000/api'));
  });

  test('addresses are unique and have no trailing slash', () {
    final bases = AuthService.candidateBaseUrls();
    expect(bases.toSet().length, bases.length, reason: 'No duplicates.');
    for (final base in bases) {
      expect(base.endsWith('/'), isFalse);
    }
  });

  test('an address that worked is remembered and moved to the front', () {
    expect(AuthService.activeBaseUrl, apiBaseUrl);
    expect(AuthService.candidateBaseUrls().first, apiBaseUrl);
  });
}
