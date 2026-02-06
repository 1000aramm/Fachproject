import 'package:flutter/material.dart';

/// Neo-Analog Design System inspired by Dieter Rams
/// A focused, peaceful, and compact design language
class DesignTokens {
  DesignTokens._();

  // ============================================
  // CORE PALETTE - Warm, Paper-like tones
  // ============================================
  
  /// Soft Vanilla - Primary background (matte paper feel)
  static const Color softVanilla = Color(0xFFF5F5F0);
  
  /// Warm Grey - Secondary background
  static const Color warmGrey = Color(0xFFEFECE5);
  
  /// Card Surface - Slightly lighter for depth
  static const Color cardSurface = Color(0xFFFAFAF7);
  
  /// Braun Black - Primary text (not pure black)
  static const Color braunBlack = Color(0xFF1A1A1A);
  
  /// Secondary Text
  static const Color textSecondary = Color(0xFF5A5A55);
  
  /// Tertiary Text (labels, hints)
  static const Color textTertiary = Color(0xFF8A8A85);
  
  // ============================================
  // ACCENT COLORS
  // ============================================
  
  /// Braun Orange - Primary CTA (use sparingly)
  static const Color braunOrange = Color(0xFFED8008);
  
  /// Sage Green - Positive metrics, success states
  static const Color sageGreen = Color(0xFF736B1E);
  
  /// Signal Yellow - Warnings, deadlines
  static const Color signalYellow = Color(0xFFF0C525);
  
  /// Muted Blue - Information, links
  static const Color mutedBlue = Color(0xFF4A6B8A);
  
  /// Soft Red - Urgent (muted, not aggressive)
  static const Color softRed = Color(0xFFC45B3E);
  
  // ============================================
  // DARK MODE PALETTE
  // ============================================
  
  /// Dark background - warm charcoal
  static const Color darkBackground = Color(0xFF1C1C1A);
  
  /// Dark surface - elevated cards
  static const Color darkSurface = Color(0xFF2A2A28);
  
  /// Dark card - slightly lighter
  static const Color darkCard = Color(0xFF323230);
  
  /// Dark text primary
  static const Color darkTextPrimary = Color(0xFFF0F0EC);
  
  /// Dark text secondary
  static const Color darkTextSecondary = Color(0xFFA0A098);
  
  /// Dark text tertiary
  static const Color darkTextTertiary = Color(0xFF707068);

  // ============================================
  // SPACING
  // ============================================
  
  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 16.0;
  static const double spacingLG = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // ============================================
  // BORDER RADIUS
  // ============================================
  
  static const double radiusSM = 8.0;
  static const double radiusMD = 12.0;
  static const double radiusLG = 16.0;
  static const double radiusXL = 24.0;

  // ============================================
  // SHADOWS (Soft, diffused for tactile feel)
  // ============================================
  
  static List<BoxShadow> cardShadow(bool isDark) => [
    BoxShadow(
      color: isDark 
          ? Colors.black.withValues(alpha: 0.3) 
          : Colors.black.withValues(alpha: 0.06),
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: isDark 
          ? Colors.black.withValues(alpha: 0.2) 
          : Colors.black.withValues(alpha: 0.03),
      blurRadius: 6,
      spreadRadius: 0,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> buttonShadow(bool isDark) => [
    BoxShadow(
      color: isDark 
          ? Colors.black.withValues(alpha: 0.4) 
          : Colors.black.withValues(alpha: 0.08),
      blurRadius: 8,
      spreadRadius: -2,
      offset: const Offset(0, 3),
    ),
  ];

  // ============================================
  // HELPER METHODS
  // ============================================
  
  static Color background(bool isDark) => isDark ? darkBackground : softVanilla;
  static Color surface(bool isDark) => isDark ? darkSurface : cardSurface;
  static Color textPrimary(bool isDark) => isDark ? darkTextPrimary : braunBlack;
  static Color textSec(bool isDark) => isDark ? darkTextSecondary : textSecondary;
  static Color textTert(bool isDark) => isDark ? darkTextTertiary : textTertiary;
  static Color border(bool isDark) => isDark 
      ? Colors.white.withValues(alpha: 0.08) 
      : Colors.black.withValues(alpha: 0.06);
}

/// Neo-Analog Card Widget - Warm paper-like containers
class NeoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double? width;
  final double? height;
  final bool elevated;

  const NeoCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = DesignTokens.radiusXL,
    this.width,
    this.height,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: DesignTokens.surface(isDark),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: DesignTokens.border(isDark),
          width: 1.0,
        ),
        boxShadow: elevated ? DesignTokens.cardShadow(isDark) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Tactile Button - Subtle bevel for physical press feel
class TactileButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isCompact;

  const TactileButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isPrimary = false,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMD),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 20,
            vertical: isCompact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: isPrimary 
                ? DesignTokens.braunOrange 
                : (isDark ? DesignTokens.darkCard : Colors.white),
            borderRadius: BorderRadius.circular(DesignTokens.radiusMD),
            border: Border.all(
              color: isPrimary 
                  ? DesignTokens.braunOrange 
                  : DesignTokens.border(isDark),
            ),
            boxShadow: DesignTokens.buttonShadow(isDark),
            // Subtle inner highlight for tactile feel
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isPrimary 
                  ? [
                      DesignTokens.braunOrange.withValues(alpha: 1.0),
                      DesignTokens.braunOrange.withValues(alpha: 0.85),
                    ]
                  : [
                      (isDark ? DesignTokens.darkCard : Colors.white).withValues(alpha: 1.0),
                      (isDark ? DesignTokens.darkCard : const Color(0xFFF5F5F0)).withValues(alpha: 1.0),
                    ],
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: isCompact ? 16 : 18,
                  color: isPrimary 
                      ? Colors.white 
                      : DesignTokens.textSec(isDark),
                ),
                SizedBox(width: isCompact ? 6 : 10),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: isCompact ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: isPrimary 
                      ? Colors.white 
                      : DesignTokens.textPrimary(isDark),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section Label - Uppercase, tracked out
class SectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? iconColor;

  const SectionLabel({
    super.key,
    required this.text,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: iconColor ?? DesignTokens.textTert(isDark),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DesignTokens.textTert(isDark),
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }
}

/// Split-Flap Display Style Counter (Analog feel)
class AnalogCounter extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color? accentColor;

  const AnalogCounter({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Split-flap style value display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 1,
                ),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (accentColor ?? DesignTokens.braunOrange).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: accentColor ?? DesignTokens.braunOrange,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: DesignTokens.textTert(isDark),
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
