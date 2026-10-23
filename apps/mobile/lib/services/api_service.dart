// lib/services/api_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'token_store.dart';

/// Result of one API call. On success, [value] is set.
/// On failure, [message] is a Romanian text for the user and [detail] is the
/// raw backend message, used to decide what the screen does next.
class ApiResult<T> {
  final T? value;
  final int? statusCode;
  final String? detail;
  final String? message;

  const ApiResult.success(this.value, {this.statusCode})
      : detail = null,
        message = null;

  const ApiResult.failure({this.statusCode, this.detail, required this.message})
      : value = null;

  bool get isSuccess => message == null;
}

class Department {
  final String id;
  final String name;
  final String slug;

  const Department({required this.id, required this.name, required this.slug});

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
    );
  }
}

class ApiService {
  // 10.0.2.2 is how the Android emulator reaches localhost on your PC.
  static const String baseUrl = 'http://10.0.2.2:8000';
  static const Duration _timeout = Duration(seconds: 15);
  static const Map<String, String> _jsonHeaders = {'Content-Type': 'application/json'};

  static Future<ApiResult<List<Department>>> fetchDepartments() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/departments'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        final departments = list
            .map((e) => Department.fromJson(e as Map<String, dynamic>))
            .toList();
        return ApiResult.success(departments, statusCode: 200);
      }
      return _failure(response);
    } catch (_) {
      return _networkFailure();
    }
  }

  static Future<ApiResult<bool>> registerUser({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String birthDate,
    required String school,
    required String locality,
    required String phone,
    required String acronym,
    required List<String> departmentIds,
    required bool acceptedPrivacyPolicy,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'first_name': firstName,
              'last_name': lastName,
              'email': email,
              'password': password,
              'confirm_password': password,
              'birth_date': birthDate,
              'school': school,
              'locality': locality,
              'phone': phone,
              'acronym': acronym,
              'department_ids': departmentIds,
              'accepted_privacy_policy': acceptedPrivacyPolicy,
            }),
          )
          .timeout(_timeout);
      // 202 is returned whether or not the e-mail already exists.
      if (response.statusCode == 202) {
        return ApiResult.success(true, statusCode: 202);
      }
      return _failure(response);
    } catch (_) {
      return _networkFailure();
    }
  }

  static Future<ApiResult<bool>> verifyEmail(String email, String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/verify-email'),
            headers: _jsonHeaders,
            body: jsonEncode({'email': email, 'code': code}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return ApiResult.success(true, statusCode: 200);
      }
      return _failure(response);
    } catch (_) {
      return _networkFailure();
    }
  }

  static Future<ApiResult<bool>> resendVerification(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/resend-verification'),
            headers: _jsonHeaders,
            body: jsonEncode({'email': email}),
          )
          .timeout(_timeout);
      if (response.statusCode == 202) {
        return ApiResult.success(true, statusCode: 202);
      }
      return _failure(response);
    } catch (_) {
      return _networkFailure();
    }
  }

  /// On success returns the account status ("pending" or "active") and stores the tokens.
  static Future<ApiResult<String>> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: _jsonHeaders,
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await TokenStore.save(
          access: data['access_token'] as String,
          refresh: data['refresh_token'] as String,
        );
        return ApiResult.success(data['account_status'] as String, statusCode: 200);
      }
      return _failure(response);
    } catch (_) {
      return _networkFailure();
    }
  }

  static ApiResult<T> _failure<T>(http.Response response) {
    final detail = _detailOf(response);
    return ApiResult.failure(
      statusCode: response.statusCode,
      detail: detail,
      message: _messageFor(response.statusCode, detail),
    );
  }

  static ApiResult<T> _networkFailure<T>() {
    return ApiResult.failure(
      message: 'Nu mă pot conecta la server. Verifică dacă backend-ul rulează.',
    );
  }

  static String _detailOf(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {}
    return '';
  }

  static String _messageFor(int status, String detail) {
    switch (status) {
      case 400:
        return 'Cod invalid sau expirat.';
      case 401:
        return 'Email sau parolă greșită.';
      case 403:
        return detail == 'E-mail not verified'
            ? 'Trebuie să îți verifici adresa de email.'
            : 'Contul nu este disponibil momentan.';
      case 422:
        return 'Datele introduse nu sunt valide. Verifică formularul.';
      case 429:
        return 'Prea multe încercări. Încearcă din nou mai târziu.';
      default:
        return 'A apărut o eroare. Încearcă din nou.';
    }
  }
}
