import 'dart:async';

import '../../models/box_id_entry.dart';
import 'cache_service.dart';
import 'shipping_service.dart';

/// Servicio para actualizaciones optimistas.
class OptimisticUpdateService {
  static final List<PendingOperation> _pendingQueue = [];
  static final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();

  static Stream<int> get pendingCountStream => _pendingCountController.stream;

  static void _emitPendingCount() {
    if (_pendingCountController.isClosed) {
      return;
    }
    _pendingCountController.add(pendingOperations.length);
  }

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
    final scannedAt = DateTime.now();
    final entry = BoxIdEntry(
      boxId: boxId,
      status: status,
      scannedAt: scannedAt,
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
      entrySnapshot: entry,
    );

    final syncResult = await _executeOperation(operation);
    if (syncResult.success) {
      _addToLocalHistory(entry);
      return OptimisticResult(
        success: true,
        tempId: tempId,
        entry: entry,
        message: syncResult.message ??
            (status == MovementType.exit
                ? 'Salida registrada'
                : 'Entrada registrada'),
      );
    }

    if (!syncResult.isConnectionError) {
      return OptimisticResult(
        success: false,
        tempId: tempId,
        error: syncResult.error ??
            (status == MovementType.exit
                ? 'No se pudo registrar la salida'
                : 'No se pudo registrar la entrada'),
      );
    }

    _addToLocalHistory(entry);
    _pendingQueue.add(operation);
    _emitPendingCount();

    return OptimisticResult(
      success: true,
      tempId: tempId,
      entry: entry,
      message: status == MovementType.exit
          ? 'Salida guardada sin conexión. Pendiente de sincronizar.'
          : 'Entrada guardada sin conexión. Pendiente de sincronizar.',
      queuedForSync: true,
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
      final result = await _executeOperation(operation);

      if (result.success) {
        _pendingQueue.removeWhere((op) => op.id == operation.id);
        operation.synced = true;
        _emitPendingCount();
        return;
      }

      operation.retryCount++;
      operation.lastError = result.error;

      if (!result.isConnectionError) {
        _removePendingOperation(operation, removeLocalEntry: true);
      }
    } catch (e) {
      operation.retryCount++;
      operation.lastError = e.toString();
    }
  }

  static Future<RegisterMovementResult> _executeOperation(
    PendingOperation operation,
  ) {
    final data = operation.data;
    return operation.type == OperationType.createExit
        ? ShippingService.registerExit(
            partNumber: data['part_number'],
            quantity: data['quantity'] ?? 0,
            scannedBy: data['scanned_by'],
            rawCode: data['raw_code'],
            destinationArea: data['destination_area'],
            reason: data['notes'],
            remarks: data['notes'],
          )
        : ShippingService.registerEntry(
            partNumber: data['part_number'],
            quantity: data['quantity'] ?? 0,
            scannedBy: data['scanned_by'],
            rawCode: data['raw_code'],
            location: data['location'],
            notes: data['notes'],
            deviceId: data['device_id'],
          );
  }

  static void _addToLocalHistory(BoxIdEntry entry) {
    final history = CacheService.getHistory() ?? [];
    history.insert(0, entry);
    CacheService.setHistory(history);
    _incrementLocalStats(entry.status);
  }

  static void _removeFromLocalHistory(BoxIdEntry entry) {
    final history = CacheService.getHistory() ?? [];
    final index = history.indexWhere(
      (item) =>
          item.boxId == entry.boxId &&
          item.partNumber == entry.partNumber &&
          item.quantity == entry.quantity &&
          item.rawCode == entry.rawCode &&
          item.scannedAt == entry.scannedAt,
    );

    if (index < 0) {
      return;
    }

    history.removeAt(index);
    CacheService.setHistory(history);
    _decrementLocalStats(entry.status);
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

  static void _decrementLocalStats(MovementType status) {
    final stats = CacheService.getStats()?.cast<String, int>() ??
        {
          'total': 0,
          'entries': 0,
          'exits': 0,
          'returns': 0,
          'inventoryQuantity': 0,
        };

    stats['total'] = ((stats['total'] ?? 0) - 1).clamp(0, 1 << 31);

    switch (status) {
      case MovementType.entry:
        stats['entries'] = ((stats['entries'] ?? 0) - 1).clamp(0, 1 << 31);
        break;
      case MovementType.exit:
        stats['exits'] = ((stats['exits'] ?? 0) - 1).clamp(0, 1 << 31);
        break;
      case MovementType.materialReturn:
        stats['returns'] = ((stats['returns'] ?? 0) - 1).clamp(0, 1 << 31);
        break;
      case MovementType.adjustment:
        stats['returns'] = ((stats['returns'] ?? 0) - 1).clamp(0, 1 << 31);
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
    final pending = _pendingQueue.where((op) => !op.synced).toList();
    for (final op in pending) {
      await _syncInBackground(op);
      if (op.synced) {
        synced++;
      }
    }
    _emitPendingCount();
    return synced;
  }

  static void cleanSynced() {
    _pendingQueue.removeWhere((op) => op.synced);
    _emitPendingCount();
  }

  static void _removePendingOperation(
    PendingOperation operation, {
    bool removeLocalEntry = false,
  }) {
    _pendingQueue.removeWhere((op) => op.id == operation.id);
    if (removeLocalEntry) {
      _removeFromLocalHistory(operation.entrySnapshot);
    }
    _emitPendingCount();
  }
}

class OptimisticResult {
  final bool success;
  final int tempId;
  final BoxIdEntry? entry;
  final String? message;
  final String? error;
  final bool queuedForSync;

  OptimisticResult({
    required this.success,
    required this.tempId,
    this.entry,
    this.message,
    this.error,
    this.queuedForSync = false,
  });
}

class PendingOperation {
  final int id;
  final OperationType type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final BoxIdEntry entrySnapshot;
  bool synced;
  int retryCount;
  String? lastError;

  PendingOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    required this.entrySnapshot,
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
