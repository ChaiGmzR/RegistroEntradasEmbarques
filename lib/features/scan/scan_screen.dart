import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/shipping_service.dart';
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
  final bool autoClose;
  final bool compactDetailView;

  const ScanResultArguments({
    required this.boxId,
    required this.status,
    required this.scannedAt,
    this.partNumber,
    this.quantity,
    this.rawCode,
    this.detail,
    this.notes,
    this.autoClose = false,
    this.compactDetailView = false,
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

enum _EntryCaptureMode {
  boxId,
  quantity,
}

class _EntryScanFormState extends State<EntryScanForm> {
  static const _qrScanSettleDelay = Duration(milliseconds: 850);

  final _manualController = TextEditingController();
  final _boxIdController = TextEditingController();
  final _quantityController = TextEditingController();
  final _qrFocusNode = FocusNode();
  final _boxIdFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();
  final List<OqcBoxInfo> _scannedBoxes = [];
  String? _expectedPartNumber;
  String? _currentLabelPartNumber;
  _EntryCaptureMode _captureMode = _EntryCaptureMode.boxId;
  bool _isProcessing = false;
  bool _isValidatingBox = false;
  Timer? _normalizeTimer;

  @override
  void dispose() {
    _normalizeTimer?.cancel();
    _manualController.dispose();
    _boxIdController.dispose();
    _quantityController.dispose();
    _qrFocusNode.dispose();
    _boxIdFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _submitBoxId(String boxId) {
    _validateAndAddBox(boxId);
  }

  Future<void> _validateAndAddBox(String rawBoxCode) async {
    final parsedQr = ShippingQrParser.parse(_manualController.text);
    if (parsedQr == null) {
      _showMessage('Escanea primero el QR de etiqueta.');
      _qrFocusNode.requestFocus();
      return;
    }

    final labelPartNumber = parsedQr.partNumber;
    if (!_requiresBoxId(labelPartNumber)) {
      _showMessage('Este número de parte se registra por cantidad.');
      _quantityFocusNode.requestFocus();
      return;
    }

    final requiredPartNumber = _expectedPartNumber ?? labelPartNumber;
    if (labelPartNumber != requiredPartNumber) {
      _showMessage(
        'El QR pertenece a $labelPartNumber; el lote requiere $requiredPartNumber.',
      );
      _qrFocusNode.requestFocus();
      return;
    }

    final boxCode = _normalizeBoxCode(rawBoxCode);
    if (boxCode.isEmpty) {
      _showMessage('Captura un Box ID valido.');
      return;
    }

    if (_scannedBoxes.any((box) => box.boxCode == boxCode)) {
      _showMessage('Este Box ID ya está en la lista.');
      return;
    }

    setState(() => _isValidatingBox = true);

    try {
      final result = await ShippingService.getOqcBoxStatus(boxCode);

      if (!mounted) {
        return;
      }

      if (!result.success || result.box == null) {
        setState(() => _isValidatingBox = false);
        _showMessage(result.error ?? 'No se pudo validar el Box ID.');
        return;
      }

      final box = result.box!;
      if (box.entered) {
        setState(() => _isValidatingBox = false);
        _showMessage(
          'El Box ID ya tiene entrada registrada${box.entryFolio == null ? '' : ' (${box.entryFolio})'}.',
          isError: true,
        );
        return;
      }

      if (box.partNumber.isEmpty || box.quantity <= 0) {
        setState(() => _isValidatingBox = false);
        _showMessage('El Box ID no tiene número de parte o cantidad válida.');
        return;
      }

      if (box.partNumber != labelPartNumber) {
        setState(() => _isValidatingBox = false);
        _showMessage(
          'La caja pertenece a ${box.partNumber}; el QR escaneado es $labelPartNumber.',
          isError: true,
        );
        return;
      }

      setState(() {
        _scannedBoxes.add(box);
        _isValidatingBox = false;
        _expectedPartNumber = requiredPartNumber;
        _currentLabelPartNumber = null;
        _captureMode = _EntryCaptureMode.boxId;
      });

      _manualController.clear();
      _boxIdController.clear();
      _qrFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isValidatingBox = false);
      _showMessage('Error al validar Box ID: $e');
    }
  }

  Future<void> _registerEntry() async {
    if (_captureMode == _EntryCaptureMode.quantity && _scannedBoxes.isEmpty) {
      await _registerQuantityEntry();
      return;
    }
    await _registerEntryBatch();
  }

  Future<void> _registerEntryBatch() async {
    if (_scannedBoxes.isEmpty) {
      _showMessage('Escanea al menos un Box ID antes de registrar.');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final user = AuthService.currentUser;
      final operatorName = user?.fullName ?? user?.username ?? 'Usuario local';

      final result = await ShippingService.registerEntryBoxes(
        boxCodes: _scannedBoxes.map((box) => box.boxCode).toList(),
        scannedBy: operatorName,
        expectedPartNumber: _expectedPartNumber ?? _firstScannedPartNumber,
        rawQr: _manualController.text.trim().isEmpty
            ? null
            : _manualController.text.trim(),
        notes:
            'Cajas OQC: ${_scannedBoxes.map((box) => '${box.boxCode}:${box.quantity}').join(', ')}',
        deviceId: 'PDA-TC15',
      );

      if (!mounted) {
        return;
      }

      setState(() => _isProcessing = false);
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ?? 'No se pudo registrar la entrada.',
            ),
            backgroundColor: AppColors.darkError,
          ),
        );
        return;
      }

      widget.onRegistered?.call();
      _manualController.clear();
      _boxIdController.clear();
      setState(() {
        _scannedBoxes.clear();
        _expectedPartNumber = null;
        _currentLabelPartNumber = null;
        _captureMode = _EntryCaptureMode.boxId;
      });
      FocusScope.of(context).unfocus();
      await _showSuccessOverlay(
        message: result.message,
      );
      if (!mounted) {
        return;
      }
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

  Future<void> _registerQuantityEntry() async {
    final parsedQr = ShippingQrParser.parse(_manualController.text);
    final partNumber = parsedQr?.partNumber ?? _currentLabelPartNumber;
    final quantity = int.tryParse(_quantityController.text.trim());

    if (partNumber == null || partNumber.isEmpty) {
      _showMessage('Escanea primero el QR de etiqueta.');
      _qrFocusNode.requestFocus();
      return;
    }

    if (_requiresBoxId(partNumber)) {
      _showMessage('Este número de parte requiere registro con Box ID.');
      _boxIdFocusNode.requestFocus();
      return;
    }

    if (quantity == null || quantity <= 0) {
      _showMessage('Captura una cantidad válida antes de registrar.');
      _quantityFocusNode.requestFocus();
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final user = AuthService.currentUser;
      final operatorName = user?.fullName ?? user?.username ?? 'Usuario local';
      final result = await ShippingService.registerEntry(
        partNumber: partNumber,
        quantity: quantity,
        scannedBy: operatorName,
        rawCode: parsedQr?.rawValue ?? _manualController.text.trim(),
        notes: 'Entrada por cantidad desde PDA',
        deviceId: 'PDA-TC15',
      );

      if (!mounted) {
        return;
      }

      setState(() => _isProcessing = false);
      if (!result.success) {
        _showMessage(result.error ?? 'No se pudo registrar la entrada.');
        return;
      }

      widget.onRegistered?.call();
      _manualController.clear();
      _quantityController.clear();
      setState(() {
        _expectedPartNumber = null;
        _currentLabelPartNumber = null;
        _captureMode = _EntryCaptureMode.boxId;
      });
      FocusScope.of(context).unfocus();
      await _showSuccessOverlay(message: result.message);
      if (!mounted) {
        return;
      }
      _qrFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isProcessing = false);
      _showMessage('Error al procesar: $e');
    }
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.darkError : AppColors.darkSuccess,
      ),
    );
  }

  void _handleQrChanged(String value) {
    _normalizeTimer?.cancel();

    if (_isDirectPartScan(value)) {
      _applyQrValue(value);
      return;
    }

    _normalizeTimer = Timer(_qrScanSettleDelay, () {
      _applyQrValue(_manualController.text);
    });
  }

  void _submitQr(String value) {
    _normalizeTimer?.cancel();
    if (_isIncompleteQrPrefix(value)) {
      _normalizeTimer = Timer(_qrScanSettleDelay, () {
        _applyQrValue(_manualController.text);
      });
      return;
    }
    _applyQrValue(value);
  }

  void _applyQrValue(String value) {
    if (!mounted) {
      return;
    }

    if (value.trim().isEmpty) {
      setState(() {
        _currentLabelPartNumber = null;
        if (_scannedBoxes.isEmpty) {
          _expectedPartNumber = null;
          _captureMode = _EntryCaptureMode.boxId;
        }
      });
      return;
    }

    if (_isIncompleteQrPrefix(value)) {
      return;
    }

    final parsed = ShippingQrParser.parse(value);
    if (parsed == null) {
      return;
    }

    final normalizedPart = parsed.partNumber;
    final requiresBoxId = _requiresBoxId(normalizedPart);
    final requiredPartNumber = _scannedBoxes.isEmpty
        ? null
        : (_expectedPartNumber ?? _firstScannedPartNumber);

    if (requiredPartNumber != null && requiredPartNumber != normalizedPart) {
      _showMessage(
        'El QR pertenece a $normalizedPart; las cajas escaneadas son $requiredPartNumber.',
      );
      return;
    }

    if (_manualController.text != normalizedPart) {
      _manualController.value = TextEditingValue(
        text: normalizedPart,
        selection: TextSelection.collapsed(offset: normalizedPart.length),
      );
    }

    setState(() {
      _currentLabelPartNumber = normalizedPart;
      _captureMode =
          requiresBoxId ? _EntryCaptureMode.boxId : _EntryCaptureMode.quantity;
      if (requiresBoxId) {
        _expectedPartNumber = normalizedPart;
        _quantityController.clear();
      } else {
        _expectedPartNumber = null;
        _scannedBoxes.clear();
        _boxIdController.clear();
      }
    });

    if (requiresBoxId) {
      _boxIdFocusNode.requestFocus();
    } else {
      _quantityFocusNode.requestFocus();
    }
  }

  bool _isIncompleteQrPrefix(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return RegExp(r'^P[/-]?NO$').hasMatch(normalized) ||
        RegExp(r'^P[/-]?NO[A-Z0-9]{0,4}$').hasMatch(normalized);
  }

  bool _isDirectPartScan(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (RegExp(r'^P[/-]?NO').hasMatch(normalized)) {
      return false;
    }
    return RegExp(r'^(?:E?EBR\d{8}|[A-Z]{3}\d{8})$').hasMatch(normalized);
  }

  void _resetScanFlow() {
    _normalizeTimer?.cancel();
    _manualController.clear();
    _boxIdController.clear();
    _quantityController.clear();
    setState(() {
      _scannedBoxes.clear();
      _expectedPartNumber = null;
      _currentLabelPartNumber = null;
      _captureMode = _EntryCaptureMode.boxId;
      _isValidatingBox = false;
    });
    _qrFocusNode.requestFocus();
  }

  String _normalizeBoxCode(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').trim().toUpperCase();
  }

  int get _totalQuantity =>
      _scannedBoxes.fold(0, (total, box) => total + box.quantity);

  String? get _firstScannedPartNumber =>
      _scannedBoxes.isEmpty ? null : _scannedBoxes.first.partNumber;

  bool get _canRegister {
    if (_isProcessing || _isValidatingBox) {
      return false;
    }
    if (_captureMode == _EntryCaptureMode.quantity && _scannedBoxes.isEmpty) {
      final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
      return (_currentLabelPartNumber?.isNotEmpty ?? false) && quantity > 0;
    }
    return _scannedBoxes.isNotEmpty;
  }

  bool _requiresBoxId(String partNumber) {
    return partNumber.trim().toUpperCase().startsWith('EBR');
  }

  Future<void> _showSuccessOverlay({
    String? message,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (navigator.mounted && navigator.canPop()) {
          navigator.pop();
        }
      }),
    );

    final statusColor = MovementType.entry.color(context);
    final statusSoftColor = MovementType.entry.softColor(context);
    const title = 'ENTRADA REGISTRADA';
    final subtitle = message ??
        'Las cajas fueron agregadas correctamente al inventario compartido.';

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'registro_exitoso',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: statusSoftColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.32),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            MovementType.entry.icon,
                            size: 48,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          style: Theme.of(dialogContext)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: Theme.of(dialogContext)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: statusColor.withValues(alpha: 0.88),
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final isReverse = animation.status == AnimationStatus.reverse;
            final progress = isReverse ? 1 - animation.value : animation.value;
            final fade = isReverse
                ? 1 - Curves.easeInQuad.transform(progress)
                : Curves.easeOutCubic.transform(progress);
            final scale = isReverse
                ? 1.0 +
                    (0.08 * Curves.easeOut.transform(progress)) -
                    (0.22 * Curves.easeInBack.transform(progress))
                : 0.96 + (0.04 * Curves.easeOutBack.transform(progress));

            return FadeTransition(
              opacity: AlwaysStoppedAnimation(fade.clamp(0.0, 1.0)),
              child: Transform.scale(
                scale: scale.clamp(0.78, 1.04),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (isReverse)
                      _BurstBubbles(
                        progress: progress,
                        color: statusColor,
                      ),
                    child ?? const SizedBox.shrink(),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final clearButton = Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _isProcessing ? null : _resetScanFlow,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Limpiar'),
      ),
    );
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
          clearButton,
          const SizedBox(height: 8),
        ],
        AppTextField(
          label: 'QR',
          hint: 'ingrese QR de etiqueta',
          prefixIcon: Icons.inventory_2_outlined,
          controller: _manualController,
          focusNode: _qrFocusNode,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          onChanged: _handleQrChanged,
          onFieldSubmitted: _submitQr,
          dense: true,
        ),
        const SizedBox(height: 8),
        if (_captureMode == _EntryCaptureMode.quantity &&
            _scannedBoxes.isEmpty) ...[
          AppTextField(
            label: 'Cantidad',
            hint: 'Cantidad',
            prefixIcon: Icons.numbers_rounded,
            controller: _quantityController,
            focusNode: _quantityFocusNode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) => _registerEntry(),
            dense: true,
          ),
          const SizedBox(height: 10),
        ] else ...[
          AppTextField(
            label: 'Box ID',
            hint: 'Box ID',
            prefixIcon: Icons.view_week_rounded,
            controller: _boxIdController,
            focusNode: _boxIdFocusNode,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: _submitBoxId,
            dense: true,
            suffixIcon: _isValidatingBox
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () => _submitBoxId(_boxIdController.text),
                  ),
          ),
          const SizedBox(height: 8),
          _BoxAccumulatorTable(
            boxes: _scannedBoxes,
            onRemove: (boxCode) {
              setState(() {
                _scannedBoxes.removeWhere((box) => box.boxCode == boxCode);
                _expectedPartNumber = _firstScannedPartNumber;
                if (_scannedBoxes.isEmpty) {
                  _currentLabelPartNumber = null;
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Cantidad total: $_totalQuantity ea',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.darkPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        AppPrimaryButton(
          label: 'Registrar entrada',
          icon: MovementType.entry.icon,
          isLoading: _isProcessing,
          onPressed: _canRegister ? _registerEntry : null,
        ),
        if (_isValidatingBox && !_isProcessing) ...[
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
            'Validando Box ID...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkInfo : AppColors.lightInfo,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Registrar entrada', style: theme.textTheme.titleSmall),
              clearButton,
            ],
          ),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: content,
            ),
          ),
        ],
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

class _BoxAccumulatorTable extends StatelessWidget {
  final List<OqcBoxInfo> boxes;
  final ValueChanged<String> onRemove;

  const _BoxAccumulatorTable({
    required this.boxes,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final headerColor = isDark
        ? AppColors.darkSurfaceElevated
        : AppColors.lightSurfaceSecondary;
    final rowColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final altRowColor = isDark
        ? AppColors.darkSurfaceElevated.withValues(alpha: 0.45)
        : AppColors.lightSurfaceSecondary.withValues(alpha: 0.72);
    final textColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      height: 142,
      decoration: BoxDecoration(
        color: rowColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: headerColor,
            child: Row(
              children: [
                _TableHeaderCell('BOX ID', flex: 6, borderColor: borderColor),
                _TableHeaderCell('NO. PARTE',
                    flex: 4, borderColor: borderColor),
                _TableHeaderCell(
                  'CANTIDAD',
                  flex: 3,
                  borderColor: borderColor,
                  isLast: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: boxes.isEmpty
                ? Center(
                    child: Text(
                      'Escanea Box ID liberados por OQC',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: boxes.length > 4,
                    child: ListView.builder(
                      itemCount: boxes.length,
                      itemBuilder: (context, index) {
                        final box = boxes[index];
                        return InkWell(
                          onLongPress: () => onRemove(box.boxCode),
                          child: Container(
                            color: index.isEven ? rowColor : altRowColor,
                            child: Row(
                              children: [
                                _TableBodyCell(
                                  box.boxCode,
                                  flex: 6,
                                  borderColor: borderColor,
                                  monospace: true,
                                ),
                                _TableBodyCell(
                                  box.partNumber,
                                  flex: 4,
                                  borderColor: borderColor,
                                  monospace: true,
                                  bold: true,
                                ),
                                _TableBodyCell(
                                  box.quantity.toString(),
                                  flex: 3,
                                  borderColor: borderColor,
                                  isLast: true,
                                  alignRight: true,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final Color borderColor;
  final bool isLast;

  const _TableHeaderCell(
    this.label, {
    required this.flex,
    required this.borderColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            right: isLast ? BorderSide.none : BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TableBodyCell extends StatelessWidget {
  final String value;
  final int flex;
  final Color borderColor;
  final bool isLast;
  final bool alignRight;
  final bool monospace;
  final bool bold;

  const _TableBodyCell(
    this.value, {
    required this.flex,
    required this.borderColor,
    this.isLast = false,
    this.alignRight = false,
    this.monospace = false,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 26,
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            right: isLast ? BorderSide.none : BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontFamily: monospace ? 'monospace' : null,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _BurstBubbles extends StatelessWidget {
  final double progress;
  final Color color;

  const _BurstBubbles({
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final burstProgress =
        Curves.easeOutExpo.transform(progress.clamp(0.0, 1.0));
    final fade = 1 - Curves.easeIn.transform(progress.clamp(0.0, 1.0));
    const angles = <double>[
      -1.85,
      -1.2,
      -0.55,
      -0.12,
      0.42,
      0.95,
      1.52,
      2.18,
      2.78,
    ];

    return IgnorePointer(
      child: SizedBox(
        width: 340,
        height: 240,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < angles.length; i++)
              _BurstBubbleParticle(
                angle: angles[i],
                distance: 36 + (92 * burstProgress) + ((i % 3) * 8),
                size: (i % 2 == 0 ? 18.0 : 12.0) * (1 - (0.72 * progress)),
                opacity: fade * (i.isEven ? 0.28 : 0.18),
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}

class _BurstBubbleParticle extends StatelessWidget {
  final double angle;
  final double distance;
  final double size;
  final double opacity;
  final Color color;

  const _BurstBubbleParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.opacity,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dx = math.cos(angle) * distance;
    final dy = math.sin(angle) * distance;

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Container(
        width: size.clamp(2.0, 18.0),
        height: size.clamp(2.0, 18.0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
          border: Border.all(
            color: color.withValues(
              alpha: (opacity * 1.35).clamp(0.0, 1.0),
            ),
            width: 1.2,
          ),
        ),
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
