import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Response from Ayla AI including any event that was added
class AylaResponse {
  final String answer;
  final Map<String, dynamic>? eventAdded;
  
  AylaResponse({required this.answer, this.eventAdded});
}

/// Service for communicating with the Ayla AI backend
class AylaService {
  /// Determine Base URL based on platform
  static String get baseUrl {
    if (kIsWeb) {
      return "http://127.0.0.1:8000";
    } else if (Platform.isAndroid) {
      return "http://10.0.2.2:8000";
    } else {
      return "http://127.0.0.1:8000"; // iOS / Desktop
    }
  }

  /// Send a question to Ayla AI with student context
  /// 
  /// Returns AylaResponse with answer and optional event data
  static Future<AylaResponse> askAyla({
    required String question,
    required Map<String, dynamic> context,
    String? studentId,
  }) async {
    final url = Uri.parse('$baseUrl/ask_ayla');
    
    try {
      debugPrint("Sending question to Ayla: ${question.substring(0, question.length > 50 ? 50 : question.length)}...");
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': question,
          'student_context': context,
          'student_id': studentId,
        }),
      );

      debugPrint("Ayla response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> result = jsonDecode(response.body);
        
        if (result['success'] == true && result['answer'] != null) {
          // Check if an event was added
          final eventAdded = result['event_added'];
          if (eventAdded != null) {
            debugPrint("Event was added: ${eventAdded['title']}");
          }
          return AylaResponse(
            answer: result['answer'],
            eventAdded: eventAdded,
          );
        } else {
          final errorMsg = result['error'] ?? "Ayla couldn't process your request.";
          throw Exception(errorMsg);
        }
      } else {
        // Try to parse error from response body
        try {
          final errorData = jsonDecode(response.body);
          final errorMsg = errorData['error'] ?? errorData['detail'] ?? "Server error occurred";
          throw Exception(errorMsg);
        } catch (e) {
          throw Exception("Unable to connect to Ayla. Please check your connection.");
        }
      }
    } on SocketException {
      throw Exception("Unable to connect to server. Please check your internet connection.");
    } on FormatException {
      throw Exception("Invalid response from Ayla. Please try again.");
    } catch (e) {
      debugPrint("Ayla service error: $e");
      if (e is Exception) {
        rethrow;
      }
      throw Exception("Something went wrong. Please try again.");
    }
  }

  /// Fetch calendar events for a student
  static Future<List<Map<String, dynamic>>> getEvents(String studentId) async {
    final url = Uri.parse('$baseUrl/events/$studentId');
    
    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> result = jsonDecode(response.body);
        if (result['success'] == true) {
          return List<Map<String, dynamic>>.from(result['events'] ?? []);
        }
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching events: $e");
      return [];
    }
  }

  /// Delete a calendar event by ID
  static Future<bool> deleteEvent(int eventId) async {
    final url = Uri.parse('$baseUrl/events/$eventId');
    
    try {
      final response = await http.delete(url);
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Error deleting event: $e");
      return false;
    }
  }
}
