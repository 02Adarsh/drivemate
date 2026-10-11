import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AuthService {
  static Future<Map<String,dynamic>> _post(String path,Map<String,dynamic> data) async {
    final response=await http.post(Uri.parse('$apiBaseUrl/auth/$path'),headers:{'Content-Type':'application/json'},body:jsonEncode(data)).timeout(const Duration(seconds:25));
    Map<String,dynamic> body;
    try { body=jsonDecode(response.body) as Map<String,dynamic>; }
    catch (_) { throw Exception('Server response was not JSON (HTTP ${response.statusCode}). Check backend, firewall and API address.'); }
    if(response.statusCode<200||response.statusCode>=300) throw Exception(body['detail']??body['message']??'Request failed (${response.statusCode})');
    return body;
  }
  static Future<Map<String,dynamic>> register(String name,String email,String phone,String password,String role)=>_post('register/',{'full_name':name,'email':email,'phone':phone,'password':password,'role':role});
  static Future<Map<String,dynamic>> login(String identifier,String password,String role)=>_post('login/',{'identifier':identifier,'password':password,'role':role});
  static Future<Map<String,dynamic>> verify(String email,String otp)=>_post('verify-otp/',{'email':email,'otp':otp});
  static Future<Map<String,dynamic>> resend(String email)=>_post('resend-otp/',{'email':email});
  static Future<Map<String,dynamic>> requestPasswordReset(String email)=>_post('password/reset/request/',{'email':email});
  static Future<Map<String,dynamic>> confirmPasswordReset(String email,String otp,String password)=>_post('password/reset/confirm/',{'email':email,'otp':otp,'new_password':password});
  static Future<void> saveSession(Map<String,dynamic> data) async {final p=await SharedPreferences.getInstance();await p.setString('access',data['access'] as String);await p.setString('refresh',data['refresh'] as String);await p.setString('user',jsonEncode(data['user']));}
  static Future<Map<String,dynamic>> saveProfile(Map<String,dynamic> data) async {
    final p=await SharedPreferences.getInstance();final token=p.getString('access');
    final response=await http.put(Uri.parse('$apiBaseUrl/auth/profile/'),headers:{'Content-Type':'application/json','Authorization':'Bearer $token'},body:jsonEncode(data)).timeout(const Duration(seconds:25));
    Map<String,dynamic> body;try{body=jsonDecode(response.body) as Map<String,dynamic>;}catch(_){throw Exception('Profile server returned an invalid response.');}
    if(response.statusCode<200||response.statusCode>=300)throw Exception(body['detail']??body['message']??'Could not save profile.');return body;
  }
  static Future<Map<String,dynamic>> uploadPrivateFile(String endpoint,String path,{Map<String,String> fields=const{}}) async {
    final p=await SharedPreferences.getInstance();final token=p.getString('access');
    final request=http.MultipartRequest('POST',Uri.parse('$apiBaseUrl/auth/$endpoint'));
    if(token!=null)request.headers['Authorization']='Bearer $token';
    request.fields.addAll(fields);request.files.add(await http.MultipartFile.fromPath('file',path));
    final streamed=await request.send().timeout(const Duration(seconds:40));final response=await http.Response.fromStream(streamed);
    Map<String,dynamic> body;try{body=jsonDecode(response.body) as Map<String,dynamic>;}catch(_){throw Exception('Upload server returned an invalid response.');}
    if(response.statusCode<200||response.statusCode>=300)throw Exception(body['detail']??body['message']??'Upload failed.');return body;
  }
}
