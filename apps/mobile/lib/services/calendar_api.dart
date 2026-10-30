// lib/services/calendar_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart' show ApiResult, ApiService;
import 'token_store.dart';

class CalendarEvent {
  final String id;
  final String title;
  final DateTime date;
  final List<String> departments;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.departments,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
    id: j['id'] as String,
    title: j['title'] as String,
    date: DateTime.parse(j['event_date'] as String),
    departments: (j['departments'] as List<dynamic>).cast<String>(),
  );
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class CalendarApi {
  static Future<ApiResult<List<CalendarEvent>>> events(DateTime start, DateTime end) async {
    final token = await TokenStore.accessToken();
    if (token == null) {
      return ApiResult.failure(statusCode: 401, message: 'Nu ești autentificat. Conectează-te din nou.');
    }
    try {
      final uri = Uri.parse(
          '${ApiService.baseUrl}/calendar/events?start=${isoDate(start)}&end=${isoDate(end)}');
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        final events = list
            .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
            .toList();
        return ApiResult.success(events, statusCode: 200);
      }
      return ApiResult.failure(
        statusCode: response.statusCode,
        message: 'Nu am putut încărca calendarul (eroarea ${response.statusCode}).',
      );
    } catch (_) {
      return ApiResult.failure(
        message: 'Nu mă pot conecta la server. Verifică dacă backend-ul rulează.',
      );
    }
  }
}