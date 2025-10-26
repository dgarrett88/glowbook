import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/canvas/view/canvas_screen.dart';

void main() => runApp(const ProviderScope(child: GlowBookApp()));

class GlowBookApp extends StatelessWidget {
  const GlowBookApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GlowBook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const CanvasScreen(),
    );
  }
}
