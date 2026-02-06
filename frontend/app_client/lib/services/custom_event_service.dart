import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CustomEvent {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String? location;
  final String color; // Hex color code

  CustomEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    this.location,
    this.color = '#6366F1', // Default purple color
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'location': location,
      'color': color,
    };
  }

  factory CustomEvent.fromJson(Map<String, dynamic> json) {
    return CustomEvent(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      date: DateTime.parse(json['date']),
      location: json['location'],
      color: json['color'] ?? '#6366F1',
    );
  }
}

class CustomEventService {
  static const String _storageKey = 'custom_events';

  // Load all custom events
  static Future<List<CustomEvent>> loadEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? eventsJson = prefs.getString(_storageKey);
      
      if (eventsJson == null) {
        return [];
      }

      final List<dynamic> decoded = jsonDecode(eventsJson);
      return decoded.map((json) => CustomEvent.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading custom events: $e');
      return [];
    }
  }

  // Save all custom events
  static Future<bool> saveEvents(List<CustomEvent> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String eventsJson = jsonEncode(
        events.map((event) => event.toJson()).toList(),
      );
      return await prefs.setString(_storageKey, eventsJson);
    } catch (e) {
      debugPrint('Error saving custom events: $e');
      return false;
    }
  }

  // Add a new custom event
  static Future<bool> addEvent(CustomEvent event) async {
    final events = await loadEvents();
    events.add(event);
    return await saveEvents(events);
  }

  // Update an existing custom event
  static Future<bool> updateEvent(CustomEvent updatedEvent) async {
    final events = await loadEvents();
    final index = events.indexWhere((e) => e.id == updatedEvent.id);
    
    if (index != -1) {
      events[index] = updatedEvent;
      return await saveEvents(events);
    }
    return false;
  }

  // Delete a custom event
  static Future<bool> deleteEvent(String eventId) async {
    final events = await loadEvents();
    events.removeWhere((e) => e.id == eventId);
    return await saveEvents(events);
  }
}

