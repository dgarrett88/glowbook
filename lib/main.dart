
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/canvas/view/canvas_screen.dart';

void main() {
  runApp(const ProviderScope(child: GlowBookApp()));
}

class GlowBookApp extends StatelessWidget {
  const GlowBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GlowBook',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6CF2FF), brightness: Brightness.dark),
      ),
      home: const CanvasScreen(),
    );
  }
}
