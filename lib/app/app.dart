import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import '../features/canvas/view/canvas_screen.dart';

class GlowBookApp extends StatelessWidget {
  const GlowBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'GlowBook',
        debugShowCheckedModeBanner: false,
        theme: buildGlowTheme(),
        home: const CanvasScreen(),
      ),
    );
  }
}
