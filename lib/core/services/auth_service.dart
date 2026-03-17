import '../config/api_config.dart';
import 'api_service.dart';

/// Modelo de usuario para autenticación.
class User {
  final String id;
  final String username;
  final String fullName;
  final String department;
  final String shift;

  const User({
    required this.id,
    required this.username,
    required this.fullName,
    required this.department,
    required this.shift,
  });

  /// Crea un User desde JSON de la API.
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? '',
      department: json['department'] ?? '',
      shift: json['shift'] ?? '',
    );
  }

  /// Convierte a JSON (para persistencia local).
  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'department': department,
        'shift': shift,
      };
}

/// Resultado de autenticación.
class AuthResult {
  final bool success;
  final String? error;
  final User? user;
  final String? token;

  AuthResult({
    required this.success,
    this.error,
    this.user,
    this.token,
  });
}

/// Servicio de autenticación.
/// 
/// Modos de operación:
/// - [useMockData] = true: Usa datos locales para desarrollo/demo
/// - [useMockData] = false: Conecta con la API del backend MES
abstract class AuthService {
  /// Cambia a false cuando el backend esté listo.
  static const bool useMockData = false;

  /// Usuario actualmente autenticado.
  static User? _currentUser;

  /// Obtiene el usuario actual.
  static User? get currentUser => _currentUser;

  /// Realiza la autenticación de usuario.
  static Future<AuthResult> login(String username, String password) async {
    if (useMockData) {
      return _mockLogin(username, password);
    }
    return _apiLogin(username, password);
  }

  /// Login contra la API real del backend MES.
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
      );
    }

    final data = response.data;
    if (data == null) {
      return AuthResult(
        success: false,
        error: 'Respuesta vacía del servidor',
      );
    }

    // Extraer token y usuario de la respuesta
    final token = data['token'] as String?;
    final userData = data['user'] as Map<String, dynamic>?;

    if (token == null || userData == null) {
      return AuthResult(
        success: false,
        error: 'Respuesta inválida del servidor',
      );
    }

    // Guardar token para requests subsecuentes
    ApiService.setAuthToken(token);

    final user = User.fromJson(userData);
    _currentUser = user;

    return AuthResult(
      success: true,
      user: user,
      token: token,
    );
  }

  /// Login con datos mock para desarrollo.
  static Future<AuthResult> _mockLogin(String username, String password) async {
    // Simular latencia de red
    await Future.delayed(const Duration(milliseconds: 800));

    final user = _mockUsers.firstWhere(
      (u) => u.username == username,
      orElse: () => _nullUser,
    );

    // Validar usuario y contraseña (en mock, password = username)
    if (user == _nullUser || password != username && password != 'admin123') {
      return AuthResult(
        success: false,
        error: 'Usuario o contraseña incorrectos',
      );
    }

    _currentUser = user;

    return AuthResult(
      success: true,
      user: user,
      token: 'mock_token_${user.id}',
    );
  }

  /// Cierra la sesión del usuario.
  static Future<void> logout() async {
    if (!useMockData) {
      // Notificar al servidor (opcional)
      await ApiService.post(ApiConfig.logoutEndpoint);
    }
    
    ApiService.clearAuthToken();
    _currentUser = null;
  }

  /// Verifica si hay una sesión activa.
  static bool get isAuthenticated => _currentUser != null;

  // ═══════════════════════════════════════════════════════════════════════════
  //  DATOS MOCK PARA DESARROLLO
  // ═══════════════════════════════════════════════════════════════════════════

  static final List<User> _mockUsers = [
    const User(
      id: '1247',
      username: '1247',
      fullName: 'Operador 1247',
      department: 'Almacén de Embarques',
      shift: 'Turno A',
    ),
    const User(
      id: '1248',
      username: '1248',
      fullName: 'Operador 1248',
      department: 'Almacén de Embarques',
      shift: 'Turno B',
    ),
    const User(
      id: '1249',
      username: '1249',
      fullName: 'Operador 1249',
      department: 'Control de Calidad',
      shift: 'Turno A',
    ),
    const User(
      id: 'admin',
      username: 'admin',
      fullName: 'Administrador Sistema',
      department: 'TI',
      shift: 'Turno Administrativo',
    ),
  ];

  static const User _nullUser = User(
    id: '',
    username: '',
    fullName: '',
    department: '',
    shift: '',
  );

  /// Obtiene lista de usuarios mock (solo para demo).
  static List<User> get demoUsers => _mockUsers;
}
