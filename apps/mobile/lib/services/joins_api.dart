// lib/services/joins_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart' show ApiResult, ApiService;
import 'token_store.dart';

class DeptRef {
  final String id;
  final String name;

  const DeptRef({required this.id, required this.name});

  factory DeptRef.fromJson(Map<String, dynamic> j) =>
      DeptRef(id: j['id'] as String, name: j['name'] as String);
}

class VolunteerRow {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final List<String> departments;
  final bool inMyDepartments;
  final List<String> pendingDepartmentIds;

  const VolunteerRow({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.departments,
    required this.inMyDepartments,
    required this.pendingDepartmentIds,
  });

  factory VolunteerRow.fromJson(Map<String, dynamic> j) => VolunteerRow(
    id: j['id'] as String,
    firstName: j['first_name'] as String,
    lastName: j['last_name'] as String,
    email: j['email'] as String,
    departments: (j['departments'] as List<dynamic>).cast<String>(),
    inMyDepartments: j['in_my_departments'] as bool,
    pendingDepartmentIds: (j['pending_department_ids'] as List<dynamic>).cast<String>(),
  );
}

class Overview {
  final List<DeptRef> myDepartments;
  final List<VolunteerRow> volunteers;

  const Overview({required this.myDepartments, required this.volunteers});
}

class JoinRequestItem {
  final String id;
  final String userName;
  final String departmentName;
  final String requestedByName;
  final String status;
  final DateTime createdAt;

  const JoinRequestItem({
    required this.id,
    required this.userName,
    required this.departmentName,
    required this.requestedByName,
    required this.status,
    required this.createdAt,
  });

  factory JoinRequestItem.fromJson(Map<String, dynamic> j) => JoinRequestItem(
    id: j['id'] as String,
    userName: j['user_name'] as String,
    departmentName: j['department_name'] as String,
    requestedByName: j['requested_by_name'] as String,
    status: j['status'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class JoinsApi {
  static const String _base = ApiService.baseUrl;
  static const Duration _timeout = Duration(seconds: 15);

  static Future<ApiResult<Overview>> overview() {
    return _send(
          (h) => http.get(Uri.parse('$_base/department-requests/overview'), headers: h),
          (r) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return Overview(
          myDepartments: (j['my_departments'] as List<dynamic>)
              .map((e) => DeptRef.fromJson(e as Map<String, dynamic>))
              .toList(),
          volunteers: (j['volunteers'] as List<dynamic>)
              .map((e) => VolunteerRow.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
    );
  }

  static Future<ApiResult<bool>> requestJoin(String userId, String departmentId) {
    return _send(
          (h) => http.post(
        Uri.parse('$_base/department-requests'),
        headers: h,
        body: jsonEncode({'user_id': userId, 'department_id': departmentId}),
      ),
          (_) => true,
    );
  }

  static Future<ApiResult<List<JoinRequestItem>>> pending() {
    return _send(
          (h) => http.get(Uri.parse('$_base/department-requests?status_filter=pending'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => JoinRequestItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<bool>> approve(String requestId) {
    return _send(
          (h) => http.post(Uri.parse('$_base/department-requests/$requestId/approve'), headers: h),
          (_) => true,
    );
  }

  static Future<ApiResult<bool>> reject(String requestId, String reason) {
    return _send(
          (h) => http.post(
        Uri.parse('$_base/department-requests/$requestId/reject'),
        headers: h,
        body: jsonEncode({'reason': reason}),
      ),
          (_) => true,
    );
  }

  // ---------- helpers ----------

  static Future<ApiResult<T>> _send<T>(
      Future<http.Response> Function(Map<String, String> headers) call,
      T Function(http.Response response) parse,
      ) async {
    final token = await TokenStore.accessToken();
    if (token == null) {
      return ApiResult.failure(statusCode: 401, message: 'Nu ești autentificat. Conectează-te din nou.');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    try {
      final response = await call(headers).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResult.success(parse(response), statusCode: response.statusCode);
      }
      return _failure<T>(response);
    } catch (_) {
      return ApiResult.failure(message: 'Nu mă pot conecta la server. Verifică dacă backend-ul rulează.');
    }
  }

  static ApiResult<T> _failure<T>(http.Response response) {
    String detail = '';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) {
        detail = body['detail'] as String;
      }
    } catch (_) {}
    return ApiResult.failure(
      statusCode: response.statusCode,
      detail: detail,
      message: detail.isNotEmpty ? detail : 'A apărut o eroare. Încearcă din nou.',
    );
  }
}