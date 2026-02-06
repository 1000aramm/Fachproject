import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class SessionService {
  static const String _sessionKey = 'cached_session';
  static const String _usernameKey = 'cached_username';
  static const String _passwordKey = 'cached_password';
  static const String _lastLoginKey = 'last_login_timestamp';

  // Save session data
  static Future<bool> saveSession(SessionData session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionJson = jsonEncode({
        'profile_name': session.profileName,
        'username': session.username,
        'user_id': session.userId,
        'ects_data': {
          'total_ects': session.ectsData.totalEcts,
          'courses_count': session.ectsData.coursesCount,
          'degree_program': session.ectsData.degreeProgram,
          'average_grade': session.ectsData.averageGrade,
          'best_grade': session.ectsData.bestGrade,
        },
        'moodle_deadlines': session.moodleDeadlines.map((d) => <String, dynamic>{
          'platform': d.platform,
          'title': d.title,
          'course': d.course,
          'date': d.date,
          'link': d.link,
          'raw_date': d.rawDate,
        }).toList(),
        'exam_requirements': session.examRequirements.map((e) => <String, dynamic>{
          'category': e.category,
          'exams': e.exams.map((exam) => <String, dynamic>{
            'name': exam.name,
            'ects': exam.ects,
            'type': exam.type,
            'required': exam.required,
            'passed': exam.passed, // CRITICAL: Include passed field!
          }).toList(),
        }).toList(),
        'current_classes': session.currentClasses,
        'detailed_grades': session.detailedGrades.map((g) => g.toJson()).toList(),
      });
      
      await prefs.setString(_sessionKey, sessionJson);
      await prefs.setString(_lastLoginKey, DateTime.now().toIso8601String());
      return true;
    } catch (e) {
      debugPrint('Error saving session: $e');
      return false;
    }
  }

  // Load cached session
  static Future<SessionData?> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionJson = prefs.getString(_sessionKey);
      
      if (sessionJson == null) {
        return null;
      }

      final Map<String, dynamic> decoded = jsonDecode(sessionJson);
      
      // Check if session is still valid (less than 7 days old)
      final lastLoginStr = prefs.getString(_lastLoginKey);
      if (lastLoginStr != null) {
        final lastLogin = DateTime.parse(lastLoginStr);
        final daysSinceLogin = DateTime.now().difference(lastLogin).inDays;
        
        // Session expires after 7 days
        if (daysSinceLogin > 7) {
          await clearSession();
          return null;
        }
      }

      var deadlinesList = decoded['moodle_deadlines'] as List;
      List<Deadline> deadlines = deadlinesList.map((i) => Deadline.fromJson(i)).toList();

      var examRequirementsList = decoded['exam_requirements'] as List? ?? [];
      List<ExamCategory> examRequirements = examRequirementsList.map((i) => ExamCategory.fromJson(i)).toList();

      var classesList = decoded['current_classes'] as List? ?? [];
      List<String> currentClasses = classesList.map((i) => i.toString()).toList();

      var detailedGradesList = decoded['detailed_grades'] as List? ?? [];
      List<DetailedGrade> detailedGrades = detailedGradesList.map((i) => DetailedGrade.fromJson(i)).toList();

      return SessionData(
        profileName: decoded['profile_name'] ?? 'Student',
        username: decoded['username'] ?? '',
        ectsData: ECTSData.fromJson(decoded['ects_data'] ?? {}),
        moodleDeadlines: deadlines,
        examRequirements: examRequirements,
        currentClasses: currentClasses,
        detailedGrades: detailedGrades,
        userId: decoded['user_id'],
      );
    } catch (e) {
      debugPrint('Error loading session: $e');
      return null;
    }
  }

  // Save credentials (optional, for auto-login)
  static Future<bool> saveCredentials(String username, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_usernameKey, username);
      // Note: In production, consider encrypting the password
      await prefs.setString(_passwordKey, password);
      return true;
    } catch (e) {
      debugPrint('Error saving credentials: $e');
      return false;
    }
  }

  // Load saved credentials
  static Future<Map<String, String>?> loadCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(_usernameKey);
      final password = prefs.getString(_passwordKey);
      
      if (username == null || password == null) {
        return null;
      }
      
      return {'username': username, 'password': password};
    } catch (e) {
      debugPrint('Error loading credentials: $e');
      return null;
    }
  }

  // Clear all cached data
  static Future<bool> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
      await prefs.remove(_lastLoginKey);
      return true;
    } catch (e) {
      debugPrint('Error clearing session: $e');
      return false;
    }
  }

  // Clear credentials (for logout)
  static Future<bool> clearCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_usernameKey);
      await prefs.remove(_passwordKey);
      await prefs.remove(_sessionKey);
      await prefs.remove(_lastLoginKey);
      return true;
    } catch (e) {
      debugPrint('Error clearing credentials: $e');
      return false;
    }
  }
}

