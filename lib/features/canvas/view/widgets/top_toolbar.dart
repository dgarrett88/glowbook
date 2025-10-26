import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';

class TopToolbar extends StatelessWidget implements PreferredSizeWidget {
  final CanvasController controller;
  final VoidCallback? onExport; // keep existing 'save/export' callback
  final VoidCallback? onNew;    // optional 'new canvas' callback

  const TopToolbar({
    super.key,
    required this.controller,
    this.onExport,
    this.onNew,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('GlowBook'),
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
