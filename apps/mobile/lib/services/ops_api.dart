// lib/services/ops_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'admin_api.dart' show MemberDetails, MemberSummary;
import 'api_service.dart' show ApiResult, ApiService;
import 'token_store.dart';

class CreatorDepartment {
  final String id;
  final String name;

  const CreatorDepartment({required this.id, required this.name});

  factory CreatorDepartment.fromJson(Map<String, dynamic> j) =>
      CreatorDepartment(id: j['id'] as String, name: j['name'] as String);
}

class CreatedCode {
  final String id;
  final String code;
  final DateTime expiresAt;
  final String departmentName;
  final String eventTitle;
  final int hours;

  const CreatedCode({
    required this.id,
    required this.code,
    required this.expiresAt,
    required this.departmentName,
    required this.eventTitle,
    required this.hours,
  });

  factory CreatedCode.fromJson(Map<String, dynamic> j) => CreatedCode(
    id: j['id'] as String,
    code: j['code'] as String,
    expiresAt: DateTime.parse(j['expires_at'] as String),
    departmentName: j['department_name'] as String,
    eventTitle: j['event_title'] as String,
    hours: j['hours'] as int,
  );
}

class CodeItem {
  final String id;
  final String departmentName;
  final String eventTitle;
  final String? taskName;
  final int hours;
  final String workDate;
  final DateTime expiresAt;
  final int redemptions;
  final String state; // active | expired | cancelled

  const CodeItem({
    required this.id,
    required this.departmentName,
    required this.eventTitle,
    required this.taskName,
    required this.hours,
    required this.workDate,
    required this.expiresAt,
    required this.redemptions,
    required this.state,
  });

  factory CodeItem.fromJson(Map<String, dynamic> j) => CodeItem(
    id: j['id'] as String,
    departmentName: j['department_name'] as String,
    eventTitle: j['event_title'] as String,
    taskName: j['task_name'] as String?,
    hours: j['hours'] as int,
    workDate: j['work_date'] as String,
    expiresAt: DateTime.parse(j['expires_at'] as String),
    redemptions: j['redemptions'] as int,
    state: j['state'] as String,
  );
}

class ReviewEntry {
  final String id;
  final String status;
  final String source;
  final int hours;
  final String workDate;
  final String eventTitle;
  final String? taskName;
  final String? departmentName;
  final String? memberName;
  final String description;

  const ReviewEntry({
    required this.id,
    required this.status,
    required this.source,
    required this.hours,
    required this.workDate,
    required this.eventTitle,
    required this.taskName,
    required this.departmentName,
    required this.memberName,
    required this.description,
  });

  factory ReviewEntry.fromJson(Map<String, dynamic> j) => ReviewEntry(
    id: j['id'] as String,
    status: j['status'] as String,
    source: j['source'] as String,
    hours: j['hours'] as int,
    workDate: j['work_date'] as String,
    eventTitle: j['event_title'] as String,
    taskName: j['task_name'] as String?,
    departmentName: j['department_name'] as String?,
    memberName: j['member_name'] as String?,
    description: (j['description'] as String?) ?? '',
  );
}

class GrantItem {
  final String id;
  final String permission;
  final String scopeType;
  final DateTime expiresAt;

  const GrantItem({
    required this.id,
    required this.permission,
    required this.scopeType,
    required this.expiresAt,
  });

  factory GrantItem.fromJson(Map<String, dynamic> j) => GrantItem(
    id: j['id'] as String,
    permission: j['permission'] as String,
    scopeType: j['scope_type'] as String,
    expiresAt: DateTime.parse(j['expires_at'] as String),
  );
}

class OpsApi {
  static const String _base = ApiService.baseUrl;
  static const Duration _timeout = Duration(seconds: 15);

  // ---------- codes ----------

  static Future<ApiResult<List<CreatorDepartment>>> creatorDepartments() {
    return _send(
          (h) => http.get(Uri.parse('$_base/codes/departments'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => CreatorDepartment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<CreatedCode>> createCode({
    required String departmentId,
    required String eventId,
    String? taskId,
    String? newTaskName,
    required String workDate,
    required int hours,
    String? description,
  }) {
    return _send(
          (h) => http.post(
        Uri.parse('$_base/codes'),
        headers: h,
        body: jsonEncode({
          'department_id': departmentId,
          'event_id': eventId,
          'task_id': taskId,
          'new_task_name': newTaskName,
          'work_date': workDate,
          'hours': hours,
          'description': description,
        }),
      ),
          (r) => CreatedCode.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
    );
  }

  static Future<ApiResult<List<CodeItem>>> myCodes() {
    return _send(
          (h) => http.get(Uri.parse('$_base/codes'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => CodeItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<bool>> cancelCode(String codeId) {
    return _send(
          (h) => http.post(Uri.parse('$_base/codes/$codeId/cancel'), headers: h),
          (_) => true,
    );
  }

  static Future<ApiResult<bool>> redeemCode(String code) {
    return _send(
          (h) => http.post(Uri.parse('$_base/codes/redeem'), headers: h, body: jsonEncode({'code': code})),
          (_) => true,
    );
  }

  // ---------- hours review ----------

  static Future<ApiResult<List<ReviewEntry>>> reviewQueue() {
    return _send(
          (h) => http.get(Uri.parse('$_base/hours/review'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => ReviewEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<bool>> approve(String entryId) {
    return _send(
          (h) => http.post(Uri.parse('$_base/hours/review/$entryId/approve'), headers: h),
          (_) => true,
    );
  }

  static Future<ApiResult<bool>> reject(String entryId, String reason) {
    return _send(
          (h) => http.post(
        Uri.parse('$_base/hours/review/$entryId/reject'),
        headers: h,
        body: jsonEncode({'reason': reason}),
      ),
          (_) => true,
    );
  }

  // ---------- team (coordinators and admins) ----------

  static Future<ApiResult<List<MemberSummary>>> myTeam() {
    return _send(
          (h) => http.get(Uri.parse('$_base/team/members'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => MemberSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<MemberDetails>> memberDetails(String userId) {
    return _send(
          (h) => http.get(Uri.parse('$_base/team/members/$userId/details'), headers: h),
          (r) => MemberDetails.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
    );
  }

  static Future<ApiResult<List<GrantItem>>> memberGrants(String userId) {
    return _send(
          (h) => http.get(Uri.parse('$_base/team/members/$userId/grants'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => GrantItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<bool>> grantPermission(String userId, String permission) {
    return _send(
          (h) => http.post(
        Uri.parse('$_base/team/members/$userId/grants'),
        headers: h,
        body: jsonEncode({'permission': permission, 'hours': 48}),
      ),
          (_) => true,
    );
  }

  static Future<ApiResult<bool>> revokeGrant(String grantId) {
    return _send(
          (h) => http.delete(Uri.parse('$_base/team/grants/$grantId'), headers: h),
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