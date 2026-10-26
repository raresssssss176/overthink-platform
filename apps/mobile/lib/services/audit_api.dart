// lib/services/audit_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'token_store.dart';

class AuditEntry {
  final String id;
  final DateTime createdAt;
  final String action;
  final String category;
  final String? actorName;
  final String? targetName;
  final String description;

  const AuditEntry({
    required this.id,
    required this.createdAt,
    required this.action,
    required this.category,
    required this.actorName,
    required this.targetName,
    required this.description,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      action: json['action'] as String,
      category: json['category'] as String,
      actorName: json['actor_name'] as String?,
      targetName: json['target_name'] as String?,
      description: json['description'] as String,
    );
  }
}

class AuditApi {
  static Future<ApiResult<List<AuditEntry>>> fetchLogs() async {
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
        Uri.parse('${ApiService.baseUrl}/admin/audit-logs?limit=500'),
        headers: {'Authorization': 'Bearer $token'},
      )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        final entries = list
            .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        return ApiResult.success(entries, statusCode: 200);
      }
      return ApiResult.failure(
        statusCode: response.statusCode,
        message: 'Nu am putut încărca jurnalul (eroarea ${response.statusCode}).',
      );
    } catch (_) {
      return ApiResult.failure(
        message: 'Nu mă pot conecta la server. Verifică dacă backend-ul rulează.',
      );
    }
  }
}