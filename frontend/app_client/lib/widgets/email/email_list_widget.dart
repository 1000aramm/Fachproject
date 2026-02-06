import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/email_service.dart';
import '../glass_container.dart';

class EmailListWidget extends StatefulWidget {
  final String username;
  final String password;
  final bool isDark;

  const EmailListWidget({
    super.key,
    required this.username,
    required this.password,
    required this.isDark,
  });

  @override
  State<EmailListWidget> createState() => _EmailListWidgetState();
}

class _EmailListWidgetState extends State<EmailListWidget> {
  final EmailService _emailService = EmailService();
  late Future<List<UniEmail>> _emailsFuture;

  @override
  void initState() {
    super.initState();
    _emailsFuture = _emailService.fetchEmails(widget.username, widget.password);
  }

  void _onRefresh() {
    setState(() {
      _emailsFuture = _emailService.fetchEmails(widget.username, widget.password);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _onRefresh,
              icon: Icon(Icons.refresh_rounded, size: 16, color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.5)),
              label: Text(
                "Refresh",
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        FutureBuilder<List<UniEmail>>(
          future: _emailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 250,
                child: Center(child: CircularProgressIndicator())
              );
            } else if (snapshot.hasError) {
              return SizedBox(
                height: 250,
                child: Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87)))
              );
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return SizedBox(
                height: 250,
                child: Center(child: Text('No emails found.', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87)))
              );
            }

            final emails = snapshot.data!;
            
            return SizedBox(
              height: 250, // Height for roughly 3.5 items
              child: ListView.separated(
                shrinkWrap: false,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: emails.length > 20 ? 20 : emails.length,
                separatorBuilder: (context, index) => Divider(color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
                itemBuilder: (context, index) {
                  final email = emails[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(
                      email.subject,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: widget.isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          email.sender,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          email.date,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _showEmailDetail(context, email),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  void _showEmailDetail(BuildContext context, UniEmail email) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: GlassContainer(
            padding: const EdgeInsets.all(24),
            blur: 20,
            opacity: widget.isDark ? 0.15 : 0.4,
            borderRadius: 30,
            child: FutureBuilder<String>(
              future: _emailService.fetchEmailBody(widget.username, widget.password, email.id),
              builder: (context, snapshot) {
                final isLoading = snapshot.connectionState == ConnectionState.waiting;
                final bodyContent = snapshot.data ?? (isLoading ? 'Fetching full message...' : 'No content found.');

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            email.subject,
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: widget.isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: widget.isDark ? Colors.white54 : Colors.black54),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'From: ${email.sender}',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      'Date: ${email.date}',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Divider(color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: isLoading 
                          ? const Center(child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(),
                            ))
                          : Text(
                              bodyContent,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                height: 1.5,
                                color: widget.isDark ? Colors.white : Colors.black,
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isDark ? Colors.white24 : Colors.black12,
                          foregroundColor: widget.isDark ? Colors.white : Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                );
              }
            ),
          ),
        ),
      ),
    );
  }
}
