import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../models/models.dart';
import '../services/ayla_service.dart';
import '../services/google_calendar_service.dart';
import '../widgets/glass_container.dart';
import '../widgets/email/email_list_widget.dart';
import '../services/workspace_service.dart';
import '../utils/design_tokens.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../services/panel_config_service.dart';

class DashboardPage extends StatefulWidget {
  final SessionData session;
  final Function(int)? onNavigate;
  final Function(Map<String, dynamic>)? onWorkspaceSelected;
  final List<PanelConfig> panelConfig;

  const DashboardPage({super.key, required this.session, this.onNavigate, this.onWorkspaceSelected, this.panelConfig = const []});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ScrollController _scrollController = ScrollController();
  DateTime? _selectedCalendarDate;
  List<CalendarEvent>? _selectedDateEvents;
  List<Deadline> _savedEvents = [];
  bool _isRefreshing = false;
  late SessionData _session;
  String? _username;
  String? _password;
  List<Map<String, dynamic>> _workspaces = [];
  
  // Google Calendar integration
  final GoogleCalendarService _googleCalendarService = GoogleCalendarService();
  List<GoogleCalendarEvent> _googleCalendarEvents = [];

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _loadCredentials();
    _fetchSavedEvents();
    _initGoogleCalendar();
  }

  void _initGoogleCalendar() {
    // Listen for changes to Google Calendar connection status
    _googleCalendarService.isConnectedNotifier.addListener(_onGoogleCalendarConnectionChanged);
    // Listen for changes to Google Calendar events
    _googleCalendarService.eventsNotifier.addListener(_onGoogleCalendarEventsChanged);
    // Load initial events if connected
    if (_googleCalendarService.isConnected) {
      _googleCalendarEvents = _googleCalendarService.events;
      _googleCalendarService.refreshEvents();
    }
  }
  
  void _onGoogleCalendarConnectionChanged() {
    if (mounted) {
      // When connection status changes (e.g., user connects their calendar),
      // refresh the events if now connected
      if (_googleCalendarService.isConnected) {
        _googleCalendarService.refreshEvents();
      }
      setState(() {
        _googleCalendarEvents = _googleCalendarService.events;
      });
    }
  }

  void _onGoogleCalendarEventsChanged() {
    if (mounted) {
      setState(() {
        _googleCalendarEvents = _googleCalendarService.events;
      });
    }
  }

  Future<void> _loadCredentials() async {
    final creds = await SessionService.loadCredentials();
    if (creds != null && mounted) {
      setState(() {
        _username = creds['username'];
        _password = creds['password'];
      });
      // Fetch workspaces once we have the username
      final workspaces = await WorkspaceService.getWorkspaces(_username!.toLowerCase().replaceAll(' ', '_'));
      if (mounted) {
        setState(() {
          _workspaces = workspaces;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    
    try {
      final credentials = await SessionService.loadCredentials();
      if (credentials != null) {
        final newSession = await ApiService.login(
          credentials['username']!,
          credentials['password']!,
          forceRefresh: true,
        );
        
        if (newSession != null && mounted) {
          await SessionService.saveSession(newSession);
          // Fetch fresh workspaces
          final workspaces = await WorkspaceService.getWorkspaces(credentials['username']!.toLowerCase().replaceAll(' ', '_'));
          
          setState(() {
            _session = newSession;
            _workspaces = workspaces;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dashboard updated successfully!'), backgroundColor: Colors.green),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _fetchSavedEvents() async {
    final studentId = _session.profileName.toLowerCase().replaceAll(' ', '_');
    try {
      final events = await AylaService.getEvents(studentId);
      if (events.isNotEmpty && mounted) {
        setState(() {
          _savedEvents = events.map((e) => Deadline(
            platform: 'Ayla',
            title: e['title'] ?? 'Event',
            course: e['course'] ?? '',
            date: e['event_date'] ?? '',
            link: e['id']?.toString() ?? '',
            rawDate: '',
          )).toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching saved events: $e");
    }
  }

  bool _isGeneratingPlan = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _googleCalendarService.isConnectedNotifier.removeListener(_onGoogleCalendarConnectionChanged);
    _googleCalendarService.eventsNotifier.removeListener(_onGoogleCalendarEventsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final realDeadlines = filterRealDeadlines(session.moodleDeadlines);
    final allDeadlines = [...realDeadlines, ..._savedEvents];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Simplified Header
          Container(
            padding: const EdgeInsets.only(left: 88, top: 32, right: 32, bottom: 24),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Overview",
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: DesignTokens.textPrimary(isDark),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Welcome back",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: DesignTokens.textSec(isDark),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (_isRefreshing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                  )
                else
                  IconButton(
                    tooltip: "Refresh Data",
                    icon: Icon(Icons.refresh_rounded, color: DesignTokens.textTert(isDark), size: 20),
                    onPressed: _refreshData,
                  ),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Content Column (Left)
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: _buildLeftColumnPanels(session, realDeadlines, isDark),
                    ),
                  ),
                  const SizedBox(width: 24),
                  
                  // Sidebar Content Column (Right)
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: _buildRightColumnPanels(session, allDeadlines, isDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isPanelVisible(String panelId) {
    if (widget.panelConfig.isEmpty) return true; // Show all if no config
    final panel = widget.panelConfig.where((p) => p.id == panelId).firstOrNull;
    return panel?.isVisible ?? true;
  }

  List<PanelConfig> _getLeftPanels() {
    if (widget.panelConfig.isEmpty) {
      return PanelConfigService.getDefaultPanels().where((p) => p.column == 'left').toList();
    }
    return widget.panelConfig.where((p) => p.column == 'left' && p.isVisible).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<PanelConfig> _getRightPanels() {
    if (widget.panelConfig.isEmpty) {
      return PanelConfigService.getDefaultPanels().where((p) => p.column == 'right').toList();
    }
    return widget.panelConfig.where((p) => p.column == 'right' && p.isVisible).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<Widget> _buildLeftColumnPanels(SessionData session, List<Deadline> realDeadlines, bool isDark) {
    final panels = _getLeftPanels();
    final List<Widget> widgets = [];
    
    for (int i = 0; i < panels.length; i++) {
      final panel = panels[i];
      final panelWidget = _buildPanelById(panel.id, session, realDeadlines, [], isDark);
      if (panelWidget != null) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 24));
        }
        widgets.add(panelWidget);
      }
    }
    
    return widgets;
  }

  List<Widget> _buildRightColumnPanels(SessionData session, List<Deadline> allDeadlines, bool isDark) {
    final panels = _getRightPanels();
    final List<Widget> widgets = [];
    
    for (int i = 0; i < panels.length; i++) {
      final panel = panels[i];
      final panelWidget = _buildPanelById(panel.id, session, [], allDeadlines, isDark);
      if (panelWidget != null) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 24));
        }
        widgets.add(panelWidget);
      }
    }
    
    return widgets;
  }

  Widget? _buildPanelById(String panelId, SessionData session, List<Deadline> realDeadlines, List<Deadline> allDeadlines, bool isDark) {
    switch (panelId) {
      case 'stats':
        return _buildStatsRow(session, isDark);
      case 'study_planner':
        return _buildStudyPlannerCard(session, isDark);
      case 'deadlines':
        return _buildSectionCard(
          title: "Deadlines",
          icon: Icons.timer_outlined,
          color: DesignTokens.signalYellow,
          child: _UpcomingListCompact(
            deadlines: realDeadlines.isNotEmpty ? realDeadlines : filterRealDeadlines(session.moodleDeadlines),
            onTap: (d) => _showEventDetails(CalendarEvent.fromDeadline(d)),
          ),
          isDark: isDark,
        );
      case 'classes':
        return _buildSectionCard(
          title: "Classes",
          icon: Icons.auto_stories_rounded,
          color: DesignTokens.mutedBlue,
          child: _CurrentClassesListCompact(classes: session.currentClasses),
          isDark: isDark,
        );
      case 'emails':
        if (_username != null && _password != null) {
          return _buildSectionCard(
            title: "University Emails",
            icon: Icons.email_outlined,
            color: DesignTokens.mutedBlue,
            child: EmailListWidget(
              username: _username!,
              password: _password!,
              isDark: isDark,
            ),
            isDark: isDark,
          );
        }
        return null;
      case 'calendar':
        final deadlines = allDeadlines.isNotEmpty ? allDeadlines : [...filterRealDeadlines(session.moodleDeadlines), ..._savedEvents];
        return _buildSectionCard(
          title: "Calendar",
          icon: Icons.calendar_today_rounded,
          color: DesignTokens.braunOrange,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MonthlyCalendar(
                deadlines: deadlines,
                googleEvents: _googleCalendarEvents,
                onDateSelected: (date, events) {
                  setState(() {
                    _selectedCalendarDate = date;
                    _selectedDateEvents = events;
                  });
                },
              ),
              if (_selectedDateEvents != null && _selectedDateEvents!.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.white12),
                const SizedBox(height: 16),
                Text(
                  DateFormat('EEEE, d MMMM').format(_selectedCalendarDate!),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 12),
                ..._selectedDateEvents!.map((event) => _buildEventItem(event, isDark)),
              ],
            ],
          ),
          isDark: isDark,
        );
      case 'exams':
        return _buildSectionCard(
          title: "Exams",
          icon: Icons.verified_rounded,
          color: DesignTokens.sageGreen,
          child: SizedBox(
            height: 120,
            child: _PassedExamsList(examRequirements: session.examRequirements),
          ),
          isDark: isDark,
        );
      case 'workspaces':
        return _buildSectionCard(
          title: "Workspaces",
          icon: Icons.layers_rounded,
          color: DesignTokens.braunOrange,
          child: SizedBox(
            height: 207,
            child: _WorkspacesListCompact(
              workspaces: _workspaces,
              onTap: widget.onWorkspaceSelected,
            ),
          ),
          isDark: isDark,
        );
      default:
        return null;
    }
  }

  Widget _buildStatsRow(SessionData session, bool isDark) {
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ECTS Progress & General Stats
        Expanded(
          flex: 2,
          child: GlassContainer(
            padding: const EdgeInsets.all(24),
            borderRadius: 32,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCircularProgress(session.ectsData.totalEcts, 180, isDark),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildStatSimple("Average Grade", session.ectsData.averageGrade?.toStringAsFixed(2) ?? "–", Icons.auto_graph_rounded, DesignTokens.braunOrange, isDark),
                        const SizedBox(height: 20),
                        _buildStatSimple("Best Grade", session.ectsData.bestGrade?.toStringAsFixed(2) ?? "–", Icons.military_tech_rounded, DesignTokens.sageGreen, isDark),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudyPlannerCard(SessionData session, bool isDark) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      borderRadius: 24,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DesignTokens.braunOrange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded, color: DesignTokens.braunOrange, size: 24),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AI Study Planner",
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DesignTokens.textPrimary(isDark),
                  ),
                ),
                Text(
                  "Generate a tailored schedule based on your upcoming deadlines.",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: DesignTokens.textSec(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _isGeneratingPlan
              ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: DesignTokens.braunOrange))
              : ElevatedButton(
                  onPressed: _generateStudyPlan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DesignTokens.braunOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: Text("Generate Plan", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
        ],
      ),
    );
  }

  Future<void> _generateStudyPlan() async {
    setState(() => _isGeneratingPlan = true);
    
    try {
      final prompt = "Base on my upcoming deadlines, create a detailed study plan for the next 7 days. Break it down day-by-day and prioritize tasks based on their due dates. Keep it concise but actionable.";
      
      final response = await AylaService.askAyla(
        question: prompt,
        context: _session.toJson(),
        studentId: _session.profileName.toLowerCase().replaceAll(' ', '_'),
      );
      
      if (mounted) {
        _showAylaAnalysisBottomSheet(response.answer, "Weekly Study Plan");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error generating plan: $e")));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPlan = false);
    }
  }

  void _showAylaAnalysisBottomSheet(String content, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => GlassContainer(
          borderRadius: 32,
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(
                    content,
                    style: GoogleFonts.inter(fontSize: 14, height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildCircularProgress(double total, double target, bool isDark) {
    final double percent = (total / target).clamp(0.0, 1.0);
    return CircularPercentIndicator(
      radius: 50.0,
      lineWidth: 10.0,
      percent: percent,
      animation: true,
      animationDuration: 1200,
      circularStrokeCap: CircularStrokeCap.round,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "${total.toInt()}",
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: DesignTokens.textPrimary(isDark),
            ),
          ),
          Text(
            "ECTS",
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: DesignTokens.textTert(isDark),
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
      backgroundColor: DesignTokens.border(isDark),
      progressColor: DesignTokens.sageGreen,
    );
  }

  Widget _buildStatSimple(String label, String value, IconData icon, Color color, bool isDark) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Split-flap style value display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9,
                color: DesignTokens.textTert(isDark),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 16),
        ),
      ],
    );
  }


  Widget _buildSectionCard({required String title, required IconData icon, required Color color, required Widget child, required bool isDark}) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withValues(alpha: 0.7), size: 18),
              const SizedBox(width: 12),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DesignTokens.textTert(isDark),
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildEventItem(CalendarEvent event, bool isDark) {
    Color eventColor;
    if (event.platform == 'Google') {
      eventColor = const Color(0xFF4285F4); // Google Blue
    } else {
      eventColor = DesignTokens.braunOrange; // Default
    }
    
    return InkWell(
      onTap: () => _showEventDetails(event),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DesignTokens.surface(isDark).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DesignTokens.border(isDark)),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(color: eventColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: DesignTokens.textPrimary(isDark))),
                  const SizedBox(height: 2),
                  Text(
                    "${DateFormat('HH:mm').format(event.date)} ${event.course ?? ''}", 
                    style: GoogleFonts.inter(fontSize: 11, color: DesignTokens.textTert(isDark))
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: isDark ? Colors.white12 : Colors.black12),
          ],
        ),
      ),
    );
  }

  void _showEventDetails(CalendarEvent event) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Get appropriate icon and color based on platform
    IconData eventIcon;
    Color eventColor;
    
    switch (event.platform) {
      case 'Google':
        eventIcon = Icons.event_rounded;
        eventColor = const Color(0xFF4285F4); // Google Blue
        break;
      case 'Ayla':
        eventIcon = Icons.assignment_rounded;
        eventColor = DesignTokens.softRed;
        break;
      default: // Moodle
        eventIcon = Icons.calendar_today_rounded;
        eventColor = DesignTokens.braunOrange;
    }
    
    // Format date/time appropriately
    String dateTimeStr;
    if (event.isAllDay) {
      dateTimeStr = DateFormat('EEEE, d MMMM yyyy').format(event.date) + ' (All day)';
    } else {
      dateTimeStr = DateFormat('EEEE, d MMMM yyyy, HH:mm').format(event.date);
      if (event.endDate != null) {
        dateTimeStr += ' - ${DateFormat('HH:mm').format(event.endDate!)}';
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DesignTokens.surface(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: eventColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                eventIcon,
                color: eventColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                event.title,
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.course != null && event.course!.isNotEmpty) ...[
              _buildDetailRow(
                event.platform == 'Google' ? Icons.location_on_outlined : Icons.book_outlined, 
                event.platform == 'Google' ? "Location" : "Course", 
                event.course!, 
                isDark
              ),
              const SizedBox(height: 16),
            ],
            _buildDetailRow(
              Icons.access_time_rounded, 
              event.platform == 'Google' ? "Time" : "Due Date", 
              dateTimeStr, 
              isDark
            ),
            if (event.description.isNotEmpty && event.platform == 'Google') ...[
              const SizedBox(height: 16),
              _buildDetailRow(Icons.notes_rounded, "Description", event.description, isDark),
            ],
            const SizedBox(height: 16),
            _buildDetailRow(Icons.apps_rounded, "Source", event.platform, isDark),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close", style: GoogleFonts.inter(color: Colors.grey)),
          ),
          if (event.link != null && event.link!.isNotEmpty)
            ElevatedButton(
              onPressed: () async {
                final link = event.link!;
                Navigator.pop(context);
                if (await canLaunchUrlString(link)) {
                  await launchUrlString(link, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Could not open link: $link")),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: eventColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text("Open in ${event.platform}", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: DesignTokens.textTert(isDark)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: GoogleFonts.inter(fontSize: 9, color: DesignTokens.textTert(isDark), fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 2),
              Text(value, style: GoogleFonts.inter(fontSize: 14, color: DesignTokens.textPrimary(isDark), fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpcomingListCompact extends StatelessWidget {
  final List<Deadline> deadlines;
  final Function(Deadline)? onTap;
  const _UpcomingListCompact({required this.deadlines, this.onTap});

  @override
  Widget build(BuildContext context) {
    final sorted = deadlines.toList()..sort((a, b) {
      try { return DateTime.parse(a.date).compareTo(DateTime.parse(b.date)); } catch (e) { return 0; }
    });
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (sorted.isEmpty) {
      return Center(child: Text("All caught up!", style: GoogleFonts.inter(color: DesignTokens.textTert(isDark), fontSize: 13)));
    }
    final ScrollController controller = ScrollController();

    return SizedBox(
      height: 200, 
      child: Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbColor: WidgetStateProperty.all(isDark ? Colors.white24 : Colors.black12),
            radius: const Radius.circular(8),
            thickness: WidgetStateProperty.all(4),
          ),
        ),
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: ListView.builder(
            controller: controller,
            padding: const EdgeInsets.only(right: 8), 
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final deadline = sorted[index];
              try {
                final deadlineDate = DateTime.parse(deadline.date);
                final daysUntil = deadlineDate.difference(DateTime.now()).inDays;
                Color urgencyColor = daysUntil <= 1 ? DesignTokens.softRed : (daysUntil <= 3 ? DesignTokens.signalYellow : DesignTokens.sageGreen);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => onTap?.call(deadline),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: DesignTokens.surface(isDark).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: DesignTokens.border(isDark)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  deadline.title, 
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: DesignTokens.textPrimary(isDark)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  deadline.course, 
                                  style: GoogleFonts.inter(fontSize: 11, color: DesignTokens.textTert(isDark)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: urgencyColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              daysUntil == 0 ? "Today" : (daysUntil == 1 ? "Tomorrow" : "$daysUntil days"), 
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: urgencyColor)
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } catch (e) { return const SizedBox.shrink(); }
            },
          ),
        ),
      ),
    );
  }
}

class _MonthlyCalendar extends StatefulWidget {
  final List<Deadline> deadlines;
  final List<GoogleCalendarEvent> googleEvents;
  final Function(DateTime, List<CalendarEvent>)? onDateSelected;
  const _MonthlyCalendar({
    required this.deadlines, 
    this.googleEvents = const [],
    this.onDateSelected,
  });

  @override
  State<_MonthlyCalendar> createState() => _MonthlyCalendarState();
}

class _MonthlyCalendarState extends State<_MonthlyCalendar> {
  DateTime? _selectedDay;
  late DateTime _focusedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final events = <DateTime, List<CalendarEvent>>{};
    
    // Add deadlines
    for (var deadline in widget.deadlines) {
      try {
        final date = DateTime.parse(deadline.date);
        final dayOnly = DateTime(date.year, date.month, date.day);
        events.putIfAbsent(dayOnly, () => []).add(CalendarEvent.fromDeadline(deadline));
      } catch (e) {
        debugPrint("Error parsing data: $e");
      }
    }
    
    // Add Google Calendar events
    for (var googleEvent in widget.googleEvents) {
      try {
        final dayOnly = DateTime(googleEvent.startTime.year, googleEvent.startTime.month, googleEvent.startTime.day);
        events.putIfAbsent(dayOnly, () => []).add(CalendarEvent.fromGoogleCalendar(
          id: googleEvent.id,
          title: googleEvent.title,
          description: googleEvent.description,
          startTime: googleEvent.startTime,
          endTime: googleEvent.endTime,
          isAllDay: googleEvent.isAllDay,
          location: googleEvent.location,
          colorHex: googleEvent.colorHex,
        ));
      } catch (e) {
        debugPrint("Error adding Google event: $e");
      }
    }

    return TableCalendar<CalendarEvent>(
      firstDay: DateTime(2020, 1, 1),
      lastDay: DateTime(2030, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDate, focusedDay) {
        setState(() { _selectedDay = selectedDate; _focusedDay = focusedDay; });
        widget.onDateSelected?.call(selectedDate, events[DateTime(selectedDate.year, selectedDate.month, selectedDate.day)] ?? []);
      },
      onPageChanged: (focusedDay) => _focusedDay = focusedDay,
      eventLoader: (day) => events[DateTime(day.year, day.month, day.day)] ?? [],
        calendarBuilders: CalendarBuilders(
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: events.take(4).map((event) {
              Color dotColor;
              if (event.platform == 'Google') {
                dotColor = const Color(0xFF4285F4); // Google Blue
              } else if (event.platform == 'Ayla') {
                dotColor = DesignTokens.softRed;
              } else {
                dotColor = DesignTokens.braunOrange;
              }
              
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              );
            }).toList(),
          );
        },
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        weekendTextStyle: GoogleFonts.inter(color: DesignTokens.softRed.withValues(alpha: 0.7), fontSize: 13),
        defaultTextStyle: GoogleFonts.inter(fontSize: 13, color: DesignTokens.textSec(isDark)),
        todayDecoration: BoxDecoration(color: DesignTokens.border(isDark), shape: BoxShape.circle),
        todayTextStyle: GoogleFonts.inter(color: DesignTokens.textPrimary(isDark), fontWeight: FontWeight.bold),
        selectedDecoration: BoxDecoration(color: DesignTokens.braunOrange, shape: BoxShape.circle),
        selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        // markerDecoration: Removed to use custom builder
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: false, 
        titleCentered: true, 
        titleTextStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: DesignTokens.textPrimary(isDark)),
        leftChevronIcon: Icon(Icons.chevron_left_rounded, color: DesignTokens.textTert(isDark)),
        rightChevronIcon: Icon(Icons.chevron_right_rounded, color: DesignTokens.textTert(isDark)),
      ),
    );
  }
}

class _CurrentClassesListCompact extends StatelessWidget {
  final List<String> classes;
  const _CurrentClassesListCompact({required this.classes});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (classes.isEmpty) return Center(child: Text("No active classes", style: GoogleFonts.inter(color: DesignTokens.textTert(isDark), fontSize: 13)));
    
    final ScrollController controller = ScrollController();
    
    return SizedBox(
      height: 200, // Height for roughly 3.5 items
      child: Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbColor: WidgetStateProperty.all(isDark ? Colors.white24 : Colors.black12),
            radius: const Radius.circular(8),
            thickness: WidgetStateProperty.all(4),
          ),
        ),
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: ListView.builder(
            controller: controller,
            padding: const EdgeInsets.only(right: 8), // Room for scrollbar
            itemCount: classes.length,
            itemBuilder: (context, index) {
              final c = classes[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12), 
                padding: const EdgeInsets.all(16), 
                decoration: BoxDecoration(
                  color: DesignTokens.surface(isDark).withValues(alpha: 0.5), 
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: DesignTokens.border(isDark)),
                ), 
                child: Row(
                  children: [
                    Icon(Icons.bookmark_rounded, size: 16, color: DesignTokens.mutedBlue.withValues(alpha: 0.7)), 
                    const SizedBox(width: 16), 
                    Expanded(child: Text(c, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: DesignTokens.textPrimary(isDark))))
                  ]
                )
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PassedExamsList extends StatelessWidget {
  final List<ExamCategory> examRequirements;
  const _PassedExamsList({required this.examRequirements});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final passed = examRequirements.expand((c) => c.exams).where((e) => e.passed).toList();
    if (passed.isEmpty) return Center(child: Text("No results found", style: GoogleFonts.inter(color: DesignTokens.textTert(isDark), fontSize: 13)));
    final ScrollController controller = ScrollController();
    
    return Theme(
      data: Theme.of(context).copyWith(
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(isDark ? Colors.white24 : Colors.black12),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(4),
        ),
      ),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: ListView.builder(
          controller: controller,
          padding: const EdgeInsets.only(right: 8), // Room for scrollbar
          itemCount: passed.length,
          itemBuilder: (context, index) {
            final e = passed[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8), 
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
              decoration: BoxDecoration(
                color: DesignTokens.surface(isDark).withValues(alpha: 0.5), 
                borderRadius: BorderRadius.circular(12),
              ), 
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: DesignTokens.sageGreen), 
                  const SizedBox(width: 12), 
                  Expanded(
                    child: Text(
                      e.name, 
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: DesignTokens.textSec(isDark)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  )
                ]
              )
            );
          },
        ),
      ),
    );
  }
}

class _WorkspacesListCompact extends StatelessWidget {
  final List<Map<String, dynamic>> workspaces;
  final Function(Map<String, dynamic>)? onTap;
  const _WorkspacesListCompact({required this.workspaces, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (workspaces.isEmpty) {
      return Center(
        child: Text(
          "No workspaces yet", 
          style: GoogleFonts.inter(color: DesignTokens.textTert(isDark), fontSize: 13)
        )
      );
    }
    final ScrollController controller = ScrollController();
    
    return Theme(
      data: Theme.of(context).copyWith(
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(isDark ? Colors.white24 : Colors.black12),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(4),
        ),
      ),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: ListView.builder(
          controller: controller,
          padding: const EdgeInsets.only(right: 8), // Room for scrollbar
          itemCount: workspaces.length,
          itemBuilder: (context, index) {
            final w = workspaces[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8), 
              child: InkWell(
                onTap: () => onTap?.call(w),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
                  decoration: BoxDecoration(
                    color: DesignTokens.surface(isDark).withValues(alpha: 0.5), 
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DesignTokens.border(isDark)),
                  ), 
                  child: Row(
                    children: [
                      Icon(Icons.folder_rounded, size: 14, color: DesignTokens.braunOrange), 
                      const SizedBox(width: 12), 
                      Expanded(
                        child: Text(
                          w['name'] ?? 'Untitled', 
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: DesignTokens.textSec(isDark)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      )
                    ]
                  )
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
