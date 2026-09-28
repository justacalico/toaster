import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

class ToasterApp extends StatelessWidget {
  final AppState state;

  const ToasterApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        title: 'toaster',
        debugShowCheckedModeBanner: false,
        theme: T.theme(),
        darkTheme: T.theme(),
        home: const RootShell(),
      ),
    );
  }
}
