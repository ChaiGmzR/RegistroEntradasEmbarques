import '../config/api_config.dart';
import '../../models/box_id_entry.dart';
import 'api_service.dart';

/// Resultado de consulta de calidad.
class QualityCheckResult {
  final bool success;
  final BoxIdEntry? entry;
  final String? error;

  const QualityCheckResult({
    required this.success,
    this.entry,
    this.error,
  });
}

/// Resultado de registro de entrada.
class RegisterEntryResult {
  final bool success;
  final int? entryId;
  final String? error;

  const RegisterEntryResult({
    required this.success,
    this.entryId,
    this.error,
  });
}

/// Estadísticas del día.
class DailyStats {
  final int total;
  final int released;
  final int pending;
  final int rejected;
  final int inProcess;

  const DailyStats({
    required this.total,
    required this.released,
    required this.pending,
    required this.rejected,
    required this.inProcess,
  });

  factory DailyStats.fromJson(Map<String, dynamic> json) {
    return DailyStats(
      total: json['total'] ?? 0,
      released: json['released'] ?? 0,
      pending: json['pending'] ?? 0,
      rejected: json['rejected'] ?? 0,
      inProcess: json['in_process'] ?? 0,
    );
  }

  factory DailyStats.empty() => const DailyStats(
        total: 0,
        released: 0,
        pending: 0,
        rejected: 0,
        inProcess: 0,
      );
}

/// Servicio para operaciones de embarques y validación de calidad.
class ShippingService {
  /// Consulta el estatus de calidad de un Box ID.
  /// 
  /// Retorna la información del Box ID incluyendo su estatus de calidad
  /// desde la tabla `quality_validations` de la base de datos.
  static Future<QualityCheckResult> checkQualityStatus(String boxId) async {
    final response = await ApiService.get(
      '${ApiConfig.qualityEndpoint}/$boxId',
    );

    if (!response.success) {
      // Si es 404, el Box ID no existe en el sistema
      if (response.statusCode == 404) {
        return const QualityCheckResult(
          success: false,
          error: 'Box ID no encontrado en el sistema',
        );
      }
      return QualityCheckResult(
        success: false,
        error: response.error ?? 'Error al consultar estatus de calidad',
      );
    }

    final data = response.data;
    if (data == null) {
      return const QualityCheckResult(
        success: false,
        error: 'Respuesta vacía del servidor',
      );
    }

    try {
      final entry = BoxIdEntry(
        boxId: data['box_id'] ?? boxId,
        status: _parseQualityStatus(data['quality_status']),
        scannedAt: DateTime.now(),
        productName: data['product_name'],
        lotNumber: data['lot_number'],
      );

      return QualityCheckResult(success: true, entry: entry);
    } catch (e) {
      return QualityCheckResult(
        success: false,
        error: 'Error al procesar respuesta: $e',
      );
    }
  }

  /// Registra una entrada de embarque en el sistema.
  /// 
  /// Crea un registro en la tabla `shipping_entries` con la información
  /// del escaneo realizado.
  static Future<RegisterEntryResult> registerEntry({
    required String boxId,
    required QualityStatus status,
    required String scannedBy,
    String? productName,
    String? lotNumber,
    String? warehouseZone,
    String? notes,
    String? deviceId,
  }) async {
    final response = await ApiService.post(
      ApiConfig.shippingEntriesEndpoint,
      body: {
        'box_id': boxId,
        'quality_status': _statusToString(status),
        'scanned_by': scannedBy,
        'product_name': productName,
        'lot_number': lotNumber,
        'warehouse_zone': warehouseZone,
        'notes': notes,
        'device_id': deviceId,
        'scanned_at': DateTime.now().toIso8601String(),
      },
    );

    if (!response.success) {
      return RegisterEntryResult(
        success: false,
        error: response.error ?? 'Error al registrar entrada',
      );
    }

    return RegisterEntryResult(
      success: true,
      entryId: response.data?['id'],
    );
  }

  /// Obtiene el historial de escaneos con filtros opcionales.
  static Future<List<BoxIdEntry>> getHistory({
    QualityStatus? statusFilter,
    String? searchQuery,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    if (statusFilter != null) {
      queryParams['status'] = _statusToString(statusFilter);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      queryParams['search'] = searchQuery;
    }
    if (fromDate != null) {
      queryParams['from_date'] = fromDate.toIso8601String();
    }
    if (toDate != null) {
      queryParams['to_date'] = toDate.toIso8601String();
    }

    final response = await ApiService.get(
      ApiConfig.shippingEntriesEndpoint,
      queryParams: queryParams,
    );

    if (!response.success || response.data == null) {
      return [];
    }

    final entriesJson = response.data!['entries'] as List<dynamic>? ?? [];
    
    return entriesJson.map((json) {
      return BoxIdEntry(
        boxId: json['box_id'] ?? '',
        status: _parseQualityStatus(json['quality_status']),
        scannedAt: DateTime.tryParse(json['scanned_at'] ?? '') ?? DateTime.now(),
        productName: json['product_name'],
        lotNumber: json['lot_number'],
      );
    }).toList();
  }

  /// Obtiene las estadísticas del día actual.
  static Future<DailyStats> getTodayStats() async {
    final today = DateTime.now();
    final response = await ApiService.get(
      '${ApiConfig.shippingStatsEndpoint}/today',
      queryParams: {
        'date': '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      },
    );

    if (!response.success || response.data == null) {
      return DailyStats.empty();
    }

    return DailyStats.fromJson(response.data!);
  }

  /// Convierte string de BD a enum QualityStatus.
  static QualityStatus _parseQualityStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'released':
        return QualityStatus.released;
      case 'pending':
        return QualityStatus.pending;
      case 'rejected':
        return QualityStatus.rejected;
      case 'in_process':
        return QualityStatus.inProcess;
      default:
        return QualityStatus.pending;
    }
  }

  /// Convierte enum QualityStatus a string para BD.
  static String _statusToString(QualityStatus status) {
    switch (status) {
      case QualityStatus.released:
        return 'released';
      case QualityStatus.pending:
        return 'pending';
      case QualityStatus.rejected:
        return 'rejected';
      case QualityStatus.inProcess:
        return 'in_process';
    }
  }
}
