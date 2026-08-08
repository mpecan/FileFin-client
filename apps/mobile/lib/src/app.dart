import 'package:filefin_mobile/src/servers/no_server_page.dart';
import 'package:flutter/material.dart';

/// The application shell: one `MaterialApp`, one theme, one home.
class FileFinApp extends StatelessWidget {
  /// Builds the shell.
  const FileFinApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FileFin',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5D8A)),
      useMaterial3: true,
    ),
    home: const NoServerPage(),
  );
}
