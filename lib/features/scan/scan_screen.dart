import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/optimistic_update_service.dart';
import '../../core/utils/shipping_qr_parser.dart';
import '../../models/box_id_entry.dart';
import '../../shared/widgets/common_widgets.dart';

/// Argumentos para la pantalla de resultado de escaneo.
class ScanResultArguments {
  final String boxId;
  final QualityStatus status;
  final DateTime scannedAt;
  final String? partNumber;
  final int? quantity;
  final String? rawCode;
  final String? productName;
  final String? lotNumber;
  final bool skipQualityValidation;

  const ScanResultArguments({
    required this.boxId,
    required this.status,
    required this.scannedAt,
    this.partNumber,
    this.quantity,
    this.rawCode,
    this.productName,
    this.lotNumber,
    this.skipQualityValidation = false,
  });
}

/// Pantalla de escaneo de QR.
/// Permite ingresar o escanear el código de embarque manualmente.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _manualController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  void _submitScan(String boxId) {
    _processScan(boxId);
  }

  /// Procesa un escaneo real o simulado.
  Future<void> _processScan(String rawScan) async {
    final parsedQr = ShippingQrParser.parse(rawScan);
    if (parsedQr == null) {
      _showInvalidQrMessage();
      return;
    }

    setState(() => _isProcessing = true);

    try {
      if (AuthService.useMockData) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      const status = QualityStatus.released;
      final scannedAt = DateTime.now();
      final partNumber = parsedQr.partNumber;
      final quantity = parsedQr.quantity;
      final rawCode = parsedQr.rawValue;

      // Registrar entrada de forma optimista (instantánea)
      final user = AuthService.currentUser;
      await OptimisticUpdateService.registerEntryOptimistic(
        boxId: partNumber,
        status: status,
        scannedBy: user?.id ?? 'unknown',
        partNumber: partNumber,
        quantity: quantity,
        rawCode: rawCode,
        lotNumber: 'QTY:$quantity',
        notes: 'QR: $rawCode | Qty: $quantity',
        deviceId: 'PDA-TC15',
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Navegar al resultado
      Navigator.pushNamed(
        context,
        AppConstants.scanResultRoute,
        arguments: ScanResultArguments(
          boxId: partNumber,
          status: status,
          scannedAt: scannedAt,
          partNumber: partNumber,
          quantity: quantity,
          rawCode: rawCode,
          skipQualityValidation: true,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Mostrar error pero no bloquear
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al procesar: $e'),
          backgroundColor: AppColors.darkError,
        ),
      );
    }
  }

  void _showInvalidQrMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'QR no reconocido. Usa un formato "P/No ... Qty ..." o "...-Oven-cantidad-...".',
        ),
        backgroundColor: AppColors.darkError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR'),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Entrada de Box ID ──
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 56,
                    color: isDark
                        ? AppColors.darkPrimary.withValues(alpha: 0.6)
                        : AppColors.lightPrimary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Escanear PDA',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ingresa o escanea el QR de embarque',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  AppTextField(
                    label: 'QR',
                    hint: 'Ej: P/No EBR... Qty 20 o 3608-EBR...-Oven-20-...',
                    prefixIcon: Icons.inventory_2_outlined,
                    controller: _manualController,
                    keyboardType: TextInputType.text,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  AppPrimaryButton(
                    label: 'Procesar QR',
                    icon: Icons.search_rounded,
                    onPressed: () {
                      if (_manualController.text.isNotEmpty) {
                        _submitScan(_manualController.text);
                      }
                    },
                  ),
                ],
              ),
            ),

            // ── Estado ──
            if (_isProcessing) ...[
              LinearProgressIndicator(
                borderRadius: BorderRadius.circular(4),
                color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                backgroundColor: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.lightSurfaceSecondary,
              ),
              const SizedBox(height: 10),
              Text(
                'Procesando QR...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppColors.darkInfo : AppColors.lightInfo,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
