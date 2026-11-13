import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/shipping_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/common_widgets.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  static const _deviceId = 'PDA-TC15';

  final _boxController = TextEditingController();
  final _boxFocusNode = FocusNode();

  ShippingAudit? _audit;
  bool _isLoading = true;
  bool _isStarting = false;
  bool _isScanning = false;
  bool _isClosing = false;

  String get _operatorName {
    final user = AuthService.currentUser;
    return user?.fullName ?? user?.username ?? 'Usuario local';
  }

  @override
  void initState() {
    super.initState();
    _loadActiveAudit();
  }

  @override
  void dispose() {
    _boxController.dispose();
    _boxFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadActiveAudit() async {
    setState(() => _isLoading = true);
    final result = await ShippingService.getActiveAudit();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result.success) {
        _audit = result.audit;
      }
    });

    if (!result.success) {
      _showMessage(result.error ?? 'No se pudo consultar la auditoría activa.');
      return;
    }
    if (_audit?.isOpen == true && AuthService.canScanAudit) {
      _boxFocusNode.requestFocus();
    }
  }

  Future<void> _startAudit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Iniciar auditoría'),
        content: const Text(
          'Se abrirá una nueva auditoría física. Escanea únicamente las cajas que se encuentren en el almacén.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Iniciar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isStarting = true);
    final result = await ShippingService.startAudit(
      startedBy: _operatorName,
      deviceId: _deviceId,
    );
    if (!mounted) return;

    setState(() {
      _isStarting = false;
      if (result.success) {
        _audit = result.audit;
      }
    });
    _showMessage(
      result.success
          ? result.message ?? 'Auditoría iniciada.'
          : result.error ?? 'No se pudo iniciar la auditoría.',
      isError: !result.success,
    );
    if (result.success && AuthService.canScanAudit) {
      _boxFocusNode.requestFocus();
    }
  }

  Future<void> _scanBox(String rawValue) async {
    final audit = _audit;
    final boxCode = rawValue.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (audit == null || !audit.isOpen || _isScanning) return;
    if (boxCode.isEmpty) {
      _showMessage('Captura un Box ID válido.');
      _boxFocusNode.requestFocus();
      return;
    }

    setState(() => _isScanning = true);
    final result = await ShippingService.scanAuditBox(
      auditId: audit.id,
      boxCode: boxCode,
      scannedBy: _operatorName,
    );
    if (!mounted) return;

    setState(() {
      _isScanning = false;
      if (result.success && result.audit != null) {
        _audit = result.audit;
        _boxController.clear();
      }
    });
    _showMessage(
      result.success
          ? '${result.audit?.boxes.isNotEmpty == true ? result.audit!.boxes.first.partNumber : boxCode}: caja registrada.'
          : result.error ?? 'No se pudo registrar el Box ID.',
      isError: !result.success,
    );
    _boxFocusNode.requestFocus();
  }

  Future<void> _closeAudit() async {
    final audit = _audit;
    if (audit == null || !audit.isOpen || audit.totalBoxes == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar auditoría'),
        content: Text(
          'Se cerrará ${audit.auditFolio} con ${audit.totalBoxes} cajas y ${audit.totalQuantity} piezas. Después del cierre ya no se podrán agregar cajas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continuar escaneando'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.darkSuccess,
            ),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Cerrar auditoría'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClosing = true);
    final result = await ShippingService.closeAudit(
      auditId: audit.id,
      closedBy: _operatorName,
    );
    if (!mounted) return;

    setState(() {
      _isClosing = false;
      if (result.success) {
        _audit = null;
        _boxController.clear();
      }
    });
    _showMessage(
      result.success
          ? result.message ?? 'Auditoría cerrada correctamente.'
          : result.error ?? 'No se pudo cerrar la auditoría.',
      isError: !result.success,
    );
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? AppColors.darkError : AppColors.darkSuccess,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Auditoría física'),
            Text(
              'Almacén de Embarques',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : _loadActiveAudit,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadActiveAudit,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_audit == null)
                      _buildEmptyState(context)
                    else
                      _buildActiveAudit(context, _audit!),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No hay una auditoría abierta',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Inicia una auditoría para registrar los Box ID que están físicamente en el almacén.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (AuthService.canManageAudit)
              AppPrimaryButton(
                label: 'Iniciar nueva auditoría',
                icon: Icons.play_arrow_rounded,
                isLoading: _isStarting,
                onPressed: _isStarting ? null : _startAudit,
              )
            else
              Text(
                'Tu usuario puede consultar auditorías, pero no iniciarlas.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAudit(BuildContext context, ShippingAudit audit) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Auditoría en proceso',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            audit.auditFolio,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Chip(
                      avatar:
                          Icon(Icons.radio_button_checked_rounded, size: 16),
                      label: Text('ABIERTA'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AuditMetric(label: 'Cajas', value: '${audit.totalBoxes}'),
                    _AuditMetric(
                        label: 'No. de parte', value: '${audit.totalParts}'),
                    _AuditMetric(
                        label: 'Piezas', value: '${audit.totalQuantity}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (AuthService.canScanAudit) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: AppTextField(
                label: 'Box ID',
                hint: 'Escanea o captura el Box ID',
                prefixIcon: Icons.qr_code_scanner_rounded,
                controller: _boxController,
                focusNode: _boxFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: _scanBox,
                dense: true,
                suffixIcon: _isScanning
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Agregar caja',
                        onPressed: () => _scanBox(_boxController.text),
                        icon: const Icon(Icons.add_rounded),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _AuditBoxesTable(boxes: audit.boxes),
        const SizedBox(height: 16),
        if (AuthService.canManageAudit)
          FilledButton.icon(
            onPressed: audit.totalBoxes > 0 && !_isClosing ? _closeAudit : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.darkSuccess,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: _isClosing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
            label: Text(_isClosing ? 'Cerrando...' : 'Cerrar auditoría'),
          ),
      ],
    );
  }
}

class _AuditMetric extends StatelessWidget {
  final String label;
  final String value;

  const _AuditMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditBoxesTable extends StatelessWidget {
  final List<ShippingAuditBox> boxes;

  const _AuditBoxesTable({required this.boxes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text('Cajas escaneadas', style: theme.textTheme.titleSmall),
          ),
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Row(
              children: [
                _AuditCell('BOX ID', flex: 5, header: true),
                _AuditCell('NO. PARTE', flex: 4, header: true),
                _AuditCell('CANT.', flex: 2, header: true, alignRight: true),
              ],
            ),
          ),
          SizedBox(
            height: 310,
            child: boxes.isEmpty
                ? const Center(child: Text('Aún no hay cajas registradas.'))
                : Scrollbar(
                    child: ListView.separated(
                      itemCount: boxes.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: borderColor,
                      ),
                      itemBuilder: (context, index) {
                        final box = boxes[index];
                        return Row(
                          children: [
                            _AuditCell(box.boxCode, flex: 5, monospace: true),
                            _AuditCell(box.partNumber, flex: 4, bold: true),
                            _AuditCell(
                              '${box.quantity}',
                              flex: 2,
                              alignRight: true,
                            ),
                          ],
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

class _AuditCell extends StatelessWidget {
  final String value;
  final int flex;
  final bool header;
  final bool alignRight;
  final bool monospace;
  final bool bold;

  const _AuditCell(
    this.value, {
    required this.flex,
    this.header = false,
    this.alignRight = false,
    this.monospace = false,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          style:
              (header ? theme.textTheme.labelSmall : theme.textTheme.bodySmall)
                  ?.copyWith(
            fontFamily: monospace ? 'monospace' : null,
            fontWeight: header || bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
