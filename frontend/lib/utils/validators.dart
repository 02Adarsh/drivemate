/// Shared input validation used by every form.
///
/// The backend re-validates all of this - these helpers exist so the person
/// filling in a form gets an answer instantly instead of waiting for the API.
class DmValidators {
  static String? requiredText(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? fullName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Full name is required';
    if (text.length < 2) return 'Enter your full name';
    if (!text.contains(RegExp(r'[A-Za-z]'))) return 'Enter a valid name';
    return null;
  }

  static String? email(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Email address is required';
    final parts = text.split('@');
    final valid = parts.length == 2 &&
        parts[0].isNotEmpty &&
        parts[1].contains('.') &&
        !parts[1].startsWith('.') &&
        !parts[1].endsWith('.');
    if (!valid) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Mobile number is required';
    final allowed = text.codeUnits.every(
      (code) =>
          (code >= 48 && code <= 57) ||
          code == 43 ||
          code == 45 ||
          code == 40 ||
          code == 41 ||
          code == 32,
    );
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (!allowed || digits.length < 8 || digits.length > 15) {
      return 'Enter a valid mobile number';
    }
    return null;
  }

  /// Login identifier: email address OR mobile number.
  static String? identifier(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Email or phone number is required';
    if (text.contains('@')) return email(text);
    return phone(text);
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Password is required';
    if (text.length < 8) return 'Use at least 8 characters';
    if (!text.contains(RegExp(r'[A-Za-z]')) ||
        !text.contains(RegExp(r'[0-9]'))) {
      return 'Mix letters and numbers for a stronger password';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if ((value ?? '').isEmpty) return 'Confirm your password';
    if (value != password) return 'Passwords do not match';
    return null;
  }

  static String? otp(String? value) {
    final text = (value ?? '').trim();
    if (text.length != 6 || int.tryParse(text) == null) {
      return 'Enter the 6-digit code';
    }
    return null;
  }

  /// Indian PIN code: exactly 6 digits.
  /// Change this single rule when the service expands to another country.
  static String? pincode(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'PIN code is required';
    if (text.length != 6 || int.tryParse(text) == null) {
      return 'Enter a valid 6-digit PIN code';
    }
    if (text.startsWith('0')) return 'PIN code cannot start with 0';
    return null;
  }

  static String? years(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter your driving experience in years';
    if (parsed <= 0) return 'Experience must be at least 1 year';
    if (parsed > 60) return 'Enter a realistic number of years';
    return null;
  }
}
