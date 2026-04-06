import '../../models/box_id_entry.dart';
import 'cache_service.dart';
import 'shipping_service.dart';

/// Servicio para actualizaciones optimistas.
class OptimisticUpdateService {
  static final List<PendingOperation> _pendingQueue = [];

  static Future<OptimisticResult> registerMovementOptimistic({
    required String boxId,
    required MovementType status,
    required String scannedBy,
    String? partNumber,
    int? quantity,
    String? rawCode,
    String? productName,
    String? lotNumber,
    String? location,
    String? destinationArea,
    String? notes,
    String? deviceId,
  }) async {
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final entry = BoxIdEntry(
      boxId: boxId,
      status: status,
      scannedAt: DateTime.now(),
      partNumber: partNumber ?? boxId,
      quantity: quantity,
      rawCode: rawCode,
      productName: productName,
      lotNumber: lotNumber,
      detail: _buildDetail(
        status: status,
        quantity: quantity,
        location: location,
        destinationArea: destinationArea,
      ),
      location: location ?? destinationArea,
      notes: notes,
    );

    _addToLocalHistory(entry);

    final operation = PendingOperation(
      id: tempId,
      type: status == MovementType.exit
          ? OperationType.createExit
          : OperationType.createEntry,
      data: {
        'box_id': boxId,
        'movement_type': status.name,
        'scanned_by': scannedBy,
        'part_number': partNumber,
        'quantity': quantity,
        'raw_code': rawCode,
        'product_name': productName,
        'lot_number': lotNumber,
        'location': location,
        'destination_area': destinationArea,
        'notes': notes,
        'device_id': deviceId,
      },
      createdAt: DateTime.now(),
    );
    _pendingQueue.add(operation);
    _syncInBackground(operation);

    return OptimisticResult(
      success: true,
      tempId: tempId,
      entry: entry,
      message: status == MovementType.exit
          ? 'Salida guardada'
          : 'Entrada guardada',
    );
  }

  static Future<OptimisticResult> registerEntryOptimistic({
    required String boxId,
    required String scannedBy,
    String? partNumber,
    int? quantity,
    String? rawCode,
    String? productName,
    String? lotNumber,
    String? location,
    String? notes,
    String? deviceId,
  }) {
    return registerMovementOptimistic(
      boxId: boxId,
      status: MovementType.entry,
      scannedBy: scannedBy,
      partNumber: partNumber,
      quantity: quantity,
      rawCode: rawCode,
      productName: productName,
      lotNumber: lotNumber,
      location: location,
      notes: notes,
      deviceId: deviceId,
    );
  }

  static Future<OptimisticResult> registerExitOptimistic({
    required String boxId,
    required String scannedBy,
    String? partNumber,
    int? quantity,
    String? rawCode,
    String? destinationArea,
    String? notes,
  }) {
    return registerMovementOptimistic(
      boxId: boxId,
      status: MovementType.exit,
      scannedBy: scannedBy,
      partNumber: partNumber,
      quantity: quantity,
      rawCode: rawCode,
      destinationArea: destinationArea,
      notes: notes,
    );
  }

  static Future<void> _syncInBackground(PendingOperation operation) async {
    try {
      final data = operation.data;
      final result = operation.type == OperationType.createExit
          ? await ShippingService.registerExit(
              partNumber: data['part_number'],
              quantity: data['quantity'] ?? 0,
              scannedBy: data['scanned_by'],
              rawCode: data['raw_code'],
              destinationArea: data['destination_area'],
              reason: data['notes'],
              remarks: data['notes'],
            )
          : await ShippingService.registerEntry(
              partNumber: data['part_number'],
              quantity: data['quantity'] ?? 0,
              scannedBy: data['scanned_by'],
              rawCode: data['raw_code'],
              location: data['location'],
              notes: data['notes'],
              deviceId: data['device_id'],
            );

      if (result.success) {
        _pendingQueue.removeWhere((op) => op.id == operation.id);
        operation.synced = true;
      } else {
        operation.retryCount++;
        operation.lastError = result.error;
      }
    } catch (e) {
      operation.retryCount++;
      operation.lastError = e.toString();
    }
  }

  static void _addToLocalHistory(BoxIdEntry entry) {
    final history = CacheService.getHistory() ?? [];
    history.insert(0, entry);
    CacheService.setHistory(history);
    _incrementLocalStats(entry.status);
  }

  static void _incrementLocalStats(MovementType status) {
    final stats = CacheService.getStats()?.cast<String, int>() ??
        {
          'total': 0,
          'entries': 0,
          'exits': 0,
          'returns': 0,
          'inventoryQuantity': 0,
        };

    stats['total'] = (stats['total'] ?? 0) + 1;

    switch (status) {
      case MovementType.entry:
        stats['entries'] = (stats['entries'] ?? 0) + 1;
        break;
      case MovementType.exit:
        stats['exits'] = (stats['exits'] ?? 0) + 1;
        break;
      case MovementType.materialReturn:
        stats['returns'] = (stats['returns'] ?? 0) + 1;
        break;
      case MovementType.adjustment:
        stats['returns'] = (stats['returns'] ?? 0) + 1;
        break;
    }

    CacheService.setStats(stats);
  }

  static String _buildDetail({
    required MovementType status,
    required int? quantity,
    String? location,
    String? destinationArea,
  }) {
    switch (status) {
      case MovementType.entry:
        if (location != null && location.isNotEmpty) {
          return 'Cant: ${quantity ?? 0} • Ubicación: $location';
        }
        return 'Cant: ${quantity ?? 0}';
      case MovementType.exit:
        if (destinationArea != null && destinationArea.isNotEmpty) {
          return 'Cant: ${quantity ?? 0} • Destino: $destinationArea';
        }
        return 'Cant: ${quantity ?? 0}';
      case MovementType.materialReturn:
        return 'Cant: ${quantity ?? 0} • Retorno';
      case MovementType.adjustment:
        return 'Cant: ${quantity ?? 0} • Ajuste';
    }
  }

  static List<PendingOperation> get pendingOperations =>
      _pendingQueue.where((op) => !op.synced).toList();

  static Future<int> syncAllPending() async {
    int synced = 0;
    for (final op in _pendingQueue.where((op) => !op.synced)) {
      await _syncInBackground(op);
      if (op.synced) {
        synced++;
      }
    }
    return synced;
  }

  static void cleanSynced() {
    _pendingQueue.removeWhere((op) => op.synced);
  }
}

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
  createExit,
  updateEntry,
  deleteEntry,
}
