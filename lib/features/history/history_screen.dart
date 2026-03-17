import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/shipping_service.dart';
import '../../models/box_id_entry.dart';
import '../../models/mock_data.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../scan/scan_screen.dart';

/// Pantalla de historial de escaneos (Mockup).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  QualityStatus? _selectedFilter;
  final _searchController = TextEditingController();
  
  List<BoxIdEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    // 1. Cache primero (instantáneo)
    final cached = CacheService.getHistory();
    if (cached != null) {
      setState(() {
        _entries = cached;
        _isLoading = false;
      });
    }

    // 2. API en background
    if (AuthService.useMockData) {
      // Modo mock
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() {
        _entries = MockData.recentScans;
        _isLoading = false;
      });
      CacheService.setHistory(MockData.recentScans);
    } else {
      // Modo real
      try {
        final entries = await ShippingService.getHistory();
        if (!mounted) return;
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
        CacheService.setHistory(entries);
      } catch (e) {
        // Si falla y no teníamos cache, marcar como no cargando
        if (!mounted) return;
        if (_isLoading) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  List<BoxIdEntry> get _filteredEntries {
    var entries = _entries;
    if (_selectedFilter != null) {
      entries =
          entries.where((e) => e.status == _selectedFilter).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      entries = entries
          .where((e) =>
              e.boxId.toLowerCase().contains(query) ||
              (e.productName?.toLowerCase().contains(query) ?? false))
          .toList();
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final entries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Escaneos'),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: Column(
        children: [
          // ── Buscador ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppTextField(
              label: 'Buscar',
              hint: 'Box ID o nombre de producto',
              prefixIcon: Icons.search_rounded,
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
          ),

          // ── Filtros ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Todos',
                  isSelected: _selectedFilter == null,
                  onTap: () => setState(() => _selectedFilter = null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Liberados',
                  color: isDark ? AppColors.darkSuccess : AppColors.lightSuccess,
                  isSelected: _selectedFilter == QualityStatus.released,
                  onTap: () => setState(
                      () => _selectedFilter = QualityStatus.released),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Pendientes',
                  color: isDark ? AppColors.darkWarning : AppColors.lightWarning,
                  isSelected: _selectedFilter == QualityStatus.pending,
                  onTap: () => setState(
                      () => _selectedFilter = QualityStatus.pending),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Rechazados',
                  color: isDark ? AppColors.darkError : AppColors.lightError,
                  isSelected: _selectedFilter == QualityStatus.rejected,
                  onTap: () => setState(
                      () => _selectedFilter = QualityStatus.rejected),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'En Proceso',
                  color: isDark ? AppColors.darkInfo : AppColors.lightInfo,
                  isSelected: _selectedFilter == QualityStatus.inProcess,
                  onTap: () => setState(
                      () => _selectedFilter = QualityStatus.inProcess),
                ),
              ],
            ),
          ),

          // ── Contador ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${entries.length} resultado${entries.length != 1 ? 's' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Icon(
                  Icons.sort_rounded,
                  size: 18,
                  color: isDark
                      ? AppColors.darkTextDisabled
                      : AppColors.lightTextDisabled,
                ),
                const SizedBox(width: 4),
                Text(
                  'Más reciente',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // ── Lista ──
          Expanded(
            child: _isLoading
                ? const ScanListShimmer()
                : entries.isEmpty
                    ? _buildEmptyState(theme, isDark)
                    : RefreshIndicator(
                        onRefresh: _loadHistory,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return ScanEntryCard(
                              entry: entry,
                              onTap: () => Navigator.pushNamed(
                                context,
                                AppConstants.scanResultRoute,
                                arguments: ScanResultArguments(
                                  boxId: entry.boxId,
                                  status: entry.status,
                                  productName: entry.productName,
                                  lotNumber: entry.lotNumber,
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

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: isDark
                ? AppColors.darkTextDisabled
                : AppColors.lightTextDisabled,
          ),
          const SizedBox(height: 12),
          Text(
            'Sin resultados',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'No se encontraron escaneos con este filtro.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveColor = color ?? theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? effectiveColor.withValues(alpha: isDark ? 0.2 : 0.12)
              : isDark
                  ? AppColors.darkSurfaceElevated
                  : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? effectiveColor
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? effectiveColor
                : (isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
