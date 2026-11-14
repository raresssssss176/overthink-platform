// lib/services/attendance_api.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_service.dart' show ApiResult, ApiService;
import 'token_store.dart';

class AttendanceEvent {
  final String id;
  final String title;
  final String eventDate;
  final List<String> departments;
  final int totalParticipants;
  final int markedParticipants;

  const AttendanceEvent({
    required this.id,
    required this.title,
    required this.eventDate,
    required this.departments,
    required this.totalParticipants,
    required this.markedParticipants,
  });

  factory AttendanceEvent.fromJson(Map<String, dynamic> j) => AttendanceEvent(
    id: j['id'] as String,
    title: j['title'] as String,
    eventDate: j['event_date'] as String,
    departments: (j['departments'] as List<dynamic>).cast<String>(),
    totalParticipants: j['total_participants'] as int,
    markedParticipants: j['marked_participants'] as int,
  );
}

class RosterParticipant {
  final String userId;
  final String firstName;
  final String lastName;
  final String email;
  final String? acronym;
  final List<String> departments;
  final String attendanceStatus; // unknown | present | absent | excused

  const RosterParticipant({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.acronym,
    required this.departments,
    required this.attendanceStatus,
  });

  factory RosterParticipant.fromJson(Map<String, dynamic> j) => RosterParticipant(
    userId: j['user_id'] as String,
    firstName: j['first_name'] as String,
    lastName: j['last_name'] as String,
    email: j['email'] as String,
    acronym: j['acronym'] as String?,
    departments: (j['departments'] as List<dynamic>).cast<String>(),
    attendanceStatus: j['attendance_status'] as String,
  );
}

class EventRoster {
  final String eventId;
  final String eventTitle;
  final String eventDate;
  final List<String> departments;
  final List<RosterParticipant> participants;

  const EventRoster({
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    required this.departments,
    required this.participants,
  });

  factory EventRoster.fromJson(Map<String, dynamic> j) => EventRoster(
    eventId: j['event_id'] as String,
    eventTitle: j['event_title'] as String,
    eventDate: j['event_date'] as String,
    departments: (j['departments'] as List<dynamic>).cast<String>(),
    participants: (j['participants'] as List<dynamic>)
        .map((e) => RosterParticipant.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class AttendanceApi {
  static const String _base = ApiService.baseUrl;
  static const Duration _timeout = Duration(seconds: 15);

  static Future<ApiResult<List<AttendanceEvent>>> todayEvents() {
    return _send(
          (h) => http.get(Uri.parse('$_base/attendance/events'), headers: h),
          (r) => (jsonDecode(r.body) as List<dynamic>)
          .map((e) => AttendanceEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<ApiResult<EventRoster>> roster(String eventId) {
    return _send(
          (h) => http.get(Uri.parse('$_base/attendance/events/$eventId/roster'), headers: h),
          (r) => EventRoster.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
    );
  }

  static Future<ApiResult<bool>> saveRoster(
      String eventId,
      Map<String, String> statusesByUserId,
      ) {
    final items = [
      for (final entry in statusesByUserId.entries)
        {'user_id': entry.key, 'attendance_status': entry.value},
    ];
    return _send(
          (h) => http.put(
        Uri.parse('$_base/attendance/events/$eventId/roster'),
        headers: h,
        body: jsonEncode({'items': items}),
      ),
          (_) => true,
    );
  }

  /// Descarcă fișierul .xlsx și îl salvează local, returnând calea fișierului.
  static Future<ApiResult<String>> exportXlsx(String eventId) async {
    final token = await TokenStore.accessToken();
    if (token == null) {
      return ApiResult.failure(
        statusCode: 401,
        message: 'Nu ești autentificat. Conectează-te din nou.',
      );
    }
    try {
      final response = await http
          .get(
        Uri.parse('$_base/attendance/events/$eventId/export'),
        headers: {'Authorization': 'Bearer $token'},
      )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _failure<String>(response);
      }

      var fileName = 'prezenta_$eventId.xlsx';
      final disposition = response.headers['content-disposition'];
      if (disposition != null) {
        final match = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
        if (match != null) fileName = match.group(1)!;
      }

      final dir = Directory('/storage/emulated/0/Download');
      final targetDir = await dir.exists() ? dir : Directory.systemTemp;
      final file = File('${targetDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes, flush: true);

      return ApiResult.success(file.path, statusCode: response.statusCode);
    } catch (_) {
      return ApiResult.failure(
        message: 'Nu am putut exporta fișierul Excel.',
      );
    }
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