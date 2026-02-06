import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/design_tokens.dart';

/// Neo-Analog Glass Container
/// Warm, paper-like cards with soft tactile shadows
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final double opacity;
  final Color? color;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 24,
    this.blur = 0, // Reduced blur for cleaner look
    this.opacity = 1.0,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Neo-Analog surface colors
    final surfaceColor = color ?? DesignTokens.surface(isDark);
    
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        // Soft, diffused shadows for tactile depth
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withValues(alpha: 0.35) 
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: isDark 
                ? Colors.black.withValues(alpha: 0.2) 
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
          // Subtle inner glow for depth (light mode only)
          if (!isDark)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.8),
              blurRadius: 0,
              spreadRadius: -1,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: blur > 0 
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: _buildContent(isDark, surfaceColor),
              )
            : _buildContent(isDark, surfaceColor),
      ),
    );
  }

  Widget _buildContent(bool isDark, Color surfaceColor) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(
          color: DesignTokens.border(isDark),
          width: 1.0,
        ),
        // Subtle gradient for paper texture feel
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surfaceColor,
            isDark 
                ? surfaceColor.withValues(alpha: 0.95)
                : Color.lerp(surfaceColor, const Color(0xFFEFECE5), 0.05)!,
          ],
        ),
      ),
      child: child,
    );
  }
}
