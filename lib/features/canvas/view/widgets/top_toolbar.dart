import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart';

class TopToolbar extends StatelessWidget {
  final CanvasController controller;
  const TopToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('GlowBook'),
      actions: [
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
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => _SettingsDialog(controller: controller),
            );
          },
          tooltip: 'Settings',
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  final CanvasController controller;
  const _SettingsDialog({required this.controller});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: const Text('Dynamic thickness'),
            value: widget.controller.dynamicThickness,
            onChanged: (v) {
              widget.controller.setDynamicThickness(v);
              setState(() {});
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
      ],
    );
  }
}
