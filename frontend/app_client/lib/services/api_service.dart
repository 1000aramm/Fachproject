import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService {
  // Determine Base URL
  static String get baseUrl {
    if (kIsWeb) {
      return "http://127.0.0.1:8000";
    } else if (Platform.isAndroid) {
      return "http://10.0.2.2:8000";
    } else {
      return "http://127.0.0.1:8000"; // iOS / Desktop
    }
  }

  /// Login and fetch all user data
  /// [forceRefresh] - If true, bypasses 24-hour cache and fetches fresh data
  static Future<SessionData?> login(String username, String password, {bool forceRefresh = false}) async {
    final url = Uri.parse('$baseUrl/login');
    
    try {
      debugPrint("Attempting login to $url with user $username${forceRefresh ? ' (force refresh)' : ''}");
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'force_refresh': forceRefresh,
        }),
      );

      debugPrint("Response status: ${response.statusCode}");
      debugPrint("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> loginResult = jsonDecode(response.body);
        
        if (loginResult['success'] == true) {
          debugPrint("Login successful. Fetching BOSS data...");
          
          // Step 2: Fetch Grades from BOSS
          try {
            final gradesUrl = Uri.parse('$baseUrl/fetch-grades');
            final gradesResponse = await http.post(
              gradesUrl,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'username': username,
                'password': password,
                'force_refresh': forceRefresh,
              }),
            );
            
            debugPrint("BOSS Response status: ${gradesResponse.statusCode}");
            
            if (gradesResponse.statusCode == 200) {
              final Map<String, dynamic> gradesResult = jsonDecode(gradesResponse.body);
              if (gradesResult['success'] == true) {
                 debugPrint("BOSS data fetched successfully.");
                 
                 // Deadlines are already included in loginResult from the login process
                 // Merge deadlines from login into grades data
                 final sessionData = gradesResult['data'] as Map<String, dynamic>;
                 sessionData['username'] = username; // Ensure stable username is passed
                  if (loginResult['data'] != null) {
                    if (loginResult['data']['moodle_deadlines'] != null) {
                      sessionData['moodle_deadlines'] = loginResult['data']['moodle_deadlines'];
                      debugPrint("Merged ${(loginResult['data']['moodle_deadlines'] as List).length} deadlines from login");
                    }
                    if (loginResult['data']['current_classes'] != null) {
                      sessionData['current_classes'] = loginResult['data']['current_classes'];
                      debugPrint("Merged ${(loginResult['data']['current_classes'] as List).length} classes from login");
                    }
                    if (loginResult['data']['user_id'] != null) {
                      sessionData['user_id'] = loginResult['data']['user_id'];
                    }
                  }
                 
                 return SessionData.fromJson(sessionData);
              } else {
                 debugPrint("BOSS fetch failed: ${gradesResult['error']}");
                 // Fallback to basic login data
                 final sessionData = loginResult['data'] as Map<String, dynamic>;
                 sessionData['username'] = username;
                 return SessionData.fromJson(sessionData);
              }
            }
          } catch (e) {
            debugPrint("Error fetching BOSS data: $e");
            // Fallback to basic login data
          }
          
          final sessionData = loginResult['data'] as Map<String, dynamic>;
          sessionData['username'] = username;
          return SessionData.fromJson(sessionData);
        } else {
          // Extract error message from response - login failed
          final errorCode = loginResult['error']?.toString() ?? "";
          debugPrint("API returned error: $errorCode");
          
          // Check for specific error codes from backend
          if (errorCode == "invalid_credentials" || 
              errorCode.toLowerCase().contains("authentication failed") ||
              errorCode.toLowerCase().contains("login failed")) {
            throw Exception("Wrong username or password. Please check your credentials and try again.");
          } else if (errorCode == "error") {
            throw Exception("Login failed. Please verify your university credentials.");
          } else if (errorCode.isNotEmpty) {
            throw Exception(errorCode);
          } else {
            throw Exception("Login failed. Please check your credentials.");
          }
        }
      } else {
        // Try to parse error from response body
        try {
          final errorData = jsonDecode(response.body);
          final errorMsg = errorData['error'] ?? errorData['detail'] ?? "Server error occurred";
          throw Exception(errorMsg);
        } catch (e) {
          throw Exception("Unable to connect to server. Please check your internet connection.");
        }
      }
    } on SocketException {
      throw Exception("Unable to connect to server. Please check your internet connection and ensure the backend is running.");
    } on FormatException {
      throw Exception("Invalid response from server. Please try again.");
    } catch (e) {
      debugPrint("Login error: $e");
      // If it's already an Exception with a message, rethrow it
      if (e is Exception) {
        rethrow;
      }
      // Otherwise, wrap it in a user-friendly message
      throw Exception("Login failed. Please check your username and password.");
    }
  }
}
