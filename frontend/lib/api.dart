import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Api {
  // Dynamically resolves host target: uses 10.0.2.2 for Android emulators unless API_URL is supplied
  static String get base {
    const envUrl = String.fromEnvironment('API_URL');
    if (envUrl.isNotEmpty) return envUrl;
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:3000/api';
    }
    return 'http://localhost:3000/api';
  }

  final _storage = const FlutterSecureStorage();
  String? token;

  Future<void> restore() async {
    token = await _storage.read(key: 'dreamtopia_token');
  }

  Future<void> signOut() async {
    token = null;
    await _storage.delete(key: 'dreamtopia_token');
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'
      };

  Future<dynamic> call(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final request = http.Request(method, Uri.parse('$base/$path'))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 20)));
    return _decode(response);
  }

  dynamic _decode(http.Response r) {
    dynamic data;
    try {
      data = jsonDecode(r.body);
    } catch (_) {
      throw ApiException(
          'The studio server could not respond. Please try again.',
          r.statusCode);
    }

    // Unblock 401 stuck states by purging stale storage tokens immediately
    if (r.statusCode == 401) {
      signOut();
      final message = data is Map ? data['message'] : null;
      throw ApiException(
          message is List
              ? message.join('\n')
              : message?.toString() ?? 'Unauthorized. Please sign in again.',
          401);
    }

    if (r.statusCode >= 400) {
      final message = data is Map ? data['message'] : null;
      throw ApiException(
          message is List
              ? message.join('\n')
              : message?.toString() ?? 'Something went wrong.',
          r.statusCode);
    }
    return data;
  }

  Future<void> authenticate(String email, String password,
      {String? name}) async {
    final result = await call('auth/${name == null ? 'login' : 'register'}',
        method: 'POST',
        body: {
          'email': email.trim(),
          'password': password,
          if (name != null) 'name': name.trim()
        });
    token = result['accessToken'] as String;
    await _storage.write(key: 'dreamtopia_token', value: token);
  }

  Future<String> upload(Uint8List bytes, String name) async {
    final request = http.MultipartRequest('POST', Uri.parse('$base/proofs'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 40)));
    return _decode(response)['id'] as String;
  }

  Future<Uint8List> proof(String id) async {
    final r = await http
        .get(Uri.parse('$base/proofs/$id'), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      _decode(r);
      throw ApiException('Cannot open this proof.');
    }
    return r.bodyBytes;
  }
}