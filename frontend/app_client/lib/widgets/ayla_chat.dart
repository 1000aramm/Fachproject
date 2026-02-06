import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/workspace_service.dart';
import '../services/audio_service.dart';
import '../utils/design_tokens.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

// Use conditional import for IoHelper
import '../utils/io_helper.dart' if (dart.library.html) '../utils/io_helper_web.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AylaChatButton extends StatefulWidget {
  final VoidCallback onPressed;

  const AylaChatButton({super.key, required this.onPressed});

  @override
  State<AylaChatButton> createState() => _AylaChatButtonState();
}

class _AylaChatButtonState extends State<AylaChatButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: DesignTokens.braunOrange,
            boxShadow: [
              BoxShadow(
                color: DesignTokens.braunOrange.withValues(alpha: 0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.auto_awesome_rounded, 
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class AylaFloatingChat extends StatefulWidget {
  final SessionData session;
  final VoidCallback onClose;
  final VoidCallback? onEventAdded;

  const AylaFloatingChat({super.key, required this.session, required this.onClose, this.onEventAdded});

  @override
  State<AylaFloatingChat> createState() => _AylaFloatingChatState();
}

class _AylaFloatingChatState extends State<AylaFloatingChat> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isMinimized = false;
  bool _isRecording = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _messages.add(ChatMessage(text: "Hi! I'm Ayla, your AI study companion 📚\nHow can I help you today?", isUser: false));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildStudentContext() {
    final grades = widget.session.ectsData;
    return {
      'student_name': widget.session.profileName,
      'degree_program': grades.degreeProgram ?? 'Unknown',
      'total_ects': grades.totalEcts,
      'courses_count': grades.coursesCount,
      'average_grade': grades.averageGrade,
      'best_grade': grades.bestGrade,
      'current_date': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;
    setState(() { _messages.add(ChatMessage(text: text, isUser: true)); _isLoading = true; });
    _messageController.clear();
    _scrollToBottom();
    try {
      final contextMap = _buildStudentContext();
      final userId = widget.session.userId ?? widget.session.username;
      final response = await WorkspaceService.sendAssistantChat(text, userId: userId, studentContext: {
        'name': widget.session.profileName,
        'ects': contextMap['total_ects'],
        'degree': contextMap['degree_program'],
        'moodle_deadlines': widget.session.moodleDeadlines.map((d) => {
          'title': d.title,
          'course': d.course,
          'date': d.date
        }).toList(),
      });
      if (mounted) {
        setState(() { _messages.add(ChatMessage(text: response ?? "No response received.", isUser: false)); _isLoading = false; });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _messages.add(ChatMessage(text: "Sorry, I couldn't process that. ${e.toString().replaceAll('Exception: ', '')}", isUser: false)); _isLoading = false; });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        final path = await AudioService.stopRecording();
        setState(() => _isRecording = false);
        if (path != null) {
          await _sendAudioMessage(path);
        }
      } else {
        await AudioService.startRecording();
        setState(() => _isRecording = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Recording error: $e")));
      }
      setState(() => _isRecording = false);
    }
  }

  Future<void> _sendAudioMessage(String path) async {
    setState(() {
      _messages.add(ChatMessage(text: "🎤 Voice Prompt", isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final List<int> bytes;
      if (kIsWeb) {
        // On web, path is a blob URL. We need to fetch the bytes.
        final response = await http.get(Uri.parse(path));
        bytes = response.bodyBytes;
      } else {
        bytes = await IoHelper.readAsBytes(path);
      }
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${WorkspaceService.baseUrl}/assistant/audio'),
      );
      
      final userId = widget.session.userId ?? widget.session.username;
      request.fields['user_id'] = userId;
      
      // Determine file extension and MIME type based on platform
      final String fileName = kIsWeb ? 'voice_prompt.ogg' : 'voice_prompt.m4a';
      final String mimeType = kIsWeb ? 'audio/ogg' : 'audio/mp4';
      
      request.files.add(http.MultipartFile.fromBytes(
        'audio_file',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _messages.add(ChatMessage(text: data['answer'] ?? "No response received.", isUser: false));
            _isLoading = false;
          });
          _scrollToBottom();
        }
      } else {
        throw Exception("Server returned ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(text: "Audio chat failed: ${e.toString()}", isUser: false));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final chatWidth = screenWidth > 600 ? 420.0 : screenWidth * 0.85;
    return ScaleTransition(
      scale: _scaleAnim,
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        elevation: 20,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _isMinimized ? 56 : chatWidth,
          height: _isMinimized ? 56 : 550,
          decoration: BoxDecoration(
            color: DesignTokens.surface(isDark), 
            borderRadius: BorderRadius.circular(24), 
            border: Border.all(color: DesignTokens.border(isDark), width: 1.5),
            boxShadow: DesignTokens.cardShadow(isDark),
          ),
          child: _isMinimized ? _buildMinimizedView() : _buildExpandedView(isDark),
        ),
      ),
    );
  }

  Widget _buildMinimizedView() {
    return InkWell(
      onTap: () => setState(() => _isMinimized = false),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: DesignTokens.braunOrange,
          borderRadius: BorderRadius.circular(24),
        ), 
        child: const Center(
          child: Icon(
            Icons.auto_awesome_rounded, 
            color: Colors.white, 
            size: 24
          )
        )
      ),
    );
  }

  Widget _buildExpandedView(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: DesignTokens.surface(isDark),
              border: Border(bottom: BorderSide(color: DesignTokens.border(isDark))),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8), 
                decoration: BoxDecoration(
                  color: DesignTokens.braunOrange, 
                  borderRadius: BorderRadius.circular(10)
                ), 
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18)
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Ayla", style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: DesignTokens.textPrimary(isDark))), Text("AI Study Companion", style: GoogleFonts.inter(fontSize: 10, color: DesignTokens.textTert(isDark)))])),
              IconButton(icon: Icon(Icons.remove_rounded, color: DesignTokens.textTert(isDark), size: 20), onPressed: () => setState(() => _isMinimized = true)),
              IconButton(icon: Icon(Icons.close_rounded, color: DesignTokens.textTert(isDark), size: 20), onPressed: widget.onClose),
            ]),
          ),
          Expanded(child: ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(12), itemCount: _messages.length + (_isLoading ? 1 : 0), itemBuilder: (context, index) { if (index == _messages.length && _isLoading) return _buildTypingIndicator(isDark); return _buildMessage(_messages[index], isDark); })),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: DesignTokens.surface(isDark), border: Border(top: BorderSide(color: DesignTokens.border(isDark)))),
            child: Row(children: [
              Expanded(child: TextField(controller: _messageController, style: GoogleFonts.inter(fontSize: 14, color: DesignTokens.textPrimary(isDark)), decoration: InputDecoration(hintText: _isRecording ? "Listening..." : "Ask anything...", hintStyle: TextStyle(color: DesignTokens.textTert(isDark), fontSize: 14), filled: true, fillColor: DesignTokens.background(isDark), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), isDense: true, suffixIcon: IconButton(icon: _isRecording ? const _PulseMicIcon() : Icon(Icons.mic_rounded, color: DesignTokens.braunOrange), onPressed: _toggleRecording)), onSubmitted: (_) => _sendMessage())),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: DesignTokens.braunOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(icon: const Icon(Icons.send_rounded, color: Colors.white), onPressed: _sendMessage),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage message, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (!message.isUser) ...[
            Container(
              width: 26, height: 26, 
              decoration: BoxDecoration(
                color: DesignTokens.braunOrange.withValues(alpha: 0.15), 
                borderRadius: BorderRadius.circular(8)
              ), 
              child: Icon(Icons.auto_awesome_rounded, color: DesignTokens.braunOrange, size: 14)
            ), 
            const SizedBox(width: 8)
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), 
              decoration: BoxDecoration(
                color: message.isUser 
                  ? DesignTokens.braunOrange 
                  : DesignTokens.surface(isDark), 
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: message.isUser ? const Radius.circular(4) : null, 
                  bottomLeft: !message.isUser ? const Radius.circular(4) : null
                ), 
                border: Border.all(color: message.isUser ? Colors.transparent : DesignTokens.border(isDark))
              ), 
              child: message.isUser 
                ? Text(message.text, style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: Colors.white)) 
                : MarkdownBody(
                    data: message.text, 
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.inter(fontSize: 13, height: 1.4, color: DesignTokens.textPrimary(isDark)), 
                      a: GoogleFonts.inter(color: DesignTokens.braunOrange, decoration: TextDecoration.underline), 
                      code: GoogleFonts.robotoMono(backgroundColor: DesignTokens.surface(isDark), fontSize: 12), 
                      codeblockDecoration: BoxDecoration(color: DesignTokens.background(isDark), borderRadius: BorderRadius.circular(8))
                    ), 
                    onTapLink: (text, href, title) { if (href != null) launchUrl(Uri.parse(href)); }
                  )
            )
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10), 
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Container(
            width: 26, height: 26, 
            decoration: BoxDecoration(
              color: DesignTokens.braunOrange.withValues(alpha: 0.15), 
              borderRadius: BorderRadius.circular(8)
            ), 
            child: Icon(Icons.psychology_rounded, color: DesignTokens.braunOrange, size: 14)
          ), 
          const SizedBox(width: 8), 
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), 
            decoration: BoxDecoration(
              color: DesignTokens.surface(isDark), 
              borderRadius: BorderRadius.circular(14).copyWith(bottomLeft: const Radius.circular(4))
            ), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              mainAxisSize: MainAxisSize.min, 
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _buildDot(i))), 
                const SizedBox(height: 6), 
                _AnimatedStatusText(isDark: isDark)
              ]
            )
          )
        ]
      )
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0), 
      duration: Duration(milliseconds: 400 + (index * 150)), 
      curve: Curves.easeInOut, 
      builder: (context, value, _) => Container(
        margin: EdgeInsets.only(right: index < 2 ? 4 : 0), 
        width: 6, height: 6, 
        decoration: BoxDecoration(color: DesignTokens.braunOrange.withValues(alpha: value), shape: BoxShape.circle)
      )
    );
  }
}

class _AnimatedStatusText extends StatefulWidget {
  final bool isDark;
  const _AnimatedStatusText({required this.isDark});
  @override
  State<_AnimatedStatusText> createState() => _AnimatedStatusTextState();
}

class _AnimatedStatusTextState extends State<_AnimatedStatusText> {
  int _currentIndex = 0;
  final List<String> _statusMessages = [
    "Thinking...", 
    "Analyzing your prompt...", 
    "Checking materials...", 
    "Synthesizing response...",
    "Listening to your voice...", 
    "Processing audio..."
  ];
  @override
  void initState() { super.initState(); _startCycling(); }
  void _startCycling() { Future.delayed(const Duration(seconds: 2), () { if (mounted) { setState(() { _currentIndex = (_currentIndex + 1) % _statusMessages.length; }); _startCycling(); } }); }
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: Text(_statusMessages[_currentIndex], key: ValueKey<int>(_currentIndex), style: GoogleFonts.inter(fontSize: 11, color: widget.isDark ? Colors.white38 : Colors.grey.shade600, fontStyle: FontStyle.italic)));
}

class _PulseMicIcon extends StatefulWidget {
  const _PulseMicIcon();
  @override
  State<_PulseMicIcon> createState() => _PulseMicIconState();
}

class _PulseMicIconState extends State<_PulseMicIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.4 * _controller.value), blurRadius: 10 * _controller.value, spreadRadius: 2 * _controller.value)],
        ),
        child: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent),
      ),
    );
  }
}
