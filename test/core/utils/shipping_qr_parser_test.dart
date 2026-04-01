import 'package:flutter_test/flutter_test.dart';
import 'package:registro_entradas_embarques/core/utils/shipping_qr_parser.dart';

void main() {
  group('ShippingQrParser', () {
    test('parsea formato P/No ... Qty ...', () {
      const rawValue =
          "P/No EBR80757421 Line R1 Qty 20 Description: PCB Assy' Main Ref ANDREA Day Model QUANTUM-T Apariencia OK Funcionamiento OK 0 0 Contenedor OK RoHS OK";

      final parsed = ShippingQrParser.parse(rawValue);

      expect(parsed, isNotNull);
      expect(parsed!.partNumber, 'EBR80757421');
      expect(parsed.quantity, 20);
      expect(parsed.rawValue, rawValue);
    });

    test('parsea formato prefijo-partNumber-Oven-cantidad', () {
      const rawValue = '3608-EBR43713608-Oven-20-TR0330_021';

      final parsed = ShippingQrParser.parse(rawValue);

      expect(parsed, isNotNull);
      expect(parsed!.partNumber, 'EBR43713608');
      expect(parsed.quantity, 20);
      expect(parsed.rawValue, rawValue);
    });

    test('retorna null cuando el QR no coincide con un formato soportado', () {
      final parsed = ShippingQrParser.parse('codigo-invalido');

      expect(parsed, isNull);
    });
  });
}
