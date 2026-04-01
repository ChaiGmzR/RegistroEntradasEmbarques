import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/box_id_entry.dart';
import '../../shared/widgets/common_widgets.dart';
import 'scan_screen.dart';

/// Pantalla de resultado de escaneo (Mockup).
/// Muestra el estado de calidad del Box ID escaneado.
class ScanResultScreen extends StatelessWidget {
  final ScanResultArguments? arguments;

  const ScanResultScreen({super.key, this.arguments});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final args = arguments ??
        ScanResultArguments(
          boxId: 'BOX-XXXX-XXXXXX',
          status: QualityStatus.released,
          scannedAt: DateTime(2026, 2, 18, 14, 32),
        );

    final status = args.status;
    final isCaptureMode = args.skipQualityValidation;
    final statusColor = isCaptureMode
        ? (isDark ? AppColors.darkSuccess : AppColors.lightSuccess)
        : status.color(context);
    final statusSoftColor = isCaptureMode
        ? (isDark ? AppColors.darkSuccessSoft : AppColors.lightSuccessSoft)
        : status.softColor(context);
    final statusIcon =
        isCaptureMode ? Icons.playlist_add_check_circle_rounded : status.icon;
    final statusTitle =
        isCaptureMode ? 'CAPTURA EXITOSA' : status.label.toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(
            isCaptureMode ? 'Resultado de Captura' : 'Resultado de Escaneo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Indicador principal de estado ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: statusSoftColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: isDark ? 0.2 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      statusIcon,
                      size: 48,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    statusTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getStatusMessage(status, isCaptureMode),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusColor.withValues(alpha: 0.85),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Detalle del Box ID ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: isCaptureMode
                          ? 'Detalle del registro'
                          : 'Detalle del Box ID',
                    ),
                    const SizedBox(height: 14),
                    if (isCaptureMode) ...[
                      _DetailRow(
                        label: 'No. de parte',
                        value: args.partNumber ?? args.boxId,
                        icon: Icons.inventory_2_outlined,
                        isMono: true,
                      ),
                      const Divider(height: 20),
                      _DetailRow(
                        label: 'Cantidad',
                        value: args.quantity?.toString() ?? 'N/A',
                        icon: Icons.numbers_rounded,
                      ),
                      const Divider(height: 20),
                      _DetailRow(
                        label: 'QR escaneado',
                        value: args.rawCode ?? 'N/A',
                        icon: Icons.qr_code_rounded,
                        isMono: true,
                      ),
                      const Divider(height: 20),
                    ] else ...[
                      _DetailRow(
                        label: 'Box ID',
                        value: args.boxId,
                        icon: Icons.qr_code_rounded,
                        isMono: true,
                      ),
                      const Divider(height: 20),
                      _DetailRow(
                        label: 'Producto',
                        value: args.productName ?? 'N/A',
                        icon: Icons.inventory_2_outlined,
                      ),
                      const Divider(height: 20),
                      _DetailRow(
                        label: 'Lote',
                        value: args.lotNumber ?? 'N/A',
                        icon: Icons.numbers_rounded,
                      ),
                      const Divider(height: 20),
                    ],
                    _DetailRow(
                      label: 'Fecha / Hora',
                      value: _formatDateTime(args.scannedAt),
                      icon: Icons.access_time_rounded,
                    ),
                    if (!isCaptureMode) ...[
                      const Divider(height: 20),
                      Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 18,
                            color: isDark
                                ? AppColors.darkTextDisabled
                                : AppColors.lightTextDisabled,
                          ),
                          const SizedBox(width: 10),
                          Text('Estado', style: theme.textTheme.bodyMedium),
                          const Spacer(),
                          SizedBox(
                            width: 100,
                            child: StatusBadge(status: status),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Acciones ──
            if (isCaptureMode || status == QualityStatus.released) ...[
              AppPrimaryButton(
                label: isCaptureMode ? 'Finalizar' : 'Confirmar Entrada',
                icon: Icons.check_rounded,
                onPressed: () => _showConfirmDialog(context),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(
                  isCaptureMode ? 'Escanear otro QR' : 'Escanear otro Box ID'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusMessage(QualityStatus status, bool isCaptureMode) {
    if (isCaptureMode) {
      return 'El QR fue procesado correctamente y la entrada quedó lista para registrarse.';
    }

    switch (status) {
      case QualityStatus.released:
        return 'Este producto ha sido liberado por calidad y puede dar entrada al almacén.';
      case QualityStatus.pending:
        return 'Este producto está pendiente de revisión por calidad. No puede dar entrada aún.';
      case QualityStatus.rejected:
        return 'Este producto fue rechazado por calidad. Se debe devolver al proveedor.';
      case QualityStatus.inProcess:
        return 'Este producto está en proceso de inspección. Espere a la resolución.';
    }
  }

  void _showConfirmDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
            SizedBox(width: 10),
            Text('Entrada Registrada'),
          ],
        ),
        content: const Text(
          'La entrada del producto ha sido registrada exitosamente en el almacén de embarques.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute hrs';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isMono;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.isMono = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color:
              isDark ? AppColors.darkTextDisabled : AppColors.lightTextDisabled,
        ),
        const SizedBox(width: 10),
        Text(label, style: theme.textTheme.bodyMedium),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: isMono ? 'monospace' : null,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
