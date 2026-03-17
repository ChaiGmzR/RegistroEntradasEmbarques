import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/shipping_service.dart';
import '../../core/services/optimistic_update_service.dart';
import '../../models/box_id_entry.dart';
import '../../shared/widgets/common_widgets.dart';

/// Argumentos para la pantalla de resultado de escaneo.
class ScanResultArguments {
  final String boxId;
  final QualityStatus status;
  final String? productName;
  final String? lotNumber;

  const ScanResultArguments({
    required this.boxId,
    required this.status,
    this.productName,
    this.lotNumber,
  });
}

/// Pantalla de escaneo de Box ID (Mockup).
/// En la PDA Zebra TC15, el scan físico disparará la lectura automática.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final _manualController = TextEditingController();
  bool _isScanning = true;
  bool _isProcessing = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _manualController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _simulateScan(String boxId) {
    _processScan(boxId.isEmpty ? 'BOX-2026-001850' : boxId);
  }

  /// Procesa un escaneo real o simulado.
  Future<void> _processScan(String boxId) async {
    setState(() => _isProcessing = true);

    try {
      QualityStatus status;
      String? productName;
      String? lotNumber;

      if (AuthService.useMockData) {
        // Modo mock: simular respuesta
        await Future.delayed(const Duration(milliseconds: 300));
        status = QualityStatus.released;
        productName = 'Componente electrónico A';
        lotNumber = 'LOT-2026-0218A';
      } else {
        // Modo real: consultar API
        final qualityResult = await ShippingService.checkQualityStatus(boxId);
        
        if (qualityResult.success && qualityResult.entry != null) {
          status = qualityResult.entry!.status;
          productName = qualityResult.entry!.productName;
          lotNumber = qualityResult.entry!.lotNumber;
        } else {
          // Box ID no encontrado, marcar como pendiente
          status = QualityStatus.pending;
          productName = null;
          lotNumber = null;
        }
      }

      // Registrar entrada de forma optimista (instantánea)
      final user = AuthService.currentUser;
      await OptimisticUpdateService.registerEntryOptimistic(
        boxId: boxId,
        status: status,
        scannedBy: user?.id ?? 'unknown',
        productName: productName,
        lotNumber: lotNumber,
        deviceId: 'PDA-TC15',
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Navegar al resultado
      Navigator.pushNamed(
        context,
        AppConstants.scanResultRoute,
        arguments: ScanResultArguments(
          boxId: boxId,
          status: status,
          productName: productName,
          lotNumber: lotNumber,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear Box ID'),
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
            // ── Área de escaneo ──
            Expanded(
              child: _isScanning
                  ? _buildScanArea(theme, isDark)
                  : _buildManualEntry(theme, isDark),
            ),

            const SizedBox(height: 16),

            // ── Toggle modo ──
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.lightSurfaceSecondary,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeButton(
                      label: 'Escáner PDA',
                      icon: Icons.qr_code_scanner_rounded,
                      isActive: _isScanning,
                      onTap: () => setState(() => _isScanning = true),
                    ),
                  ),
                  Expanded(
                    child: _ModeButton(
                      label: 'Manual',
                      icon: Icons.keyboard_rounded,
                      isActive: !_isScanning,
                      onTap: () => setState(() => _isScanning = false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Estado ──
            if (_isProcessing) ...[
              LinearProgressIndicator(
                borderRadius: BorderRadius.circular(4),
                color:
                    isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                backgroundColor: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.lightSurfaceSecondary,
              ),
              const SizedBox(height: 10),
              Text(
                'Validando estatus de calidad...',
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

  Widget _buildScanArea(ThemeData theme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Viewfinder animado
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = 1.0 + (_pulseController.value * 0.04);
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                width: 3,
              ),
            ),
            child: Stack(
              children: [
                // Esquinas decorativas
                ..._buildCorners(isDark),
                // Icono central
                Center(
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 72,
                    color: (isDark ? AppColors.darkPrimary : AppColors.lightPrimary)
                        .withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Apunta el scanner al código de barras',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Presiona el botón lateral del PDA\npara activar el escáner',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // Simular escaneo (para el mockup)
        OutlinedButton.icon(
          onPressed: () => _simulateScan(''),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Simular Escaneo'),
        ),
      ],
    );
  }

  Widget _buildManualEntry(ThemeData theme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.keyboard_rounded,
          size: 56,
          color: isDark ? AppColors.darkTextDisabled : AppColors.lightTextDisabled,
        ),
        const SizedBox(height: 20),
        Text(
          'Ingreso Manual',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Escribe el código Box ID manualmente',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Box ID',
          hint: 'Ej: BOX-2026-001847',
          prefixIcon: Icons.inventory_2_outlined,
          controller: _manualController,
          keyboardType: TextInputType.text,
          autofocus: true,
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          label: 'Validar Box ID',
          icon: Icons.search_rounded,
          onPressed: () {
            if (_manualController.text.isNotEmpty) {
              _simulateScan(_manualController.text);
            }
          },
        ),
      ],
    );
  }

  List<Widget> _buildCorners(bool isDark) {
    final color = isDark ? AppColors.darkFocusRing : AppColors.lightFocusRing;
    const size = 24.0;
    const thickness = 3.0;

    return [
      // Top-left
      Positioned(
        top: 0,
        left: 0,
        child: _CornerDecoration(
          color: color,
          size: size,
          thickness: thickness,
          topLeft: true,
        ),
      ),
      // Top-right
      Positioned(
        top: 0,
        right: 0,
        child: _CornerDecoration(
          color: color,
          size: size,
          thickness: thickness,
          topRight: true,
        ),
      ),
      // Bottom-left
      Positioned(
        bottom: 0,
        left: 0,
        child: _CornerDecoration(
          color: color,
          size: size,
          thickness: thickness,
          bottomLeft: true,
        ),
      ),
      // Bottom-right
      Positioned(
        bottom: 0,
        right: 0,
        child: _CornerDecoration(
          color: color,
          size: size,
          thickness: thickness,
          bottomRight: true,
        ),
      ),
    ];
  }
}

class _CornerDecoration extends StatelessWidget {
  final Color color;
  final double size;
  final double thickness;
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;

  const _CornerDecoration({
    required this.color,
    required this.size,
    required this.thickness,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          thickness: thickness,
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;

  _CornerPainter({
    required this.color,
    required this.thickness,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    if (topLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (topRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (bottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else if (bottomRight) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Botón de modo (Escáner / Manual).
class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? AppColors.darkPrimary : AppColors.lightPrimary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? Colors.white
                  : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
