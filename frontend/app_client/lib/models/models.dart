class ECTSData {
  final double totalEcts;
  final int coursesCount;
  final String? degreeProgram;
  final double? averageGrade;
  final double? bestGrade;

  ECTSData({
    required this.totalEcts,
    required this.coursesCount,
    this.degreeProgram,
    this.averageGrade,
    this.bestGrade,
  });

  factory ECTSData.fromJson(Map<String, dynamic> json) {
    return ECTSData(
      totalEcts: (json['total_ects'] ?? 0).toDouble(),
      coursesCount: json['courses_count'] ?? 0,
      degreeProgram: json['degree_program'],
      averageGrade: json['average_grade']?.toDouble(),
      bestGrade: json['best_grade']?.toDouble(),
    );
  }
}

class Deadline {
  final String platform;
  final String title;
  final String course;
  final String date;
  final String link;
  final String rawDate;

  Deadline({
    required this.platform,
    required this.title,
    required this.course,
    required this.date,
    required this.link,
    required this.rawDate,
  });

  factory Deadline.fromJson(Map<String, dynamic> json) {
    return Deadline(
      platform: json['platform'] ?? 'Moodle',
      // Support both old field names and new API field names
      title: json['title'] ?? json['activity_name'] ?? '',
      course: json['course'] ?? json['course_name'] ?? '',
      date: json['date'] ?? json['due_date'] ?? '',
      link: json['link'] ?? json['url'] ?? '',
      rawDate: json['raw_date'] ?? '',
    );
  }
}

class Exam {
  final String name;
  final double ects;
  final String type;
  final bool required;
  final bool passed; // Whether the student has passed this exam

  Exam({
    required this.name,
    required this.ects,
    required this.type,
    required this.required,
    this.passed = false,
  });

  factory Exam.fromJson(Map<String, dynamic> json) {
    return Exam(
      name: json['name'] ?? '',
      ects: (json['ects'] ?? 0).toDouble(),
      type: json['type'] ?? '',
      required: json['required'] ?? true,
      passed: json['passed'] ?? false,
    );
  }
}

class ExamCategory {
  final String category;
  final List<Exam> exams;

  ExamCategory({
    required this.category,
    required this.exams,
  });

  factory ExamCategory.fromJson(Map<String, dynamic> json) {
    var examsList = json['exams'] as List;
    List<Exam> exams = examsList.map((i) => Exam.fromJson(i)).toList();

    return ExamCategory(
      category: json['category'] ?? '',
      exams: exams,
    );
  }
}

class DetailedGrade {
  final String name;
  final String grade;
  final String ects;
  final bool passed;

  DetailedGrade({
    required this.name,
    required this.grade,
    required this.ects,
    required this.passed,
  });

  factory DetailedGrade.fromJson(Map<String, dynamic> json) {
    // Handle both 'name' and 'title' field names from backend
    final name = json['name'] ?? json['title'] ?? '';
    
    // Handle grade which can be string or other types
    final gradeValue = json['grade'];
    final grade = gradeValue?.toString() ?? '-';
    
    // Handle ects/credits which can be int, double, or string
    final ectsValue = json['ects'] ?? json['credits'] ?? 0;
    final ects = ectsValue.toString();
    
    // Handle passed status
    // Default to true if not specified to avoid false negatives in older sessions,
    // or if we can infer it from grade/status
    bool isPassed = json['passed'] ?? false;
    
    // Fallback inference if 'passed' field is missing (e.g. older JSON)
    if (!json.containsKey('passed')) {
       // Try to infer from grade if possible, otherwise safe default?
       // Actually 'passed' should come from backend. If missing, false is safer, 
       // but might annoy users if they see failed exams.
       // Let's stick to what backend sends.
       isPassed = false;
    }

    return DetailedGrade(
      name: name,
      grade: grade,
      ects: ects,
      passed: isPassed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'grade': grade,
      'ects': ects,
      'passed': passed,
    };
  }
}

class SessionData {
  final String profileName;
  final String username; // Added for stable identification
  final ECTSData ectsData;
  final List<Deadline> moodleDeadlines;
  final List<ExamCategory> examRequirements;
  final List<String> currentClasses;
  final List<DetailedGrade> detailedGrades;
  final String? userId; // The UUID (hashed or Supabase)

  SessionData({
    required this.profileName,
    required this.username,
    required this.ectsData,
    required this.moodleDeadlines,
    required this.examRequirements,
    required this.currentClasses,
    this.detailedGrades = const [],
    this.userId,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) {
    var deadlinesList = json['moodle_deadlines'] as List;
    List<Deadline> deadlines = deadlinesList.map((i) => Deadline.fromJson(i)).toList();

    var examRequirementsList = json['exam_requirements'] as List? ?? [];
    List<ExamCategory> examRequirements = examRequirementsList.map((i) => ExamCategory.fromJson(i)).toList();

    var classesList = json['current_classes'] as List? ?? [];
    List<String> currentClasses = classesList.map((i) {
      if (i is Map && i.containsKey('name')) return i['name'].toString();
      return i.toString();
    }).toList();

    var detailedGradesList = json['detailed_grades'] as List? ?? [];
    List<DetailedGrade> detailedGrades = detailedGradesList.map((i) => DetailedGrade.fromJson(i)).toList();

    return SessionData(
      profileName: json['profile_name'] ?? 'Student',
      username: json['username'] ?? '',
      ectsData: ECTSData.fromJson(json['ects_data'] ?? {}),
      moodleDeadlines: deadlines,
      examRequirements: examRequirements,
      currentClasses: currentClasses,
      detailedGrades: detailedGrades,
      userId: json['user_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile_name': profileName,
      'username': username,
      'ects_data': {
        'total_ects': ectsData.totalEcts,
        'courses_count': ectsData.coursesCount,
        'degree_program': ectsData.degreeProgram,
        'average_grade': ectsData.averageGrade,
        'best_grade': ectsData.bestGrade,
      },
      'moodle_deadlines': moodleDeadlines.map((d) => {
        'platform': d.platform,
        'title': d.title,
        'course': d.course,
        'date': d.date,
        'link': d.link,
        'raw_date': d.rawDate,
      }).toList(),
      'exam_requirements': examRequirements.map((e) => {
        'category': e.category,
        'exams': e.exams.map((exam) => {
          'name': exam.name,
          'ects': exam.ects,
          'type': exam.type,
          'required': exam.required,
          'passed': exam.passed,
        }).toList(),
      }).toList(),
      'current_classes': currentClasses,
      'detailed_grades': detailedGrades.map((g) => g.toJson()).toList(),
      'user_id': userId,
    };
  }
}
// Unified event class for calendar display
class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final DateTime? endDate;
  final String? course;
  final String? link;
  final bool isCustom;
  final bool isAllDay;
  final String color;
  final String platform; // 'Moodle', 'Ayla', or 'Google'

  CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    this.endDate,
    this.course,
    this.link,
    required this.isCustom,
    this.isAllDay = false,
    this.color = '#4a5568',
    this.platform = 'Moodle',
  });

  factory CalendarEvent.fromDeadline(Deadline deadline) {
    final isAyla = deadline.platform == 'Ayla';
    return CalendarEvent(
      id: deadline.link.isNotEmpty ? deadline.link : DateTime.now().millisecondsSinceEpoch.toString(),
      title: deadline.title,
      description: deadline.course,
      date: DateTime.parse(deadline.date),
      course: deadline.course,
      link: deadline.link,
      isCustom: isAyla,
      color: isAyla ? '#E74C3C' : '#4a5568', // Red for exams, gray for Moodle
      platform: deadline.platform,
    );
  }

  factory CalendarEvent.fromCustomEvent(CustomEvent customEvent) {
    return CalendarEvent(
      id: customEvent.id,
      title: customEvent.title,
      description: customEvent.description,
      date: customEvent.date,
      course: customEvent.location,
      isCustom: true,
      color: customEvent.color,
    );
  }

  /// Factory constructor for Google Calendar events
  factory CalendarEvent.fromGoogleCalendar({
    required String id,
    required String title,
    String? description,
    required DateTime startTime,
    DateTime? endTime,
    bool isAllDay = false,
    String? location,
    String colorHex = '#4285F4',
  }) {
    return CalendarEvent(
      id: 'google_$id',
      title: title,
      description: description ?? '',
      date: startTime,
      endDate: endTime,
      course: location,
      isCustom: false,
      isAllDay: isAllDay,
      color: colorHex,
      platform: 'Google',
    );
  }
}

// Helper function to filter out submission actions (not actual deadlines)
List<Deadline> filterRealDeadlines(List<Deadline> deadlines) {
  final filterOutTitles = [
    'aufgabenlösung hinzufügen',
    'lösung hinzufügen',
    'abgabe hinzufügen',
    'add submission',
    'edit submission',
    'einreichung',
    'aufgabe lösen',
    'lösung',
    'hinzufügen',
    'endet',      
    'beginnt',    
  ];
  
  final filterOutUrls = [
    'action=editsubmission',
    'action=submit',
    'action=add',
  ];
  
  return deadlines.where((deadline) {
    final titleLower = deadline.title.toLowerCase();
    final linkLower = deadline.link.toLowerCase();
    
    if (filterOutTitles.any((filter) => titleLower.contains(filter))) {
      return false;
    }
    
    if (filterOutUrls.any((filter) => linkLower.contains(filter))) {
      return false;
    }
    
    return true;
  }).toList();
}

class CustomEvent {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String location;
  final String color;

  CustomEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.location,
    required this.color,
  });
}
