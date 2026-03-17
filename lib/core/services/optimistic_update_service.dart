import '../../models/box_id_entry.dart';
import 'shipping_service.dart';
import 'cache_service.dart';

/// Servicio para actualizaciones optimistas.
/// 
/// Patrón: Mostrar resultado inmediato al usuario y sincronizar
/// con el servidor en background. Si falla, revertir.
class OptimisticUpdateService {
  /// Cola de operaciones pendientes de sincronizar.
  static final List<PendingOperation> _pendingQueue = [];
  
  /// Registra una entrada de forma optimista.
  /// 
  /// 1. Muestra resultado inmediato al usuario
  /// 2. Encola la operación para sincronizar
  /// 3. Sincroniza en background
  /// 4. Si falla, notifica pero no bloquea
  static Future<OptimisticResult> registerEntryOptimistic({
    required String boxId,
    required QualityStatus status,
    required String scannedBy,
    String? productName,
    String? lotNumber,
    String? warehouseZone,
    String? deviceId,
  }) async {
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final entry = BoxIdEntry(
      boxId: boxId,
      status: status,
      scannedAt: DateTime.now(),
      productName: productName,
      lotNumber: lotNumber,
    );

    // 1. Agregar a caché local inmediatamente
    _addToLocalHistory(entry);
    
    // 2. Encolar para sincronización
    final operation = PendingOperation(
      id: tempId,
      type: OperationType.createEntry,
      data: {
        'box_id': boxId,
        'quality_status': status,
        'scanned_by': scannedBy,
        'product_name': productName,
        'lot_number': lotNumber,
        'warehouse_zone': warehouseZone,
        'device_id': deviceId,
      },
      createdAt: DateTime.now(),
    );
    _pendingQueue.add(operation);

    // 3. Intentar sincronizar en background (no bloquea)
    _syncInBackground(operation);

    return OptimisticResult(
      success: true,
      tempId: tempId,
      entry: entry,
      message: 'Registro guardado',
    );
  }

  /// Sincroniza una operación en background.
  static Future<void> _syncInBackground(PendingOperation operation) async {
    try {
      final data = operation.data;
      final result = await ShippingService.registerEntry(
        boxId: data['box_id'],
        status: data['quality_status'],
        scannedBy: data['scanned_by'],
        productName: data['product_name'],
        lotNumber: data['lot_number'],
        warehouseZone: data['warehouse_zone'],
        deviceId: data['device_id'],
      );

      if (result.success) {
        // Éxito: remover de cola
        _pendingQueue.removeWhere((op) => op.id == operation.id);
        operation.synced = true;
      } else {
        // Fallo: marcar para reintento
        operation.retryCount++;
        operation.lastError = result.error;
      }
    } catch (e) {
      operation.retryCount++;
      operation.lastError = e.toString();
    }
  }

  /// Agrega entrada al historial local.
  static void _addToLocalHistory(BoxIdEntry entry) {
    final history = CacheService.get<List<BoxIdEntry>>('history:recent', 'history') ?? [];
    history.insert(0, entry);
    CacheService.set('history:recent', history);
    
    // Actualizar estadísticas locales
    _incrementLocalStats(entry.status);
  }

  /// Incrementa estadísticas locales.
  static void _incrementLocalStats(QualityStatus status) {
    final stats = CacheService.get<Map<String, int>>('stats:today', 'stats') ?? {
      'total': 0,
      'released': 0,
      'pending': 0,
      'rejected': 0,
      'inProcess': 0,
    };
    
    stats['total'] = (stats['total'] ?? 0) + 1;
    
    switch (status) {
      case QualityStatus.released:
        stats['released'] = (stats['released'] ?? 0) + 1;
        break;
      case QualityStatus.pending:
        stats['pending'] = (stats['pending'] ?? 0) + 1;
        break;
      case QualityStatus.rejected:
        stats['rejected'] = (stats['rejected'] ?? 0) + 1;
        break;
      case QualityStatus.inProcess:
        stats['inProcess'] = (stats['inProcess'] ?? 0) + 1;
        break;
    }
    
    CacheService.set('stats:today', stats);
  }

  /// Retorna operaciones pendientes de sincronizar.
  static List<PendingOperation> get pendingOperations => 
      _pendingQueue.where((op) => !op.synced).toList();

  /// Intenta sincronizar todas las operaciones pendientes.
  static Future<int> syncAllPending() async {
    int synced = 0;
    for (final op in _pendingQueue.where((op) => !op.synced)) {
      await _syncInBackground(op);
      if (op.synced) synced++;
    }
    return synced;
  }

  /// Limpia operaciones sincronizadas.
  static void cleanSynced() {
    _pendingQueue.removeWhere((op) => op.synced);
  }
}

/// Resultado de operación optimista.
class OptimisticResult {
  final bool success;
  final int tempId;
  final BoxIdEntry? entry;
  final String? message;
  final String? error;

  OptimisticResult({
    required this.success,
    required this.tempId,
    this.entry,
    this.message,
    this.error,
  });
}

/// Operación pendiente de sincronizar.
class PendingOperation {
  final int id;
  final OperationType type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  bool synced;
  int retryCount;
  String? lastError;

  PendingOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.synced = false,
    this.retryCount = 0,
    this.lastError,
  });
}

enum OperationType {
  createEntry,
  updateEntry,
  deleteEntry,
}
