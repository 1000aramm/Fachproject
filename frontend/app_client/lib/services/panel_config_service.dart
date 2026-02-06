import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PanelConfig {
  final String id;
  final String name;
  final IconData icon;
  bool isVisible;
  int order;
  String column; // 'left' or 'right'

  PanelConfig({
    required this.id,
    required this.name,
    required this.icon,
    this.isVisible = true,
    required this.order,
    required this.column,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconCodePoint': icon.codePoint,
    'iconFontFamily': icon.fontFamily,
    'isVisible': isVisible,
    'order': order,
    'column': column,
  };

  factory PanelConfig.fromJson(Map<String, dynamic> json) {
    return PanelConfig(
      id: json['id'],
      name: json['name'],
      icon: IconData(
        json['iconCodePoint'],
        fontFamily: json['iconFontFamily'],
      ),
      isVisible: json['isVisible'] ?? true,
      order: json['order'] ?? 0,
      column: json['column'] ?? 'left',
    );
  }

  PanelConfig copyWith({
    String? id,
    String? name,
    IconData? icon,
    bool? isVisible,
    int? order,
    String? column,
  }) {
    return PanelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      isVisible: isVisible ?? this.isVisible,
      order: order ?? this.order,
      column: column ?? this.column,
    );
  }
}

class PanelConfigService {
  static const String _panelConfigKey = 'panel_config';

  static List<PanelConfig> getDefaultPanels() {
    return [
      PanelConfig(id: 'stats', name: 'Statistics', icon: Icons.analytics_rounded, order: 0, column: 'left'),
      PanelConfig(id: 'study_planner', name: 'AI Study Planner', icon: Icons.auto_awesome_rounded, order: 1, column: 'left'),
      PanelConfig(id: 'deadlines', name: 'Deadlines', icon: Icons.timer_outlined, order: 2, column: 'left'),
      PanelConfig(id: 'classes', name: 'Classes', icon: Icons.auto_stories_rounded, order: 3, column: 'left'),
      PanelConfig(id: 'emails', name: 'University Emails', icon: Icons.email_outlined, order: 4, column: 'left'),
      PanelConfig(id: 'calendar', name: 'Calendar', icon: Icons.calendar_today_rounded, order: 0, column: 'right'),
      PanelConfig(id: 'exams', name: 'Exams', icon: Icons.verified_rounded, order: 1, column: 'right'),
      PanelConfig(id: 'workspaces', name: 'Workspaces', icon: Icons.layers_rounded, order: 2, column: 'right'),
    ];
  }

  static Future<List<PanelConfig>> loadPanelConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_panelConfigKey);
      
      if (configJson == null) {
        return getDefaultPanels();
      }

      final List<dynamic> decoded = jsonDecode(configJson);
      final savedPanels = decoded.map((json) => PanelConfig.fromJson(json)).toList();
      
      // Merge with defaults to ensure new panels are included
      final defaultPanels = getDefaultPanels();
      final savedIds = savedPanels.map((p) => p.id).toSet();
      
      for (final defaultPanel in defaultPanels) {
        if (!savedIds.contains(defaultPanel.id)) {
          savedPanels.add(defaultPanel);
        }
      }
      
      return savedPanels;
    } catch (e) {
      debugPrint('Error loading panel config: $e');
      return getDefaultPanels();
    }
  }

  static Future<bool> savePanelConfig(List<PanelConfig> panels) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = jsonEncode(panels.map((p) => p.toJson()).toList());
      await prefs.setString(_panelConfigKey, configJson);
      return true;
    } catch (e) {
      debugPrint('Error saving panel config: $e');
      return false;
    }
  }

  static Future<bool> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_panelConfigKey);
      return true;
    } catch (e) {
      debugPrint('Error resetting panel config: $e');
      return false;
    }
  }
}
