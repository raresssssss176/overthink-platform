// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // 10.0.2.2 is how the Android emulator reaches localhost on your PC.
  static const String baseUrl = 'http://10.0.2.2:8000';

  static Future<bool> registerUser({
    required String firstName,
    required String lastName,
    required String email,
    required String birthDate,
    required String school,
    required String locality,
    required String password,
    required bool acceptedPrivacyPolicy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'password': password,
          'confirm_password': password,
          'birth_date': birthDate,
          'school': school,
          'locality': locality,
          'accepted_privacy_policy': acceptedPrivacyPolicy,
        }),
      );

      // The backend returns 202 whether or not the e-mail already exists.
      if (response.statusCode == 202) {
        return true;
      }
      print('Register failed: ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      print('Register error: $e');
      return false;
    }
  }

  // The second argument is the 6-digit code from the e-mail.
  static Future<bool> verifyEmail(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      }
      print('Verify failed: ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      print('Verify error: $e');
      return false;
    }
  }

  // Returns the access token on success, or null.
  static Future<String?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['access_token'] as String?;
      }
      print('Login failed: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      print('Login error: $e');
      return null;
    }
  }
}