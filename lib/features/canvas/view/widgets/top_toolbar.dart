import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';
import 'brush_hud.dart';

class TopToolbar extends StatelessWidget {
  final CanvasController controller;
  final VoidCallback? onExport;
  const TopToolbar({super.key, required this.controller, this.onExport});

  IconData _symIcon(SymmetryMode m){
    switch(m){
      case SymmetryMode.off: return Icons.close_fullscreen;
      case SymmetryMode.mirrorV: return Icons.swap_horiz;
      case SymmetryMode.mirrorH: return Icons.swap_vert;
      case SymmetryMode.quad: return Icons.grid_4x4;
    }
  }

  void _openBrushHUD(BuildContext context){
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BrushHUD(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('GlowBook'),
      actions: [
        IconButton(
          icon: const Icon(Icons.brush),
          tooltip: 'Brush HUD',
          onPressed: () => _openBrushHUD(context),
        ),
        IconButton(
          icon: Icon(_symIcon(controller.symmetry)),
          tooltip: 'Cycle symmetry',
          onPressed: controller.cycleSymmetry,
        ),
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
