import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/models.dart';
import 'services/session_service.dart';
import 'services/google_calendar_service.dart';
import 'widgets/glass_container.dart';
import 'utils/design_tokens.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/workspace_page.dart';

import 'widgets/ayla_chat.dart';
import 'widgets/sidebar_menu_item.dart';
import 'widgets/configure_panels_dialog.dart';
import 'services/panel_config_service.dart';

late final SharedPreferences prefs;
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  
  // Load saved theme
  final savedTheme = prefs.getString('theme_mode');
  if (savedTheme == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else {
    themeNotifier.value = ThemeMode.dark;
  }

  await GoogleCalendarService().initialize();
  runApp(const Ayla());
}

class Ayla extends StatelessWidget {
  const Ayla({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Ayla',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          // Neo-Analog Light Theme (Warm Vanilla / Dieter Rams inspired)
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F5F0), // Soft Vanilla
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A1A1A), // Braun Black
              secondary: Color(0xFF5A5A55),
              tertiary: Color(0xFFED8008), // Braun Orange
              surface: Color(0xFFFAFAF7),
              onSurface: Color(0xFF1A1A1A),
            ),
            textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
              bodyColor: const Color(0xFF1A1A1A),
              displayColor: const Color(0xFF1A1A1A),
            ),
            iconTheme: const IconThemeData(color: Color(0xFF5A5A55)),
          ),
          // Neo-Analog Dark Theme (Warm Charcoal)
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF1C1C1A), // Warm Charcoal
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFF0F0EC),
              secondary: Color(0xFFA0A098),
              tertiary: Color(0xFFED8008), // Braun Orange
              surface: Color(0xFF2A2A28),
              onSurface: Color(0xFFF0F0EC),
            ),
            textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
              bodyColor: const Color(0xFFF0F0EC),
              displayColor: const Color(0xFFF0F0EC),
            ),
            iconTheme: const IconThemeData(color: Color(0xFFA0A098)),
          ),
          home: const LoginPage(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final SessionData session;
  const MainScreen({super.key, required this.session});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isSidebarOpen = false;
  bool _isChatOpen = false;
  int _dashboardKey = 0;
  Map<String, dynamic>? _selectedWorkspace;
  List<PanelConfig> _panelConfig = [];
  bool _isGoogleCalendarConnected = false;
  final GoogleCalendarService _googleCalendarService = GoogleCalendarService();

  @override
  void initState() {
    super.initState();
    _loadPanelConfig();
    _initializeGoogleCalendar();
  }
  
  @override
  void dispose() {
    _googleCalendarService.isConnectedNotifier.removeListener(_onGoogleCalendarChanged);
    super.dispose();
  }
  
  Future<void> _initializeGoogleCalendar() async {
    // Listen for connection changes BEFORE initializing
    // This ensures we catch any status updates during initialization
    _googleCalendarService.isConnectedNotifier.addListener(_onGoogleCalendarChanged);
    
    // Set user ID and initialize
    // Use userId if available, otherwise fall back to username-based ID
    final userId = widget.session.userId ?? 
        widget.session.profileName.toLowerCase().replaceAll(' ', '_');
    
    debugPrint('Initializing Google Calendar with userId: $userId');
    
    _googleCalendarService.setUserId(userId);
    await _googleCalendarService.initialize(userId: userId);
    
    // Check for OAuth redirect (google_connected=true in URL)
    _handleOAuthRedirect();
    
    // Update local state to match the service state
    debugPrint('Google Calendar connected: ${_googleCalendarService.isConnected}');
    _isGoogleCalendarConnected = _googleCalendarService.isConnected;
    if (mounted) setState(() {});
  }
  
  void _handleOAuthRedirect() {
    // On web, check URL for google_connected parameter
    final uri = Uri.base;
    if (uri.queryParameters['google_connected'] == 'true') {
      debugPrint('OAuth redirect detected - refreshing status');
      _googleCalendarService.handleOAuthRedirect();
      
      // Remove the query parameter from URL to clean it up
      // (Optional: Could use html.window.history.replaceState on web)
    }
  }
  
  void _onGoogleCalendarChanged() {
    if (mounted) {
      setState(() {
        _isGoogleCalendarConnected = _googleCalendarService.isConnected;
      });
    }
  }

  Future<void> _loadPanelConfig() async {
    final config = await PanelConfigService.loadPanelConfig();
    if (mounted) {
      setState(() => _panelConfig = config);
    }
  }

  void _refreshDashboard() {
    setState(() => _dashboardKey++);
  }

  void _openConfigurePanels() {
    showDialog(
      context: context,
      builder: (context) => ConfigurePanelsDialog(
        panels: _panelConfig,
        onSave: (updatedPanels) async {
          await PanelConfigService.savePanelConfig(updatedPanels);
          setState(() {
            _panelConfig = updatedPanels;
            _dashboardKey++; // Refresh dashboard
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget currentPage;
    switch (_selectedIndex) {
      case 0:
        currentPage = DashboardPage(
          key: ValueKey(_dashboardKey), 
          session: widget.session, 
          onNavigate: (index) => setState(() => _selectedIndex = index),
          onWorkspaceSelected: (workspace) {
            setState(() {
              _selectedWorkspace = workspace;
              _selectedIndex = 1;
            });
          },
          panelConfig: _panelConfig,
        );
        break;
      case 1:
        currentPage = WorkspacePage(
          session: widget.session, 
          onNavigate: (index) => setState(() => _selectedIndex = index),
          initialWorkspace: _selectedWorkspace,
        );
        break;
      default:
        currentPage = DashboardPage(
          key: ValueKey(_dashboardKey), 
          session: widget.session, 
          onNavigate: (index) => setState(() => _selectedIndex = index),
          onWorkspaceSelected: (workspace) {
            setState(() {
              _selectedWorkspace = workspace;
              _selectedIndex = 1;
            });
          },
          panelConfig: _panelConfig,
        );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          currentPage,
          if (_isSidebarOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isSidebarOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            left: _isSidebarOpen ? 0 : -260,
            top: 0,
            bottom: 0,
            child: GlassContainer(
              width: 260,
              borderRadius: 0,
              opacity: isDark ? 0.08 : 0.4,
              blur: 20,
              border: Border(right: BorderSide(color: DesignTokens.border(isDark))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 60, 20, 40),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: DesignTokens.braunOrange,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: DesignTokens.braunOrange.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          "Ayla", 
                          style: GoogleFonts.inter(
                            fontSize: 24, 
                            fontWeight: FontWeight.w800, 
                            color: DesignTokens.textPrimary(isDark),
                            letterSpacing: -0.5,
                          )
                        ),
                      ],
                    ),
                  ),
                  SidebarMenuItem(
                    icon: Icons.grid_view_rounded, 
                    label: "Overview", 
                    isSelected: _selectedIndex == 0, 
                    onTap: () => setState(() { _selectedIndex = 0; _isSidebarOpen = false; })
                  ),
                  const SizedBox(height: 4),
                  SidebarMenuItem(
                    icon: Icons.layers_rounded, 
                    label: "Workspace", 
                    isSelected: _selectedIndex == 1, 
                    onTap: () => setState(() { 
                      _selectedIndex = 1; 
                      _isSidebarOpen = false; 
                      _selectedWorkspace = null; // Reset when clicking sidebar manually
                    })
                  ),
                  const SizedBox(height: 16),
                  // Separator Line
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(height: 1, thickness: 1, color: DesignTokens.border(isDark)),
                  ),
                  const SizedBox(height: 16),
                  // Theme Toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InkWell(
                      onTap: () async {
                        final newMode = themeNotifier.value == ThemeMode.dark 
                            ? ThemeMode.light 
                            : ThemeMode.dark;
                        themeNotifier.value = newMode;
                        await prefs.setString('theme_mode', newMode == ThemeMode.light ? 'light' : 'dark');
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: DesignTokens.surface(isDark),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: DesignTokens.border(isDark)),
                        ),
                        child: Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, animation) {
                                return RotationTransition(
                                  turns: Tween(begin: 0.5, end: 1.0).animate(animation),
                                  child: ScaleTransition(scale: animation, child: child),
                                );
                              },
                              child: Icon(
                                isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                                key: ValueKey(isDark),
                                color: isDark 
                                    ? DesignTokens.signalYellow 
                                    : DesignTokens.mutedBlue, 
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              isDark ? 'Light Mode' : 'Dark Mode',
                              style: GoogleFonts.inter(
                                color: DesignTokens.textSec(isDark),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Configure Panels Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InkWell(
                      onTap: _openConfigurePanels,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: DesignTokens.surface(isDark),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: DesignTokens.border(isDark)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.dashboard_customize_rounded,
                              color: DesignTokens.textSec(isDark),
                              size: 20,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              'Configure Panels',
                              style: GoogleFonts.inter(
                                color: DesignTokens.textSec(isDark),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Google Calendar Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: DesignTokens.surface(isDark),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: DesignTokens.border(isDark)),
                      ),
                      child: Row(
                        children: [
                          // Google Calendar Icon from asset
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset(
                              'assets/images/google_calendar_icon.png',
                              width: 24,
                              height: 24,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Google Calendar',
                              style: GoogleFonts.inter(
                                color: DesignTokens.textSec(isDark),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          // Toggle Switch
                          Transform.scale(
                            scale: 0.8,
                            child: Switch(
                              value: _isGoogleCalendarConnected,
                              onChanged: (value) async {
                                final success = await _googleCalendarService.toggleConnection();
                                if (success) {
                                  setState(() {
                                    _isGoogleCalendarConnected = _googleCalendarService.isConnected;
                                  });
                                }
                              },
                              activeColor: Colors.white,
                              activeTrackColor: const Color(0xFF4285F4),
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: DesignTokens.textTert(isDark).withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _SidebarActionButton(
                          label: "Reset Data",
                          icon: Icons.refresh_rounded,
                          onTap: () async { 
                            await SessionService.clearSession(); 
                            if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage())); 
                          },
                        ),
                        const SizedBox(height: 8),
                        _SidebarActionButton(
                          label: "Sign Out",
                          icon: Icons.logout_rounded,
                          onTap: () async { 
                            await SessionService.clearCredentials(); 
                            if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage())); 
                          },
                          isDestructive: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isSidebarOpen)
            Positioned(
              top: 24,
              left: 24,
              child: Tooltip(
                message: 'Menu',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _isSidebarOpen = true),
                    borderRadius: BorderRadius.circular(12),
                    child: GlassContainer(
                      padding: const EdgeInsets.all(10),
                      borderRadius: 12,
                      opacity: isDark ? 0.05 : 0.1,
                      child: Icon(
                        Icons.menu_open_rounded, 
                        color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black.withValues(alpha: 0.7), 
                        size: 22
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_isChatOpen)
            Positioned(
              right: 24,
              bottom: 24,
              child: AylaFloatingChat(session: widget.session, onClose: () => setState(() => _isChatOpen = false), onEventAdded: _refreshDashboard),
            ),
        ],
      ),
      floatingActionButton: _isChatOpen ? null : AylaChatButton(
        onPressed: () => setState(() => _isChatOpen = true),
      ),
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SidebarActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isDestructive 
              ? DesignTokens.softRed.withValues(alpha: 0.08) 
              : DesignTokens.surface(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDestructive 
                ? DesignTokens.softRed.withValues(alpha: 0.15) 
                : DesignTokens.border(isDark)
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isDestructive ? DesignTokens.softRed : DesignTokens.textTert(isDark)),
            const SizedBox(width: 12),
            Text(
              label, 
              style: GoogleFonts.inter(
                fontSize: 13, 
                fontWeight: FontWeight.w500, 
                color: isDestructive ? DesignTokens.softRed : DesignTokens.textSec(isDark)
              )
            ),
          ],
        ),
      ),
    );
  }
}
