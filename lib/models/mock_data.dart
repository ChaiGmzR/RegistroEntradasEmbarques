import 'box_id_entry.dart';

/// Datos de ejemplo para el mockup.
class MockData {
  static final List<BoxIdEntry> recentScans = [
    BoxIdEntry(
      boxId: 'BOX-2026-001847',
      status: QualityStatus.released,
      scannedAt: DateTime(2026, 2, 18, 14, 32),
      productName: 'Componente electrónico A',
      lotNumber: 'LOT-2026-0218A',
    ),
    BoxIdEntry(
      boxId: 'BOX-2026-001846',
      status: QualityStatus.released,
      scannedAt: DateTime(2026, 2, 18, 14, 28),
      productName: 'Arnés de cableado B',
      lotNumber: 'LOT-2026-0218B',
    ),
    BoxIdEntry(
      boxId: 'BOX-2026-001845',
      status: QualityStatus.pending,
      scannedAt: DateTime(2026, 2, 18, 14, 15),
      productName: 'Sensor de temperatura C',
      lotNumber: 'LOT-2026-0217C',
    ),
    BoxIdEntry(
      boxId: 'BOX-2026-001844',
      status: QualityStatus.rejected,
      scannedAt: DateTime(2026, 2, 18, 13, 50),
      productName: 'Conector tipo D',
      lotNumber: 'LOT-2026-0217D',
    ),
    BoxIdEntry(
      boxId: 'BOX-2026-001843',
      status: QualityStatus.released,
      scannedAt: DateTime(2026, 2, 18, 13, 42),
      productName: 'Módulo de control E',
      lotNumber: 'LOT-2026-0216E',
    ),
    BoxIdEntry(
      boxId: 'BOX-2026-001842',
      status: QualityStatus.inProcess,
      scannedAt: DateTime(2026, 2, 18, 13, 30),
      productName: 'Placa base F',
      lotNumber: 'LOT-2026-0216F',
    ),
    BoxIdEntry(
      boxId: 'BOX-2026-001841',
      status: QualityStatus.released,
      scannedAt: DateTime(2026, 2, 18, 12, 55),
      productName: 'Resistencia SMD G',
      lotNumber: 'LOT-2026-0215G',
    ),
    BoxIdEntry(
      boxId: 'BOX-2026-001840',
      status: QualityStatus.pending,
      scannedAt: DateTime(2026, 2, 18, 12, 40),
      productName: 'Capacitor cerámico H',
      lotNumber: 'LOT-2026-0215H',
    ),
  ];

  static const Map<String, int> todayStats = {
    'total': 47,
    'released': 38,
    'pending': 5,
    'rejected': 2,
    'inProcess': 2,
  };
}
