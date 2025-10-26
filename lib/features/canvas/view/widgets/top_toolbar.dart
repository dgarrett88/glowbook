
import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';

class TopToolbar extends StatelessWidget {
  final CanvasController controller;
  final VoidCallback? onExport;
  const TopToolbar({super.key, required this.controller, this.onExport});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('GlowBook'),
      actions: [
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: 'Export PNG',
          onPressed: onExport,
        ),
        IconButton(
          icon: const Icon(Icons.undo),
          onPressed: controller.undo,
          tooltip: 'Undo',
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          onPressed: controller.redo,
          tooltip: 'Redo',
        ),
      ],
    );
  }
}
