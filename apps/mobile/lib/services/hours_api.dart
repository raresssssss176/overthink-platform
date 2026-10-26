// lib/services/hours_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart' show ApiResult, ApiService;
import 'token_store.dart';

class DepartmentOption {
  final String id;
  final String name;

  const DepartmentOption({required this.id, required this.name});

  factory DepartmentOption.fromJson(Map<String, dynamic> json) {
    return DepartmentOption(id: json['id'] as String, name: json['name'] as String);
  }
}

class EventOption {
  final String id;
  final String title;

  const EventOption({required this.id, required this.title});

  factory EventOption.fromJson(Map<String, dynamic> json) {
    return EventOption(id: json['id'] as String, title: json['title'] as String);
  }
}

class TaskOption {
  final String id;
  final String name;

  const TaskOption({required this.id, required this.name});

  factory TaskOption.fromJson(Map<String, dynamic> json) {
    return TaskOption(id: json['id'] as String, name: json['name'] as String);
  }
}

class HoursApi {
  static const Duration _timeout = Duration(seconds: 15);

  static Future<ApiResult<List<DepartmentOption>>> myDepartments() {
    return _send(
          (headers) => http.get(Uri.parse('${ApiService.baseUrl}/hours/my-departments'), headers: headers),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => DepartmentOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<List<EventOption>>> events() {
    return _send(
          (headers) => http.get(Uri.parse('${ApiService.baseUrl}/hours/events'), headers: headers),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => EventOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<List<TaskOption>>> tasks(String eventId) {
    return _send(
          (headers) => http.get(Uri.parse('${ApiService.baseUrl}/hours/events/$eventId/tasks'), headers: headers),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => TaskOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<bool>> submitManual({
    required String departmentId,
    String? eventId,
    String? newEventTitle,
    String? taskId,
    String? newTaskName,
    required String workDate,
    required int hours,
    String? mentions,
  }) {
    return _send(
          (headers) => http.post(
        Uri.parse('${ApiService.baseUrl}/hours/manual'),
        headers: headers,
        body: jsonEncode({
          'department_id': departmentId,
          'event_id': eventId,
          'new_event_title': newEventTitle,
          'task_id': taskId,
          'new_task_name': newTaskName,
          'work_date': workDate,
          'hours': hours,
          'mentions': mentions,
        }),
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