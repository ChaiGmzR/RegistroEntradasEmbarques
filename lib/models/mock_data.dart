import 'box_id_entry.dart';

/// Datos de ejemplo para el mockup.
class MockData {
  static final List<BoxIdEntry> recentScans = [
    BoxIdEntry(
      boxId: 'EMB-ENT-2026001',
      status: MovementType.entry,
      scannedAt: DateTime(2026, 2, 18, 14, 32),
      partNumber: 'EBR-001-A',
      quantity: 24,
      detail: 'Ubicación A-01',
      folio: 'EMB-ENT-2026001',
    ),
    BoxIdEntry(
      boxId: 'EMB-RET-2026003',
      status: MovementType.materialReturn,
      scannedAt: DateTime(2026, 2, 18, 14, 15),
      partNumber: 'EBR-003-C',
      quantity: 5,
      detail: 'Retorno a embarques',
      folio: 'EMB-RET-2026003',
    ),
    BoxIdEntry(
      boxId: 'EMB-ENT-2026004',
      status: MovementType.entry,
      scannedAt: DateTime(2026, 2, 18, 13, 50),
      partNumber: 'EBR-004-D',
      quantity: 18,
      detail: 'Ubicación A-04',
      folio: 'EMB-ENT-2026004',
    ),
    BoxIdEntry(
      boxId: 'EMB-ENT-2026006',
      status: MovementType.entry,
      scannedAt: DateTime(2026, 2, 18, 13, 30),
      partNumber: 'EBR-006-F',
      quantity: 36,
      detail: 'Ubicación B-01',
      folio: 'EMB-ENT-2026006',
    ),
    BoxIdEntry(
      boxId: 'EMB-RET-2026008',
      status: MovementType.materialReturn,
      scannedAt: DateTime(2026, 2, 18, 12, 40),
      partNumber: 'EBR-008-H',
      quantity: 3,
      detail: 'Retorno por sobrante',
      folio: 'EMB-RET-2026008',
    ),
  ];

  static const Map<String, int> todayStats = {
    'total': 15,
    'entries': 12,
    'returns': 3,
    'inventoryQuantity': 420,
  };
}
