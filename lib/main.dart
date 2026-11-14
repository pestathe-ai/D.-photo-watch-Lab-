import 'package:flutter/material.dart';

import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const PhotoWatchApp());

class PhotoWatchApp extends StatelessWidget {
  const PhotoWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D. Photo Watch Lab',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
