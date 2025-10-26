import 'package:flutter/material.dart';
import '../../state/canvas_controller.dart'; // for type only
import '../../state/glow_blend.dart' as gb;

class GlowBlendDropdown extends StatefulWidget {
  final CanvasController controller;
  const GlowBlendDropdown({super.key, required this.controller});

  @override
  State<GlowBlendDropdown> createState() => _GlowBlendDropdownState();
}

class _GlowBlendDropdownState extends State<GlowBlendDropdown> {
  @override
  void initState() {
    super.initState();
    gb.GlowBlendState.I.addListener(_onBlendChanged);
  }

  @override
  void dispose() {
    gb.GlowBlendState.I.removeListener(_onBlendChanged);
    super.dispose();
  }

  void _onBlendChanged(){
    if(mounted) setState((){});
  }

  @override
  Widget build(BuildContext context) {
    final mode = gb.GlowBlendState.I.mode;
    return DropdownButton<gb.GlowBlend>(
      value: mode,
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: gb.GlowBlend.additive, child: Text('Additive')),
        DropdownMenuItem(value: gb.GlowBlend.screen, child: Text('Screen')),
      ],
      onChanged: (v){
        if(v==null) return;
        gb.GlowBlendState.I.setMode(v);
      },
    );
  }
}
