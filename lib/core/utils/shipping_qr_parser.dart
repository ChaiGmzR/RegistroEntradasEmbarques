class ShippingQrData {
  final String rawValue;
  final String partNumber;
  final int quantity;

  const ShippingQrData({
    required this.rawValue,
    required this.partNumber,
    required this.quantity,
  });
}

/// Extrae número de parte y cantidad desde los formatos de QR soportados.
abstract final class ShippingQrParser {
  static final RegExp _partQtyFormat = RegExp(
    r'P\/No\s+([A-Z0-9]+)\b.*?\bQty\s+(\d+)\b',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _ovenFormat = RegExp(
    r'^[^-]+-([A-Z0-9]+)-Oven-(\d+)(?:-|$)',
    caseSensitive: false,
  );

  static ShippingQrData? parse(String rawValue) {
    final normalizedValue = rawValue.trim();
    if (normalizedValue.isEmpty) {
      return null;
    }

    final partQtyMatch = _partQtyFormat.firstMatch(normalizedValue);
    if (partQtyMatch != null) {
      return ShippingQrData(
        rawValue: normalizedValue,
        partNumber: partQtyMatch.group(1)!.toUpperCase(),
        quantity: int.parse(partQtyMatch.group(2)!),
      );
    }

    final ovenMatch = _ovenFormat.firstMatch(normalizedValue);
    if (ovenMatch != null) {
      return ShippingQrData(
        rawValue: normalizedValue,
        partNumber: ovenMatch.group(1)!.toUpperCase(),
        quantity: int.parse(ovenMatch.group(2)!),
      );
    }

    return null;
  }
}
