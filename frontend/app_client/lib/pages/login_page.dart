import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../utils/design_tokens.dart';
import '../main.dart'; // To access MainScreen

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isCheckingCache = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkCachedSession();
  }

  Future<void> _checkCachedSession() async {
    final credentials = await SessionService.loadCredentials();
    if (credentials != null && mounted) {
      setState(() {
        _usernameController.text = credentials['username']!;
        _passwordController.text = credentials['password']!;
      });
    }
    
    if (mounted) {
      setState(() {
        _isCheckingCache = false;
      });
    }
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = "Please enter both username and password.";
        _isLoading = false;
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = await ApiService.login(username, password);

      if (mounted && session != null) {
        await SessionService.clearSession();
        await SessionService.saveSession(session);
        await SessionService.saveCredentials(
          _usernameController.text,
          _passwordController.text,
        );
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainScreen(session: session)),
          );
        }
      }
    } catch (e) {
      String errorText = "Login failed. Please check your credentials.";
      final errorString = e.toString();
      
      // Extract the actual error message
      if (errorString.contains("Exception: ")) {
        errorText = errorString.replaceAll("Exception: ", "").trim();
      } else if (errorString.isNotEmpty && errorString != "Exception") {
        errorText = errorString.trim();
      }
      
      // Clean up "Message:" prefix if present
      if (errorText.startsWith("Message:")) {
        errorText = errorText.substring(8).trim();
      }
      
      // Map network errors to friendly messages, but keep credential errors as-is
      final lowerError = errorText.toLowerCase();
      if (lowerError.contains("connect") ||
          lowerError.contains("network") ||
          lowerError.contains("socketexception") ||
          lowerError.contains("unable to connect")) {
        errorText = "Unable to connect to server. Please check your internet connection and ensure the backend is running.";
      } else if (lowerError.contains("500") ||
                 lowerError.contains("server error")) {
        errorText = "Server error occurred. Please try again later.";
      }
      // Note: "Wrong username or password" messages are preserved as-is
      
      if (mounted) {
        setState(() {
          _errorMessage = errorText;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_isCheckingCache) {
      return Scaffold(
        backgroundColor: DesignTokens.background(isDark),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minimal loading indicator
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: DesignTokens.braunOrange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: DesignTokens.braunOrange,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DesignTokens.background(isDark),
      body: Row(
        children: [
          // Left side - Branding Panel
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: isDark 
                    ? DesignTokens.darkSurface 
                    : DesignTokens.warmGrey,
              ),
              child: Stack(
                children: [
                  // Subtle gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            DesignTokens.braunOrange.withValues(alpha: isDark ? 0.08 : 0.05),
                            Colors.transparent,
                            DesignTokens.sageGreen.withValues(alpha: isDark ? 0.05 : 0.03),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo mark
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: DesignTokens.braunOrange,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: DesignTokens.braunOrange.withValues(alpha: 0.3),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        // App name
                        Text(
                          "Ayla",
                          style: GoogleFonts.inter(
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                            color: DesignTokens.textPrimary(isDark),
                            letterSpacing: -2,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Tagline
                        Text(
                          "Your focused academic companion.\nPowered by AI, designed for clarity.",
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                            color: DesignTokens.textSec(isDark),
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 48),
                        // Feature highlights
                        _buildFeatureItem(
                          Icons.calendar_today_rounded,
                          "Track deadlines & schedules",
                          isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildFeatureItem(
                          Icons.auto_graph_rounded,
                          "Monitor ECTS & grades",
                          isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildFeatureItem(
                          Icons.chat_bubble_outline_rounded,
                          "AI-powered study assistant",
                          isDark,
                        ),
                      ],
                    ),
                  ),
                  // Footer
                  Positioned(
                    left: 64,
                    bottom: 48,
                    child: Text(
                      "SYNCS WITH BOSS & MOODLE",
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: DesignTokens.textTert(isDark),
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Right side - Login Form
          Expanded(
            flex: 4,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(64),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Header
                      Text(
                        "SIGN IN",
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: DesignTokens.textTert(isDark),
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Welcome back",
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: DesignTokens.textPrimary(isDark),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Enter your university credentials to continue.",
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: DesignTokens.textSec(isDark),
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      // Username field
                      _buildInputField(
                        controller: _usernameController,
                        label: "USERNAME",
                        hint: "Your university ID",
                        icon: Icons.person_outline_rounded,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 20),
                      
                      // Password field
                      _buildInputField(
                        controller: _passwordController,
                        label: "PASSWORD",
                        hint: "Service password",
                        icon: Icons.lock_outline_rounded,
                        isDark: isDark,
                        isPassword: true,
                      ),
                      const SizedBox(height: 32),
                      
                      // Error message
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: DesignTokens.softRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: DesignTokens.softRed.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: DesignTokens.softRed,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.inter(
                                    color: DesignTokens.softRed,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      
                      // Login button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isLoading ? null : _handleLogin,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: DesignTokens.braunOrange,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: DesignTokens.braunOrange.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isLoading
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white.withValues(alpha: 0.9),
                                      ),
                                    )
                                  : Text(
                                      "Continue",
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Loading status
                      if (_isLoading) ...[
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SpinKitThreeBounce(
                              color: DesignTokens.braunOrange,
                              size: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Syncing with university systems...\nThis may take up to 30 seconds.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: DesignTokens.textTert(isDark),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text, bool isDark) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: DesignTokens.surface(isDark),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DesignTokens.border(isDark)),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: DesignTokens.braunOrange,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: DesignTokens.textSec(isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: DesignTokens.textTert(isDark),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: DesignTokens.surface(isDark),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DesignTokens.border(isDark)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            style: GoogleFonts.inter(
              color: DesignTokens.textPrimary(isDark),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: Icon(
                  icon,
                  color: DesignTokens.textTert(isDark),
                  size: 20,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 18),
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                color: DesignTokens.textTert(isDark),
                fontWeight: FontWeight.w400,
              ),
            ),
            onSubmitted: (_) => _handleLogin(),
          ),
        ),
      ],
    );
  }
}
