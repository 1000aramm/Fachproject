import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:js_interop' if (dart.library.io) '';
import 'package:web/web.dart' if (dart.library.io) '' as web;

/// Model for Google Calendar events
class GoogleCalendarEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String? location;
  final String? calendarId;
  final String colorHex;

  GoogleCalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    this.location,
    this.calendarId,
    this.colorHex = '#4285F4', // Default Google Blue
  });

  factory GoogleCalendarEvent.fromJson(Map<String, dynamic> json) {
    return GoogleCalendarEvent(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled Event',
      description: json['description'],
      startTime: DateTime.parse(json['start_time']),
      endTime: DateTime.parse(json['end_time']),
      isAllDay: json['is_all_day'] ?? false,
      location: json['location'],
      calendarId: json['calendar_id'],
      colorHex: json['color_hex'] ?? '#4285F4',
    );
  }
}

/// Service to manage Google Calendar integration via backend OAuth
class GoogleCalendarService {
  static const String _connectionKey = 'google_calendar_connected';
  static const String _emailKey = 'google_calendar_email';
  
  static final GoogleCalendarService _instance = GoogleCalendarService._internal();
  
  factory GoogleCalendarService() => _instance;
  
  GoogleCalendarService._internal();
  
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<GoogleCalendarEvent>> eventsNotifier = ValueNotifier<List<GoogleCalendarEvent>>([]);
  
  bool get isConnected => isConnectedNotifier.value;
  List<GoogleCalendarEvent> get events => eventsNotifier.value;
  
  String? _connectedEmail;
  String? get connectedEmail => _connectedEmail;
  
  String? _currentUserId;
  
  // Backend API base URL
  static String get _baseUrl {
    if (kIsWeb) {
      return "http://127.0.0.1:8000";
    } else {
      return "http://127.0.0.1:8000";
    }
  }
  
  /// Set the current user ID (call after Ayla login)
  void setUserId(String userId) {
    _currentUserId = userId;
  }
  
  /// Initialize the service and check connection status
  Future<void> initialize({String? userId}) async {
    if (userId != null) {
      _currentUserId = userId;
    }
    
    try {
      // Try to load cached state first
      final prefs = await SharedPreferences.getInstance();
      isConnectedNotifier.value = prefs.getBool(_connectionKey) ?? false;
      _connectedEmail = prefs.getString(_emailKey);
      
      // If we have a user ID, verify with backend
      if (_currentUserId != null) {
        await checkStatus();
      }
    } catch (e) {
      debugPrint('Error initializing Google Calendar service: $e');
      isConnectedNotifier.value = false;
    }
  }
  
  /// Check connection status with backend
  Future<void> checkStatus() async {
    if (_currentUserId == null) {
      debugPrint('Google Calendar checkStatus: No user ID set, skipping');
      return;
    }
    
    debugPrint('Google Calendar checkStatus: Checking for user $_currentUserId');
    
    try {
      final url = '$_baseUrl/calendar/status?user_id=$_currentUserId';
      debugPrint('Google Calendar checkStatus: Calling $url');
      
      final response = await http.get(
        Uri.parse(url),
      );
      
      debugPrint('Google Calendar checkStatus: Response ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final connected = data['connected'] == true;
        final email = data['email'] as String?;
        
        debugPrint('Google Calendar checkStatus: connected=$connected, email=$email');
        
        isConnectedNotifier.value = connected;
        _connectedEmail = email;
        
        // Cache the state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_connectionKey, connected);
        if (email != null) {
          await prefs.setString(_emailKey, email);
        }
        
        // If connected, fetch events
        if (connected) {
          await refreshEvents();
        }
      } else {
        debugPrint('Google Calendar checkStatus: Failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error checking Google Calendar status: $e');
    }
  }
  
  /// Connect to Google Calendar via backend OAuth
  Future<bool> connect() async {
    if (_currentUserId == null) {
      debugPrint('Cannot connect: No user ID set');
      return false;
    }
    
    try {
      // Get OAuth URL from backend
      final response = await http.get(
        Uri.parse('$_baseUrl/calendar/auth/url?user_id=$_currentUserId'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final url = data['url'] as String?;
        
        if (url != null) {
          // On web, use popup window
          if (kIsWeb) {
            _openPopupWindow(url);
            return true;
          } else {
            // On mobile/desktop, use external browser
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return true;
            }
          }
        }
      }
      
      debugPrint('Failed to get OAuth URL: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error connecting to Google Calendar: $e');
      return false;
    }
  }
  
  /// Open a popup window for OAuth (web only)
  void _openPopupWindow(String url) {
    if (kIsWeb) {
      // Use dart:html for web
      // ignore: avoid_web_libraries_in_flutter
      _openWebPopup(url);
    }
  }
  
  /// Web-specific popup implementation using JavaScript interop
  void _openWebPopup(String url) {
    // Calculate center position for popup
    const width = 500;
    const height = 650;
    
    // Use web package to open a proper popup window
    final screenWidth = web.window.screen.width;
    final screenHeight = web.window.screen.height;
    final left = (screenWidth - width) ~/ 2;
    final top = (screenHeight - height) ~/ 2;
    
    final features = 'width=$width,height=$height,left=$left,top=$top,toolbar=no,menubar=no,scrollbars=yes,resizable=yes';
    
    // Set up listener for message from popup before opening
    _setupMessageListener();
    
    web.window.open(url, 'google_oauth_popup', features);
  }
  
  bool _messageListenerSetup = false;
  
  /// Set up listener for postMessage from OAuth popup
  void _setupMessageListener() {
    if (_messageListenerSetup) return;
    _messageListenerSetup = true;
    
    web.window.addEventListener('message', (web.Event event) {
      final messageEvent = event as web.MessageEvent;
      final data = messageEvent.data;
      
      // Check if this is our OAuth message
      if (data != null) {
        try {
          // Handle the message - data should be a JS object
          final jsData = data as dynamic;
          if (jsData['type'] == 'google_calendar_oauth') {
            final status = jsData['status'] as String?;
            debugPrint('OAuth popup message received: status=$status');
            
            if (status == 'success') {
              // Refresh status from backend
              checkStatus();
            }
          }
        } catch (e) {
          // Not our message, ignore
          debugPrint('Error processing message: $e');
        }
      }
    }.toJS);
  }
  
  /// Disconnect from Google Calendar
  Future<bool> disconnect() async {
    if (_currentUserId == null) {
      // Just clear local state
      isConnectedNotifier.value = false;
      eventsNotifier.value = [];
      _connectedEmail = null;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_connectionKey, false);
      await prefs.remove(_emailKey);
      return true;
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/calendar/disconnect?user_id=$_currentUserId'),
      );
      
      if (response.statusCode == 200) {
        isConnectedNotifier.value = false;
        eventsNotifier.value = [];
        _connectedEmail = null;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_connectionKey, false);
        await prefs.remove(_emailKey);
        
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error disconnecting from Google Calendar: $e');
      return false;
    }
  }
  
  /// Toggle connection state
  Future<bool> toggleConnection() async {
    if (isConnected) {
      return await disconnect();
    } else {
      return await connect();
    }
  }
  
  /// Fetch events from backend
  Future<void> refreshEvents() async {
    if (_currentUserId == null || !isConnected) {
      return;
    }
    
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/calendar/events?user_id=$_currentUserId'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final eventsList = data['events'] as List<dynamic>;
          final events = eventsList
              .map((e) => GoogleCalendarEvent.fromJson(e as Map<String, dynamic>))
              .toList();
          
          eventsNotifier.value = events;
          debugPrint('Fetched ${events.length} Google Calendar events');
        } else {
          debugPrint('Failed to fetch events: ${data['error']}');
        }
      }
    } catch (e) {
      debugPrint('Error fetching Google Calendar events: $e');
    }
  }
  
  /// Get events for a specific date
  List<GoogleCalendarEvent> getEventsForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    return eventsNotifier.value.where((event) {
      if (event.isAllDay) {
        return event.startTime.isBefore(endOfDay) && 
               event.endTime.isAfter(startOfDay);
      }
      return event.startTime.isAfter(startOfDay) && 
             event.startTime.isBefore(endOfDay);
    }).toList();
  }
  
  /// Handle OAuth redirect (called when app detects google_connected=true in URL)
  Future<void> handleOAuthRedirect() async {
    debugPrint('OAuth redirect detected, checking status...');
    await checkStatus();
  }
}
