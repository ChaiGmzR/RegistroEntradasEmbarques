import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../../features/login/login_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/scan/scan_screen.dart';
import '../../features/scan/scan_result_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/settings/settings_screen.dart';

/// Configuración de rutas de navegación de la app.
class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppConstants.loginRoute:
        return _buildRoute(const LoginScreen(), settings);
      case AppConstants.homeRoute:
        return _buildRoute(const HomeScreen(), settings);
      case AppConstants.scanRoute:
        return _buildRoute(const ScanScreen(), settings);
      case AppConstants.scanResultRoute:
        final args = settings.arguments as ScanResultArguments?;
        return _buildRoute(ScanResultScreen(arguments: args), settings);
      case AppConstants.historyRoute:
        return _buildRoute(const HistoryScreen(), settings);
      case AppConstants.settingsRoute:
        return _buildRoute(const SettingsScreen(), settings);
      default:
        return _buildRoute(const LoginScreen(), settings);
    }
  }

  static MaterialPageRoute _buildRoute(Widget page, RouteSettings settings) {
    return MaterialPageRoute(
      builder: (_) => page,
      settings: settings,
    );
  }
}
