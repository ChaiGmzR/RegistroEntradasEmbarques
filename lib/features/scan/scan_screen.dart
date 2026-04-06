import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/optimistic_update_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/shipping_qr_parser.dart';
import '../../models/box_id_entry.dart';
import '../../shared/widgets/common_widgets.dart';

class ScanResultArguments {
  final String boxId;
  final MovementType status;
  final DateTime scannedAt;
  final String? partNumber;
  final int? quantity;
  final String? rawCode;
  final String? detail;
  final String? notes;

  const ScanResultArguments({
    required this.boxId,
    required this.status,
    required this.scannedAt,
    this.partNumber,
    this.quantity,
    this.rawCode,
    this.detail,
    this.notes,
  });
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: _EntryScanAppBar(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: EntryScanForm(),
        ),
      ),
    );
  }
}

class EntryScanForm extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onRegistered;

  const EntryScanForm({
    super.key,
    this.embedded = false,
    this.onRegistered,
  });

  @override
  State<EntryScanForm> createState() => _EntryScanFormState();
}

class _EntryScanFormState extends State<EntryScanForm> {
  final _manualController = TextEditingController();
  final _quantityController = TextEditingController();
  final _qrFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();
  bool _isProcessing = false;
  Timer? _normalizeTimer;

  @override
  void dispose() {
    _normalizeTimer?.cancel();
    _manualController.dispose();
    _quantityController.dispose();
    _qrFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _submitScan(String boxId) {
    _processScan(boxId);
  }

  Future<void> _processScan(String rawScan) async {
    final parsedQr = ShippingQrParser.parse(rawScan);
    if (parsedQr == null) {
      _showInvalidQrMessage();
      return;
    }

    final quantityValue = int.tryParse(_quantityController.text.trim());
    if (quantityValue == null || quantityValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Captura una cantidad valida antes de registrar.'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final scannedAt = DateTime.now();
      final partNumber = parsedQr.partNumber;
      final quantity = quantityValue;
      final rawCode = parsedQr.rawValue;
      final user = AuthService.currentUser;
      final operatorName = user?.fullName ?? user?.username ?? 'Usuario local';

      final result = await OptimisticUpdateService.registerEntryOptimistic(
        boxId: partNumber,
        scannedBy: operatorName,
        partNumber: partNumber,
        quantity: quantity,
        rawCode: rawCode,
        lotNumber: parsedQr.quantity != null ? 'QR-QTY:${parsedQr.quantity}' : null,
        notes: 'QR: $rawCode | Qty registrada: $quantity',
        deviceId: 'PDA-TC15',
      );

      if (!mounted) {
        return;
      }

      setState(() => _isProcessing = false);
      widget.onRegistered?.call();

      Navigator.pushNamed(
        context,
        AppConstants.scanResultRoute,
        arguments: ScanResultArguments(
          boxId: partNumber,
          status: MovementType.entry,
          scannedAt: scannedAt,
          partNumber: partNumber,
          quantity: quantity,
          rawCode: rawCode,
          detail: result.entry?.detail,
          notes: result.message,
        ),
      );
      _manualController.clear();
      _quantityController.clear();
      _qrFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isProcessing = false);

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
          'QR no reconocido. Usa un formato valido que incluya el numero de parte.',
        ),
        backgroundColor: AppColors.darkError,
      ),
    );
  }

  void _handleQrChanged(String value) {
    _normalizeTimer?.cancel();
    _normalizeTimer = Timer(const Duration(milliseconds: 180), () {
      final parsed = ShippingQrParser.parse(value);
      if (parsed == null) {
        return;
      }

      final normalizedPart = parsed.partNumber;
      if (_manualController.text != normalizedPart) {
        _manualController.value = TextEditingValue(
          text: normalizedPart,
          selection: TextSelection.collapsed(offset: normalizedPart.length),
        );
      }

      if (!_quantityFocusNode.hasFocus) {
        _quantityFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          Icon(
            MovementType.entry.icon,
            size: 56,
            color: MovementType.entry.color(context).withValues(alpha: 0.8),
          ),
          const SizedBox(height: 20),
          Text(
            'Registrar entrada',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Escanea el QR del material para ingresarlo al inventario.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
        AppTextField(
          label: 'QR',
          hint: 'Ej: P/No EBR... o 3608-EBR...-Oven-...',
          prefixIcon: Icons.inventory_2_outlined,
          controller: _manualController,
          focusNode: _qrFocusNode,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          maxLines: 4,
          minLines: 1,
          autofocus: true,
          onChanged: _handleQrChanged,
        ),
        const SizedBox(height: 12),
        AppTextField(
          label: 'Cantidad',
          hint: 'Ej: 20',
          prefixIcon: Icons.numbers_rounded,
          controller: _quantityController,
          focusNode: _quantityFocusNode,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          label: 'Registrar entrada',
          icon: MovementType.entry.icon,
          onPressed: () {
            if (_manualController.text.isNotEmpty) {
              _submitScan(_manualController.text);
            }
          },
        ),
        if (_isProcessing) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            borderRadius: BorderRadius.circular(4),
            color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
            backgroundColor: isDark
                ? AppColors.darkSurfaceElevated
                : AppColors.lightSurfaceSecondary,
          ),
          const SizedBox(height: 10),
          Text(
            'Registrando entrada...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkInfo : AppColors.lightInfo,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (widget.embedded) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: content,
      ),
    );
  }
}

class _EntryScanAppBar extends StatelessWidget {
  const _EntryScanAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Registrar Entrada'),
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            )
          : null,
    );
  }
}
