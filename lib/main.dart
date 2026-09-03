import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/editor_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MenoApp()));
}

class MenoApp extends StatelessWidget {
  const MenoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF262923);
    const paper = Color(0xFFF7F6F1);
    return MaterialApp(
      title: 'Meno',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFAAB6A8),
          brightness: Brightness.light,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
          fontFamily: 'Georgia',
        ),
      ),
      home: const EditorScreen(),
    );
  }
}
