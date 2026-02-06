import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service for workspace operations
class WorkspaceService {
  /// Determine Base URL based on platform
  /// Base URL for backend
  static String get baseUrl {
    if (kIsWeb) {
      return "http://127.0.0.1:8000";
    } else if (Platform.isAndroid) {
      return "http://10.0.2.2:8000";
    } else {
      return "http://127.0.0.1:8000";
    }
  }


  /// Get all workspaces for a student
  static Future<List<Map<String, dynamic>>> getWorkspaces(String studentId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/workspaces/$studentId'));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return List<Map<String, dynamic>>.from(result['workspaces'] ?? []);
        }
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching workspaces: $e");
      return [];
    }
  }

  /// Create a new workspace
  static Future<Map<String, dynamic>?> createWorkspace(String studentId, String name) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/workspaces'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'student_id': studentId, 'name': name}),
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['workspace'];
        }
      }
      return null;
    } catch (e) {
      debugPrint("Error creating workspace: $e");
      return null;
    }
  }

  /// Delete a workspace
  // Updated ID to String (UUID)
  static Future<bool> deleteWorkspace(String workspaceId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/workspaces/$workspaceId'));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Error deleting workspace: $e");
      return false;
    }
  }

  /// Get notes for a workspace
  // Updated ID to String (UUID)
  static Future<String> getNotes(String workspaceId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/workspaces/$workspaceId/notes'));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['content'] ?? '';
        }
      }
      return '';
    } catch (e) {
      debugPrint("Error fetching notes: $e");
      return '';
    }
  }

  /// Save notes for a workspace
  // Updated ID to String (UUID) & Added userId
  static Future<bool> saveNotes(String workspaceId, String content, String userId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/workspaces/$workspaceId/notes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': content, 
          'user_id': userId
        }),
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Error saving notes: $e");
      return false;
    }
  }

  /// Get chat history for a workspace
  // Updated ID to String (UUID)
  static Future<List<Map<String, dynamic>>> getChats(String workspaceId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/workspaces/$workspaceId/chats'));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return List<Map<String, dynamic>>.from(result['chats'] ?? []);
        }
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching chats: $e");
      return [];
    }
  }

  /// Send a chat message in workspace context
  // Updated ID to String (UUID) & Added userId
  static Future<String?> sendChat(String workspaceId, String userId, String message, String notesContext) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/workspaces/$workspaceId/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'message': message,
          'notes_context': notesContext,
        }),
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['answer'];
        }
      }
      return null;
    } catch (e) {
      debugPrint("Error sending chat: $e");
      return null;
    }
  }

  /// Send a chat message to the Chat Assistant (Ayla).
  /// Uses dedicated /assistant/chat endpoint with academic context from Supabase.
  /// This is for the floating Ayla widget - separate from workspace chat.
  static Future<String?> sendAssistantChat(
    String message, {
    String? userId,
    Map<String, dynamic>? studentContext,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/assistant/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'user_id': userId ?? 'anonymous',
          'student_context': studentContext,
        }),
      );
      
      debugPrint("Assistant chat response: ${response.statusCode}");
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        debugPrint("Chat history count: ${result['history_count']}");
        return result['result'];
      } else {
        debugPrint("Assistant error: ${response.body}");
        return "Sorry, I couldn't process your request. Error: ${response.statusCode}";
      }
    } catch (e) {
      debugPrint("Error sending assistant chat: $e");
      return "Sorry, I'm having trouble connecting to the AI service. Please try again.";
    }
  }

  /// [DEPRECATED] Use sendAssistantChat for floating widget, or sendChat for workspace.
  /// Kept for backward compatibility.
  static Future<String?> sendGeminiChat(
    String message, {
    String? userId,
    Map<String, dynamic>? studentContext,
  }) async {
    // Redirect to assistant chat
    return sendAssistantChat(message, userId: userId, studentContext: studentContext);
  }

  /// Get files for a workspace
  // Updated ID to String (UUID)
  static Future<List<Map<String, dynamic>>> getFiles(String workspaceId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/workspaces/$workspaceId/files'));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return List<Map<String, dynamic>>.from(result['files'] ?? []);
        }
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching files: $e");
      return [];
    }
  }

  /// Delete a file
  // Updated ID to String (UUID)
  static Future<bool> deleteFile(String fileId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/workspaces/files/$fileId'));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Error deleting file: $e");
      return false;
    }
  }

  /// Upload a file to workspace
  // Updated to use MultipartRequest & bytes for Web compatibility
  static Future<bool> uploadFile(String workspaceId, List<int> fileBytes, String fileName, String userId) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/workspaces/$workspaceId/files'),
      );
      
      // Add text fields
      request.fields['user_id'] = userId;
      
      // Add file using bytes (works on Web and Mobile)
      request.files.add(
        http.MultipartFile.fromBytes(
          'file', // Field name matches FastAPI
          fileBytes,
          filename: fileName,
        )
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Error uploading file: $e");
      return false;
    }
  }
}

