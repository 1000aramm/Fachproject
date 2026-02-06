import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/design_tokens.dart';

class SidebarMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const SidebarMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected 
                ? DesignTokens.braunOrange.withValues(alpha: 0.12) 
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected 
                ? Border.all(color: DesignTokens.braunOrange.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon, 
                color: isSelected 
                    ? DesignTokens.braunOrange 
                    : DesignTokens.textSec(isDark), 
                size: 20
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isSelected 
                      ? DesignTokens.braunOrange
                      : DesignTokens.textSec(isDark),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
