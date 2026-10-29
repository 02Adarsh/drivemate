import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';

/// Personal direct UPI, deliberately NOT a merchant/gateway verification SDK.
class DirectUPIService {
  static Future<Map<String, dynamic>> profile() =>
      AuthService.getJson('payments/driver/profile/');
  static Future<Uint8List> profileImage() =>
      AuthService.getPrivateBytes('payments/driver/qr/');
  static Future<Map<String, dynamic>> saveProfile(
          {required String upiId,
          required String password,
          required bool attested,
          required bool active,
          String? imagePath}) =>
      imagePath == null
          ? AuthService.postJson('payments/driver/profile/', {
              'upi_id': upiId,
              'password': password,
              'ownership_attested': attested,
              'active': active
            })
          : AuthService.uploadUpiProfile(imagePath, {
              'upi_id': upiId,
              'password': password,
              'ownership_attested': attested.toString(),
              'active': active.toString()
            });
  static Future<Map<String, dynamic>> create(int bookingId) =>
      AuthService.postJson('payments/trips/$bookingId/');
  static Future<Map<String, dynamic>> get(int bookingId) =>
      AuthService.getJson('payments/trips/$bookingId/');
  static Future<Uint8List> qrImage(int bookingId) =>
      AuthService.getPrivateBytes('payments/trips/$bookingId/qr/');
  static Future<Map<String, dynamic>> report(int bookingId, String reference) =>
      AuthService.postJson(
          'payments/trips/$bookingId/report/', {'reference': reference});
  static Future<Map<String, dynamic>> confirm(int bookingId,
          {required String receivedAmount,
          required String bankReference,
          required bool checkedBank}) =>
      AuthService.postJson('payments/trips/$bookingId/review/', {
        'action': 'confirm',
        'received_amount': receivedAmount,
        'bank_reference': bankReference,
        'checked_bank': checkedBank
      });
  static Future<Map<String, dynamic>> reject(int bookingId, String note) =>
      AuthService.postJson('payments/trips/$bookingId/review/',
          {'action': 'reject', 'note': note});
  static Future<Map<String, dynamic>> cancel(int bookingId) =>
      AuthService.postJson(
          'payments/trips/$bookingId/cancel/', {'checked_no_payment': true});
  static Future<void> openUPI(String payload) async {
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.scheme != 'upi' || uri.host != 'pay') {
      throw ApiException('Invalid UPI payment payload.');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw ApiException(
          'No UPI app could be opened. Use another device to scan, or use your UPI app’s gallery scanner if supported.');
    }
    // App return/callback is NEVER treated as proof of payment.
  }

  static Future<void> shareQR(int bookingId) async {
    final bytes = await qrImage(bookingId);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/DriveMate-UPI-trip-$bookingId.png');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text:
            'DriveMate trip #$bookingId. Pay the exact fare once and check the receiver. This personal QR is not single-use at the bank.'));
  }
}
