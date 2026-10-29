import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';

class HubService {
  static Future<Map<String, dynamic>> account() =>
      AuthService.getJson('hub/account/');
  static Future<Map<String, dynamic>> updateProfile(
          String name, String phone) =>
      AuthService.putJson('hub/account/', {'name': name, 'phone': phone});
  static Future<void> preferences(Map<String, dynamic> values) async {
    await AuthService.putJson('hub/preferences/', values);
  }

  static Future<List<Map<String, dynamic>>> list(String collection) async {
    final data = await AuthService.getJson('hub/collections/$collection/');
    return rows(data);
  }

  static List<Map<String, dynamic>> rows(Map<String, dynamic> data) =>
      ((data['results'] as List?) ?? [])
          .whereType<Map>()
          .map((r) => r.cast<String, dynamic>())
          .toList();
  static Future<Map<String, dynamic>> save(
          String collection, Map<String, dynamic> data, {int? id}) =>
      id == null
          ? AuthService.postJson('hub/collections/$collection/', data)
          : AuthService.putJson('hub/collections/$collection/$id/', data);
  static Future<void> remove(String collection, int id) async {
    await AuthService.deleteJson('hub/collections/$collection/$id/');
  }

  static Future<List<Map<String, dynamic>>> search(String query) async =>
      rows(await AuthService.getJson(
          'hub/map/search/?q=${Uri.encodeQueryComponent(query)}'));
  static Future<List<Map<String, dynamic>>> reverse(
          double lat, double lon) async =>
      rows(await AuthService.getJson('hub/map/search/?lat=$lat&lon=$lon'));
  static Future<Map<String, dynamic>> tickets() =>
      AuthService.getJson('hub/tickets/');
  static Future<Map<String, dynamic>> ticket(int id) =>
      AuthService.getJson('hub/tickets/$id/');
  static Future<Map<String, dynamic>> createTicket(Map<String, dynamic> data) =>
      AuthService.postJson('hub/tickets/', data);
  static Future<void> reply(int id, String text, {String? status}) async {
    await AuthService.postJson('hub/tickets/$id/',
        {'text': text, if (status != null) 'status': status});
  }

  static Future<Map<String, dynamic>> promotions() =>
      AuthService.getJson('hub/promotions/');
  static Future<void> claim(String code) async {
    await AuthService.postJson('hub/promotions/', {'code': code});
  }

  static Future<Map<String, dynamic>> startCode(int id,
          {bool regenerate = false}) =>
      regenerate
          ? AuthService.postJson('rides/bookings/$id/start-code/')
          : AuthService.getJson('rides/bookings/$id/start-code/');
  static Future<void> cashReceived(int id) async {
    await AuthService.postJson('rides/bookings/$id/cash/');
  }

  static Future<void> rate(int id, int score, String comment) async {
    await AuthService.postJson(
        'rides/bookings/$id/rating/', {'score': score, 'comment': comment});
  }

  static Future<void> location(int id, double lat, double lon) async {
    await AuthService.postJson('rides/bookings/$id/location/', {
      'latitude': lat.toStringAsFixed(7),
      'longitude': lon.toStringAsFixed(7)
    });
  }

  static Future<void> emailReceipt(int id) async {
    await AuthService.postJson('rides/bookings/$id/receipt/');
  }

  static Future<void> requestEmailChange(String email, String password) async {
    await AuthService.postJson(
        'hub/email/', {'email': email, 'password': password});
  }

  static Future<Map<String, dynamic>> confirmEmail(String otp) =>
      AuthService.putJson('hub/email/', {'otp': otp});
  static Future<void> deactivate(String password) async {
    await AuthService.postJson('hub/privacy/', {'password': password});
  }

  static Future<Map<String, dynamic>> exportData() =>
      AuthService.getJson('hub/privacy/');

  static Future<void> dial(String phone) async {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty ||
        !await launchUrl(Uri(scheme: 'tel', path: number),
            mode: LaunchMode.externalApplication)) {
      throw ApiException(
          'No dialer is available. You can copy the displayed number instead.');
    }
  }

  static Future<void> navigate(double latitude, double longitude) async {
    final url = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$latitude,$longitude',
      'travelmode': 'driving'
    });
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw ApiException('No navigation app/browser could be opened.');
    }
  }

  static Future<void> shareText(String text, {Rect? origin}) async {
    await SharePlus.instance
        .share(ShareParams(text: text, sharePositionOrigin: origin));
  }

  static Future<void> shareReceipt(int id, {Rect? origin}) async {
    final bytes =
        await AuthService.getPrivateBytes('rides/bookings/$id/receipt/');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/DriveMate-trip-$id.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin));
  }
}
