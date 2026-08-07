import 'package:flutter/material.dart';

import 'core/router/app_router.dart';

class TukiTukiDriverApp extends StatelessWidget {
  const TukiTukiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TukiTuki Conductor',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.amber,
        inputDecorationTheme:
            const InputDecorationTheme(
          filled: true,
        ),
      ),
    );
  }
}