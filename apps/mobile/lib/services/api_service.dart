// lib/services/api_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'token_store.dart';

/// Result of one API call. On success, [value] is set.
/// On failure, [message] is Romanian text for the user and [detail] is the raw
/// backend message, used by screens to decide what to do next.
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

class CurrentUser {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String accountStatus;
  final List<String> roles;

  const CurrentUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.accountStatus,
    required this.roles,
  });

  bool get isAdmin => roles.contains('admin');

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    return CurrentUser(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      email: json['email'] as String,
      accountStatus: json['account_status'] as String,
      roles: (json['roles'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

class PendingRequest {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String birthDate;
  final String school;
  final String locality;
  final String? phone;
  final String? acronym;
  final List<String> departments;
  final DateTime submittedAt;
  final bool overdue;
  final int reminderCount;

  const PendingRequest({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.birthDate,
    required this.school,
    required this.locality,
    required this.phone,
    required this.acronym,
    required this.departments,
    required this.submittedAt,
    required this.overdue,
    required this.reminderCount,
  });

  factory PendingRequest.fromJson(Map<String, dynamic> json) {
    return PendingRequest(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      email: json['email'] as String,
      birthDate: json['birth_date'] as String,
      school: json['school'] as String,
      locality: json['locality'] as String,
      phone: json['phone'] as String?,
      acronym: json['acronym'] as String?,
      departments: (json['departments'] as List<dynamic>? ?? []).cast<String>(),
      submittedAt: DateTime.parse(json['submitted_at'] as String),
      overdue: json['overdue'] as bool,
      reminderCount: json['reminder_count'] as int,
    );
  }
}

class ApiService {
  // 10.0.2.2 is how the Android emulator reaches localhost on your PC.
  static const String baseUrl = 'http://10.0.2.2:8000';
  static const Duration _timeout = Duration(seconds: 15);
  static const Map<String, String> _jsonHeaders = {'Content-Type': 'application/json'};

  // ---------- public (no login needed) ----------

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

  // ---------- logged in ----------

  static Future<ApiResult<CurrentUser>> getMe() async {
    final token = await TokenStore.accessToken();
    if (token == null) return _notLoggedIn();
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/users/me'), headers: _authHeaders(token))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.success(CurrentUser.fromJson(json), statusCode: 200);
      }
      return _failure(response);
    } catch (_) {
      return _networkFailure();
    }
  }

  static Future<ApiResult<List<PendingRequest>>> fetchPendingRequests() async {
    final token = await TokenStore.accessToken();
    if (token == null) return _notLoggedIn();
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/membership-requests'), headers: _authHeaders(token))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        final requests = list
            .map((e) => PendingRequest.fromJson(e as Map<String, dynamic>))
            .toList();
        return ApiResult.success(requests, statusCode: 200);
      }
      return _failure(response);
    } catch (_) {
      return _networkFailure();
    }
  }

  static Future<ApiResult<bool>> approveRequest(String requestId) async {
    final token = await TokenStore.accessToken();
    if (token == null) return _notLoggedIn();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/admin/membership-requests/$requestId/approve'),
            headers: _authHeaders(token),
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

  static Future<ApiResult<bool>> rejectRequest(String requestId, String reason) async {
    final token = await TokenStore.accessToken();
    if (token == null) return _notLoggedIn();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/admin/membership-requests/$requestId/reject'),
            headers: _authHeaders(token),
            body: jsonEncode({'reason': reason}),
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

  // ---------- helpers ----------

  static Map<String, String> _authHeaders(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
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

  static ApiResult<T> _notLoggedIn<T>() {
    return ApiResult.failure(
      statusCode: 401,
      message: 'Nu ești autentificat. Conectează-te din nou.',
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
        return 'Sesiunea a expirat sau email/parola sunt greșite.';
      case 403:
        if (detail == 'E-mail not verified') {
          return 'Trebuie să îți verifici adresa de email.';
        }
        if (detail == 'Missing permission') {
          return 'Nu ai permisiunea necesară pentru această acțiune.';
        }
        if (detail == 'Account is awaiting approval') {
          return 'Contul tău așteaptă aprobarea unui administrator.';
        }
        return 'Contul nu este disponibil momentan.';
      case 404:
        return 'Cererea nu mai există.';
      case 409:
        return 'Cererea a fost deja procesată.';
      case 422:
        return 'Datele introduse nu sunt valide. Verifică formularul.';
      case 429:
        return 'Prea multe încercări. Încearcă din nou mai târziu.';
      default:
        return 'A apărut o eroare. Încearcă din nou.';
    }
  }
}
