import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'api_service.dart';
import 'cache_service.dart';

/// Modelo de usuario para autenticación.
class User {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String department;
  final String cargo;
  final bool isActive;
  final List<String> permissions;

  const User({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
    required this.department,
    required this.cargo,
    required this.isActive,
    this.permissions = const [],
  });

  /// Compatibilidad con vistas que todavía muestran un "turno".
  String get shift => cargo;

  /// Crea un [User] desde JSON de la API o sesión local.
  factory User.fromJson(
    Map<String, dynamic> json, {
    List<String>? permissions,
  }) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: (json['full_name'] ?? json['nombre_completo'] ?? '').toString(),
      email: json['email']?.toString(),
      department: (json['department'] ?? json['departamento'] ?? '').toString(),
      cargo: (json['cargo'] ?? json['shift'] ?? '').toString(),
      isActive:
          _parseBool(json['active'] ?? json['activo'], defaultValue: true),
      permissions: List.unmodifiable(
        permissions ?? _parsePermissions(json['permissions']),
      ),
    );
  }

  /// Convierte a JSON para persistencia local.
  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'email': email,
        'department': department,
        'cargo': cargo,
        'active': isActive,
        'permissions': permissions,
      };

  User copyWith({
    List<String>? permissions,
  }) {
    return User(
      id: id,
      username: username,
      fullName: fullName,
      email: email,
      department: department,
      cargo: cargo,
      isActive: isActive,
      permissions: permissions ?? this.permissions,
    );
  }

  static bool _parseBool(dynamic value, {required bool defaultValue}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == '1' || normalized == 'true') {
        return true;
      }
      if (normalized == '0' || normalized == 'false') {
        return false;
      }
    }
    return defaultValue;
  }

  static List<String> _parsePermissions(dynamic rawPermissions) {
    if (rawPermissions is! List) {
      return const [];
    }

    final permissions = <String>[];
    for (final permission in rawPermissions) {
      if (permission is String && permission.isNotEmpty) {
        permissions.add(permission);
        continue;
      }

      if (permission is Map<String, dynamic>) {
        final key = permission['permission_key']?.toString();
        final enabled = _parseBool(permission['enabled'], defaultValue: true);
        if (key != null && key.isNotEmpty && enabled) {
          permissions.add(key);
        }
      }
    }

    return permissions;
  }
}

/// Resultado de autenticación.
class AuthResult {
  final bool success;
  final String? error;
  final User? user;
  final int? attemptsRemaining;
  final DateTime? blockedUntil;

  const AuthResult({
    required this.success,
    this.error,
    this.user,
    this.attemptsRemaining,
    this.blockedUntil,
  });
}

/// Servicio de autenticación con persistencia de sesión local.
abstract class AuthService {
  /// Cambia a `true` para pruebas sin backend.
  static const bool useMockData = false;
  static const String viewDashboardPermission = 'view_shipping_dashboard';
  static const String writeEntriesPermission = 'write_shipping_entries';
  static const String viewHistoryPermission = 'view_shipping_history';
  static const String viewSettingsPermission = 'view_shipping_settings';
  static const String manageUsersPermission = 'manage_shipping_users';

  static const Duration _sessionDuration = Duration(hours: 24);
  static const String _userSessionKey = 'user_session';
  static const String _sessionStartTimeKey = 'session_start_time';

  static User? _currentUser;

  /// Usuario actualmente autenticado.
  static User? get currentUser => _currentUser;

  /// Estado de autenticación actual.
  static bool get isAuthenticated => _currentUser != null;

  /// Permisos cargados del usuario actual.
  static List<String> get currentPermissions =>
      _currentUser?.permissions ?? const [];

  static bool hasPermission(String permissionKey) {
    return currentPermissions.contains(permissionKey);
  }

  static bool get canViewDashboard => hasPermission(viewDashboardPermission);

  static bool get canWriteEntries => hasPermission(writeEntriesPermission);

  static bool get canViewHistory => hasPermission(viewHistoryPermission);

  static bool get canViewSettings => hasPermission(viewSettingsPermission);

  /// Restaura la sesión local si sigue vigente.
  static Future<bool> restoreSession() async {
    if (useMockData) {
      return _restoreMockSession();
    }

    final prefs = await SharedPreferences.getInstance();
    final userSession = prefs.getString(_userSessionKey);
    final sessionStartTime = prefs.getString(_sessionStartTimeKey);

    if (userSession == null || sessionStartTime == null) {
      await _clearLocalSession(prefs: prefs);
      return false;
    }

    final storedAt = DateTime.tryParse(sessionStartTime);
    if (storedAt == null ||
        DateTime.now().difference(storedAt) > _sessionDuration) {
      await _clearLocalSession(prefs: prefs);
      return false;
    }

    try {
      final storedUser = User.fromJson(
        jsonDecode(userSession) as Map<String, dynamic>,
      );

      if (storedUser.id.isEmpty) {
        await _clearLocalSession(prefs: prefs);
        return false;
      }

      final verifyResponse = await ApiService.get(
        '${ApiConfig.verifySessionEndpoint}/${storedUser.id}',
      );

      final verifiedUserData = verifyResponse.data?['user'];
      final isValid = verifyResponse.success &&
          verifiedUserData is Map<String, dynamic> &&
          (verifyResponse.data?['valid'] != false);

      if (!isValid) {
        await _clearLocalSession(prefs: prefs);
        return false;
      }

      final permissions = await _loadPermissions(storedUser.id);
      final verifiedUser = User.fromJson(
        verifiedUserData,
        permissions: permissions,
      );

      _currentUser = verifiedUser;
      await _persistSession(verifiedUser,
          prefs: prefs, sessionStartedAt: storedAt);
      return true;
    } catch (_) {
      await _clearLocalSession(prefs: prefs);
      return false;
    }
  }

  /// Realiza autenticación interactiva.
  static Future<AuthResult> login(String username, String password) async {
    if (useMockData) {
      return _mockLogin(username, password);
    }
    return _apiLogin(username, password);
  }

  /// Login contra la API real del backend.
  static Future<AuthResult> _apiLogin(String username, String password) async {
    final response = await ApiService.post(
      ApiConfig.loginEndpoint,
      body: {
        'username': username,
        'password': password,
      },
    );

    if (!response.success) {
      return AuthResult(
        success: false,
        error: response.error ?? 'Error de autenticación',
        attemptsRemaining: _parseAttemptsRemaining(response.data),
        blockedUntil: _parseBlockedUntil(response.data),
      );
    }

    final data = response.data;
    final userData = data?['user'];
    if (userData is! Map<String, dynamic>) {
      return const AuthResult(
        success: false,
        error: 'Respuesta inválida del servidor',
      );
    }

    final userId = userData['id']?.toString() ?? '';
    final permissions = await _loadPermissions(userId);
    final user = User.fromJson(userData, permissions: permissions);

    _currentUser = user;
    ApiService.clearAuthToken();
    await _persistSession(user);

    return AuthResult(
      success: true,
      user: user,
    );
  }

  /// Login con datos mock para desarrollo.
  static Future<AuthResult> _mockLogin(String username, String password) async {
    await Future.delayed(const Duration(milliseconds: 800));

    final user = _mockUsers.firstWhere(
      (item) => item.username == username,
      orElse: () => _nullUser,
    );

    if (user == _nullUser || (password != username && password != 'admin123')) {
      return const AuthResult(
        success: false,
        error: 'Usuario o contraseña incorrectos',
      );
    }

    _currentUser = user;
    await _persistSession(user);

    return AuthResult(
      success: true,
      user: user,
    );
  }

  /// Cierra la sesión local y notifica al backend.
  static Future<void> logout() async {
    final userId = _currentUser?.id;

    try {
      if (!useMockData && userId != null && userId.isNotEmpty) {
        await ApiService.post(
          ApiConfig.logoutEndpoint,
          body: {'userId': userId},
        );
      }
    } finally {
      await _clearLocalSession();
    }
  }

  static Future<List<String>> _loadPermissions(String userId) async {
    if (userId.isEmpty) {
      return const [];
    }

    final response = await ApiService.get(
      '${ApiConfig.usersEndpoint}/$userId/permissions',
    );

    if (!response.success || response.data == null) {
      return const [];
    }

    final data = response.data!;
    final enabledPermissions = data['enabledPermissions'];
    if (enabledPermissions is List) {
      return enabledPermissions
          .map((permission) => permission.toString())
          .where((permission) => permission.isNotEmpty)
          .toList();
    }

    final permissions = data['permissions'];
    if (permissions is List) {
      return permissions
          .whereType<Map<String, dynamic>>()
          .where((permission) =>
              User._parseBool(permission['enabled'], defaultValue: true))
          .map((permission) => permission['permission_key']?.toString() ?? '')
          .where((permission) => permission.isNotEmpty)
          .toList();
    }

    return const [];
  }

  static int? _parseAttemptsRemaining(Map<String, dynamic>? data) {
    final attempts = data?['intentosRestantes'];
    if (attempts is int) {
      return attempts;
    }
    if (attempts is String) {
      return int.tryParse(attempts);
    }
    return null;
  }

  static DateTime? _parseBlockedUntil(Map<String, dynamic>? data) {
    final blockedUntil = data?['blockedUntil']?.toString();
    if (blockedUntil == null || blockedUntil.isEmpty) {
      return null;
    }
    return DateTime.tryParse(blockedUntil);
  }

  static Future<void> _persistSession(
    User user, {
    SharedPreferences? prefs,
    DateTime? sessionStartedAt,
  }) async {
    final sharedPrefs = prefs ?? await SharedPreferences.getInstance();
    await sharedPrefs.setString(_userSessionKey, jsonEncode(user.toJson()));
    await sharedPrefs.setString(
      _sessionStartTimeKey,
      (sessionStartedAt ?? DateTime.now()).toIso8601String(),
    );
  }

  static Future<void> _clearLocalSession({
    SharedPreferences? prefs,
  }) async {
    final sharedPrefs = prefs ?? await SharedPreferences.getInstance();
    await sharedPrefs.remove(_userSessionKey);
    await sharedPrefs.remove(_sessionStartTimeKey);
    ApiService.clearAuthToken();
    CacheService.clear();
    _currentUser = null;
  }

  static Future<bool> _restoreMockSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userSession = prefs.getString(_userSessionKey);
    final sessionStartTime = prefs.getString(_sessionStartTimeKey);

    if (userSession == null || sessionStartTime == null) {
      await _clearLocalSession(prefs: prefs);
      return false;
    }

    final storedAt = DateTime.tryParse(sessionStartTime);
    if (storedAt == null ||
        DateTime.now().difference(storedAt) > _sessionDuration) {
      await _clearLocalSession(prefs: prefs);
      return false;
    }

    try {
      _currentUser = User.fromJson(
        jsonDecode(userSession) as Map<String, dynamic>,
      );
      return _currentUser != null;
    } catch (_) {
      await _clearLocalSession(prefs: prefs);
      return false;
    }
  }

  static const List<String> _defaultMockPermissions = [
    'view_shipping_dashboard',
    'write_shipping_entries',
    'view_shipping_history',
    'view_shipping_settings',
  ];

  static final List<User> _mockUsers = [
    const User(
      id: '1247',
      username: '1247',
      fullName: 'Operador 1247',
      department: 'Almacén de Embarques',
      cargo: 'Operador de Embarques',
      isActive: true,
      permissions: _defaultMockPermissions,
    ),
    const User(
      id: '1248',
      username: '1248',
      fullName: 'Operador 1248',
      department: 'Almacén de Embarques',
      cargo: 'Supervisor de Embarques',
      isActive: true,
      permissions: _defaultMockPermissions,
    ),
    const User(
      id: '1249',
      username: '1249',
      fullName: 'Inspector 1249',
      department: 'Calidad',
      cargo: 'Inspector de Calidad',
      isActive: true,
      permissions: _defaultMockPermissions,
    ),
    const User(
      id: '1',
      username: 'admin',
      fullName: 'Administrador Sistema',
      department: 'Sistemas',
      cargo: 'Administrador',
      isActive: true,
      permissions: [
        ..._defaultMockPermissions,
        'manage_shipping_users',
      ],
    ),
  ];

  static const User _nullUser = User(
    id: '',
    username: '',
    fullName: '',
    department: '',
    cargo: '',
    isActive: false,
  );
}
