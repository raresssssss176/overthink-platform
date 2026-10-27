// lib/services/events_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart' show ApiResult, ApiService;
import 'token_store.dart';

class EventDepartment {
  final String id;
  final String name;

  const EventDepartment({required this.id, required this.name});

  factory EventDepartment.fromJson(Map<String, dynamic> j) =>
      EventDepartment(id: j['id'] as String, name: j['name'] as String);
}

class ManagedEvent {
  final String id;
  final String title;
  final String eventDate; // YYYY-MM-DD
  final String status;
  final List<String> departments;
  final String? creatorName;
  final bool canCancel;

  const ManagedEvent({
    required this.id,
    required this.title,
    required this.eventDate,
    required this.status,
    required this.departments,
    required this.creatorName,
    required this.canCancel,
  });

  factory ManagedEvent.fromJson(Map<String, dynamic> j) => ManagedEvent(
    id: j['id'] as String,
    title: j['title'] as String,
    eventDate: j['event_date'] as String,
    status: j['status'] as String,
    departments: (j['departments'] as List<dynamic>).cast<String>(),
    creatorName: j['created_by_name'] as String?,
    canCancel: j['can_cancel'] as bool,
  );
}

class EventsApi {
  static const String _base = ApiService.baseUrl;
  static const Duration _timeout = Duration(seconds: 15);

  static Future<ApiResult<List<EventDepartment>>> departments() {
    return _send(
          (h) => http.get(Uri.parse('$_base/events/departments'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => EventDepartment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<List<ManagedEvent>>> manage() {
    return _send(
          (h) => http.get(Uri.parse('$_base/events/manage'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => ManagedEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<bool>> create({
    required String title,
    required String startsOn,
    required List<String> departmentIds,
  }) {
    return _send(
          (h) => http.post(
        Uri.parse('$_base/events'),
        headers: h,
        body: jsonEncode({
          'title': title,
          'starts_on': startsOn,
          'department_ids': departmentIds,
        }),
      ),
          (_) => true,
    );
  }

  static Future<ApiResult<bool>> cancel(String eventId) {
    return _send(
          (h) => http.post(Uri.parse('$_base/events/$eventId/cancel'), headers: h),
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