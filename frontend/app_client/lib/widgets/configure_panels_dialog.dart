import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/panel_config_service.dart';
import '../utils/design_tokens.dart';

class ConfigurePanelsDialog extends StatefulWidget {
  final List<PanelConfig> panels;
  final Function(List<PanelConfig>) onSave;

  const ConfigurePanelsDialog({
    super.key,
    required this.panels,
    required this.onSave,
  });

  @override
  State<ConfigurePanelsDialog> createState() => _ConfigurePanelsDialogState();
}

class _ConfigurePanelsDialogState extends State<ConfigurePanelsDialog> {
  late List<PanelConfig> _panels;

  @override
  void initState() {
    super.initState();
    // Create deep copy of panels
    _panels = widget.panels.map((p) => p.copyWith()).toList();
  }

  List<PanelConfig> get _leftPanels => 
      _panels.where((p) => p.column == 'left').toList()..sort((a, b) => a.order.compareTo(b.order));
  
  List<PanelConfig> get _rightPanels => 
      _panels.where((p) => p.column == 'right').toList()..sort((a, b) => a.order.compareTo(b.order));

  void _toggleVisibility(String panelId) {
    setState(() {
      final panel = _panels.firstWhere((p) => p.id == panelId);
      panel.isVisible = !panel.isVisible;
    });
  }

  void _moveToColumn(String panelId, String targetColumn) {
    setState(() {
      final panel = _panels.firstWhere((p) => p.id == panelId);
      final targetPanels = _panels.where((p) => p.column == targetColumn).toList();
      panel.column = targetColumn;
      panel.order = targetPanels.length;
      _reorderColumn(targetColumn);
    });
  }

  void _reorderColumn(String column) {
    final columnPanels = _panels.where((p) => p.column == column).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    for (int i = 0; i < columnPanels.length; i++) {
      columnPanels[i].order = i;
    }
  }

  void _onReorderLeft(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final leftPanels = _leftPanels;
      final item = leftPanels.removeAt(oldIndex);
      leftPanels.insert(newIndex, item);
      for (int i = 0; i < leftPanels.length; i++) {
        leftPanels[i].order = i;
      }
    });
  }

  void _onReorderRight(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final rightPanels = _rightPanels;
      final item = rightPanels.removeAt(oldIndex);
      rightPanels.insert(newIndex, item);
      for (int i = 0; i < rightPanels.length; i++) {
        rightPanels[i].order = i;
      }
    });
  }

  void _saveAndClose() {
    widget.onSave(_panels);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: DesignTokens.surface(isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 750,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DesignTokens.braunOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.dashboard_customize_rounded, color: DesignTokens.braunOrange, size: 20),
                ),
                const SizedBox(width: 16),
                Text(
                  'Configure Panels',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: DesignTokens.textPrimary(isDark),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: DesignTokens.textTert(isDark)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Two Column Layout
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column
                  Expanded(
                    child: _buildColumnSection(
                      title: 'LEFT COLUMN',
                      panels: _leftPanels,
                      onReorder: _onReorderLeft,
                      currentColumn: 'left',
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Right Column
                  Expanded(
                    child: _buildColumnSection(
                      title: 'RIGHT COLUMN',
                      panels: _rightPanels,
                      onReorder: _onReorderRight,
                      currentColumn: 'right',
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveAndClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DesignTokens.braunOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  'Save Changes',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnSection({
    required String title,
    required List<PanelConfig> panels,
    required void Function(int, int) onReorder,
    required String currentColumn,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.background(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.border(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DesignTokens.textTert(isDark),
                letterSpacing: 1.5,
              ),
            ),
          ),
          Divider(height: 1, color: DesignTokens.border(isDark)),
          Expanded(
            child: panels.isEmpty
                ? Center(
                    child: Text(
                      'No panels',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: DesignTokens.textTert(isDark),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: panels.length,
                    onReorder: onReorder,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final panel = panels[index];
                      return _buildPanelCard(
                        key: ValueKey(panel.id),
                        panel: panel,
                        currentColumn: currentColumn,
                        isDark: isDark,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelCard({
    required Key key,
    required PanelConfig panel,
    required String currentColumn,
    required bool isDark,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: DesignTokens.surface(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesignTokens.border(isDark)),
      ),
      child: Row(
        children: [
          // Checkbox for visibility
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: panel.isVisible,
              onChanged: (_) => _toggleVisibility(panel.id),
              activeColor: DesignTokens.braunOrange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              side: BorderSide(color: DesignTokens.textTert(isDark), width: 1.5),
            ),
          ),
          const SizedBox(width: 10),
          // Panel Icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: DesignTokens.braunOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(panel.icon, color: DesignTokens.braunOrange, size: 14),
          ),
          const SizedBox(width: 10),
          // Panel Name
          Expanded(
            child: Text(
              panel.name,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: panel.isVisible 
                    ? DesignTokens.textPrimary(isDark) 
                    : DesignTokens.textTert(isDark),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Move to other column button (just arrow)
          Tooltip(
            message: currentColumn == 'left' ? 'Move to Right Column' : 'Move to Left Column',
            child: InkWell(
              onTap: () => _moveToColumn(panel.id, currentColumn == 'left' ? 'right' : 'left'),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: DesignTokens.mutedBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  currentColumn == 'left' ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                  size: 16,
                  color: DesignTokens.mutedBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

}

