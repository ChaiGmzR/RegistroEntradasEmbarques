import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/dark_theme.dart';
import 'core/theme/light_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientación preferida para PDA
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const RegistroEmbarquesApp());
}

/// Aplicación principal: Registro de Entradas de Embarques.
class RegistroEmbarquesApp extends StatefulWidget {
  const RegistroEmbarquesApp({super.key});

  /// Acceso global al state para cambio de tema (mockup).
  static RegistroEmbarquesAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<RegistroEmbarquesAppState>();

  @override
  State<RegistroEmbarquesApp> createState() => RegistroEmbarquesAppState();
}

class RegistroEmbarquesAppState extends State<RegistroEmbarquesApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      initialRoute: AppConstants.loginRoute,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
