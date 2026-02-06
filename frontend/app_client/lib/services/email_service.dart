import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class UniEmail {
  final String id;
  final String subject;
  final String sender;
  final String date;

  UniEmail({
    required this.id,
    required this.subject,
    required this.sender,
    required this.date,
  });

  factory UniEmail.fromJson(Map<String, dynamic> json) {
    return UniEmail(
      id: json['id'] ?? '',
      subject: json['subject'] ?? '(No Subject)',
      sender: json['sender'] ?? 'Unknown',
      date: json['date'] ?? '',
    );
  }
}

class EmailService {
  String get baseUrl => ApiService.baseUrl;

  Future<List<UniEmail>> fetchEmails(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/email/fetch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['emails'] != null) {
          return (data['emails'] as List)
              .map((e) => UniEmail.fromJson(e))
              .toList();
        }
      } else if (response.statusCode == 401) {
        throw Exception('Invalid university credentials');
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching emails: $e');
      rethrow;
    }
  }

  Future<String> fetchEmailBody(String username, String password, String emailId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/email/details'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'email_id': emailId,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['body'] ?? '';
        }
      }
      return 'Could not retrieve email body.';
    } catch (e) {
      debugPrint('Error fetching email body: $e');
      return 'Error: $e';
    }
  }
}
