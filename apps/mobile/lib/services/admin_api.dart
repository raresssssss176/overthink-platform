// lib/services/admin_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'token_store.dart';

const String _base = ApiService.baseUrl;
const Duration _timeout = Duration(seconds: 15);

/// "1.5" for 90 minutes, "2" for 120 minutes.
String formatHours(int minutes) {
  final hours = minutes / 60;
  return hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toStringAsFixed(1);
}

class PendingItem {
  final String requestId;
  final String userId;
  final String firstName;
  final String lastName;
  final bool overdue;

  const PendingItem({
    required this.requestId,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.overdue,
  });

  factory PendingItem.fromJson(Map<String, dynamic> json) {
    return PendingItem(
      requestId: json['id'] as String,
      userId: json['user_id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      overdue: json['overdue'] as bool,
    );
  }
}

class MemberSummary {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final List<String> roles;
  final List<String> coordinatedDepartments;

  const MemberSummary({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.roles,
    required this.coordinatedDepartments,
  });

  bool get isAdmin => roles.contains('admin');
  bool get isCoordinator => roles.contains('coordinator');

  factory MemberSummary.fromJson(Map<String, dynamic> json) {
    return MemberSummary(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      email: json['email'] as String,
      roles: (json['roles'] as List<dynamic>).cast<String>(),
      coordinatedDepartments: (json['coordinated_departments'] as List<dynamic>).cast<String>(),
    );
  }
}

class DepartmentRef {
  final String id;
  final String name;

  const DepartmentRef({required this.id, required this.name});

  factory DepartmentRef.fromJson(Map<String, dynamic> json) {
    return DepartmentRef(id: json['id'] as String, name: json['name'] as String);
  }
}

class HoursSummary {
  final int approvedMinutes;
  final int pendingMinutes;
  final int rejectedMinutes;

  const HoursSummary({
    required this.approvedMinutes,
    required this.pendingMinutes,
    required this.rejectedMinutes,
  });

  factory HoursSummary.fromJson(Map<String, dynamic> json) {
    return HoursSummary(
      approvedMinutes: json['approved_minutes'] as int,
      pendingMinutes: json['pending_minutes'] as int,
      rejectedMinutes: json['rejected_minutes'] as int,
    );
  }
}

class MemberDetails {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String accountStatus;
  final String? phone;
  final String? acronym;
  final String? gender;
  final String? birthDate;
  final String? school;
  final String? locality;
  final String? membershipRequestId;
  final String? membershipRequestStatus;
  final List<String> roles;
  final List<DepartmentRef> departments;
  final HoursSummary hours;

  const MemberDetails({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.accountStatus,
    required this.phone,
    required this.acronym,
    required this.gender,
    required this.birthDate,
    required this.school,
    required this.locality,
    required this.membershipRequestId,
    required this.membershipRequestStatus,
    required this.roles,
    required this.departments,
    required this.hours,
  });

  bool get isAdmin => roles.contains('admin');
  bool get isCoordinator => roles.contains('coordinator');
  bool get isActive => accountStatus == 'active';
  bool get canDecideRequest => membershipRequestId != null && membershipRequestStatus == 'pending';

  factory MemberDetails.fromJson(Map<String, dynamic> json) {
    return MemberDetails(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      email: json['email'] as String,
      accountStatus: json['account_status'] as String,
      phone: json['phone'] as String?,
      acronym: json['acronym'] as String?,
      gender: json['gender'] as String?,
      birthDate: json['birth_date'] as String?,
      school: json['school'] as String?,
      locality: json['locality'] as String?,
      membershipRequestId: json['membership_request_id'] as String?,
      membershipRequestStatus: json['membership_request_status'] as String?,
      roles: (json['roles'] as List<dynamic>).cast<String>(),
      departments: (json['departments'] as List<dynamic>)
          .map((e) => DepartmentRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      hours: HoursSummary.fromJson(json['hours'] as Map<String, dynamic>),
    );
  }
}

class AdminApi {
  static Future<ApiResult<List<PendingItem>>> fetchPendingItems() {
    return _send(
          (headers) => http.get(Uri.parse('$_base/admin/membership-requests'), headers: headers),
          (response) => (jsonDecode(response.body) as List<dynamic>)
          .map((e) => PendingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<List<MemberSummary>>> fetchMembers() {
    return _send(
          (headers) => http.get(Uri.parse('$_base/admin/members'), headers: headers),
          (response) => (jsonDecode(response.body) as List<dynamic>)
          .map((e) => MemberSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<MemberDetails>> fetchMemberDetails(String userId) {
    return _send(
          (headers) => http.get(Uri.parse('$_base/admin/members/$userId/details'), headers: headers),
          (response) => MemberDetails.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  static Future<ApiResult<bool>> promote(String userId, String departmentId) {
    return _send(
          (headers) => http.post(
        Uri.parse('$_base/admin/members/$userId/promote'),
        headers: headers,
        body: jsonEncode({'department_id': departmentId}),
      ),
          (_) => true,
    );
  }

  static Future<ApiResult<bool>> demote(String userId) {
    return _send(
          (headers) => http.post(Uri.parse('$_base/admin/members/$userId/demote'), headers: headers),
          (_) => true,
    );
  }

  static Future<ApiResult<bool>> deleteMember(String userId) {
    return _send(
          (headers) => http.delete(Uri.parse('$_base/admin/members/$userId'), headers: headers),
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
      return ApiResult.failure(
        statusCode: 401,
        message: 'Nu ești autentificat. Conectează-te din nou.',
      );
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
      return ApiResult.failure(
        message: 'Nu mă pot conecta la server. Verifică dacă backend-ul rulează.',
      );
    }
  }

  static ApiResult<T> _failure<T>(http.Response response) {
    final detail = _detailOf(response);
    return ApiResult.failure(
      statusCode: response.statusCode,
      detail: detail,
      // Backend messages for admin actions are already in Romanian.
      message: detail.isNotEmpty ? detail : _genericMessage(response.statusCode),
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

  static String _genericMessage(int status) {
    switch (status) {
      case 401:
        return 'Sesiunea a expirat. Conectează-te din nou.';
      case 403:
        return 'Nu ai permisiunea necesară pentru această acțiune.';
      case 404:
        return 'Elementul nu mai există.';
      case 409:
        return 'Acțiunea nu se poate face în starea actuală.';
      default:
        return 'A apărut o eroare. Încearcă din nou.';
    }
  }
}