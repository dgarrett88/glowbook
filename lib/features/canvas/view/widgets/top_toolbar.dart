import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';
import '../../state/canvas_preview_quality.dart';

class TopToolbar extends StatelessWidget implements PreferredSizeWidget {
  final CanvasController controller;
  final VoidCallback? onExport; // keep existing 'save/export' callback
  final VoidCallback? onNew; // optional 'new canvas' callback
  final VoidCallback? onExitToMenu; // new: exit to main menu

  const TopToolbar({
    super.key,
    required this.controller,
    this.onExport,
    this.onNew,
    this.onExitToMenu,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        tooltip: 'Main menu',
        icon: const Icon(Icons.home_outlined),
        onPressed: onExitToMenu,
      ),
      title: _PreviewQualityButton(controller: controller),
      actions: [
        // New canvas (optional)
        IconButton(
          tooltip: 'New',
          icon: const Icon(Icons.add),
          onPressed: onNew,
        ),
        // Save/Export (kept compatible with existing usage)
        IconButton(
          tooltip: 'Save',
          icon: const Icon(Icons.download),
          onPressed: onExport,
        ),
        // Undo / Redo
        IconButton(
          tooltip: 'Undo',
          icon: const Icon(Icons.undo),
          onPressed: controller.undo,
        ),
        IconButton(
          tooltip: 'Redo',
          icon: const Icon(Icons.redo),
          onPressed: controller.redo,
        ),
      ],
    );
  }
}

class _PreviewQualityButton extends StatelessWidget {
  final CanvasController controller;

  const _PreviewQualityButton({
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = controller.previewMetrics;

    final label = metrics == null
        ? controller.previewQuality.label
        : '${controller.previewQuality.label} ${metrics.renderWidthPx}x${metrics.renderHeightPx}';

    return PopupMenuButton<CanvasPreviewQuality>(
      tooltip: 'Preview quality',
      initialValue: controller.previewQuality,
      onSelected: controller.setPreviewQuality,
      itemBuilder: (context) {
        return CanvasPreviewQuality.values.map((quality) {
          return PopupMenuItem<CanvasPreviewQuality>(
            value: quality,
            child: Text(quality.label),
          );
        }).toList();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
