import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Modelo para representar estados de calidad de un Box ID.
enum QualityStatus {
  released,
  pending,
  rejected,
  inProcess,
}

extension QualityStatusExtension on QualityStatus {
  String get label {
    switch (this) {
      case QualityStatus.released:
        return 'Liberado';
      case QualityStatus.pending:
        return 'Pendiente';
      case QualityStatus.rejected:
        return 'Rechazado';
      case QualityStatus.inProcess:
        return 'En Proceso';
    }
  }

  IconData get icon {
    switch (this) {
      case QualityStatus.released:
        return Icons.check_circle_rounded;
      case QualityStatus.pending:
        return Icons.warning_amber_rounded;
      case QualityStatus.rejected:
        return Icons.cancel_rounded;
      case QualityStatus.inProcess:
        return Icons.info_rounded;
    }
  }

  Color color(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (this) {
      case QualityStatus.released:
        return isDark ? AppColors.darkSuccess : AppColors.lightSuccess;
      case QualityStatus.pending:
        return isDark ? AppColors.darkWarning : AppColors.lightWarning;
      case QualityStatus.rejected:
        return isDark ? AppColors.darkError : AppColors.lightError;
      case QualityStatus.inProcess:
        return isDark ? AppColors.darkInfo : AppColors.lightInfo;
    }
  }

  Color softColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (this) {
      case QualityStatus.released:
        return isDark ? AppColors.darkSuccessSoft : AppColors.lightSuccessSoft;
      case QualityStatus.pending:
        return isDark ? AppColors.darkWarningSoft : AppColors.lightWarningSoft;
      case QualityStatus.rejected:
        return isDark ? AppColors.darkErrorSoft : AppColors.lightErrorSoft;
      case QualityStatus.inProcess:
        return isDark ? AppColors.darkInfoSoft : AppColors.lightInfoSoft;
    }
  }
}

/// Modelo de datos de un escaneo de Box ID (mockup).
class BoxIdEntry {
  final String boxId;
  final QualityStatus status;
  final DateTime scannedAt;
  final String? productName;
  final String? lotNumber;

  const BoxIdEntry({
    required this.boxId,
    required this.status,
    required this.scannedAt,
    this.productName,
    this.lotNumber,
  });
}
