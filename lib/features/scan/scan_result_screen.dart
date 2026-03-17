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
        const ScanResultArguments(
          boxId: 'BOX-XXXX-XXXXXX',
          status: QualityStatus.released,
        );

    final status = args.status;
    final statusColor = status.color(context);
    final statusSoftColor = status.softColor(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado de Escaneo'),
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
                      status.icon,
                      size: 48,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    status.label.toUpperCase(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getStatusMessage(status),
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
                    SectionHeader(title: 'Detalle del Box ID'),
                    const SizedBox(height: 14),
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
                    _DetailRow(
                      label: 'Fecha / Hora',
                      value: '18/02/2026 14:32 hrs',
                      icon: Icons.access_time_rounded,
                    ),
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
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Acciones ──
            if (status == QualityStatus.released) ...[
              AppPrimaryButton(
                label: 'Confirmar Entrada',
                icon: Icons.check_rounded,
                onPressed: () => _showConfirmDialog(context),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Escanear otro Box ID'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusMessage(QualityStatus status) {
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
          color: isDark
              ? AppColors.darkTextDisabled
              : AppColors.lightTextDisabled,
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
