import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/shipping_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/box_id_entry.dart';
import '../../models/mock_data.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../scan/scan_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  MovementType? _selectedFilter;
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
    final cached = _visibleEntries(CacheService.getHistory());
    if (cached != null) {
      setState(() {
        _entries = cached;
        _isLoading = false;
      });
    }

    if (AuthService.useMockData) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = _visibleEntries(MockData.recentScans) ?? [];
        _isLoading = false;
      });
      CacheService.setHistory(_entries);
      return;
    }

    try {
      final entries = await ShippingService.getHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = _visibleEntries(entries) ?? [];
        _isLoading = false;
      });
      CacheService.setHistory(_entries);
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (_isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<BoxIdEntry> get _filteredEntries {
    var entries = _entries;
    if (_selectedFilter != null) {
      entries = entries.where((e) => e.status == _selectedFilter).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      entries = entries
          .where((e) =>
              e.boxId.toLowerCase().contains(query) ||
              (e.folio?.toLowerCase().contains(query) ?? false) ||
              (e.partNumber?.toLowerCase().contains(query) ?? false) ||
              (e.detail?.toLowerCase().contains(query) ?? false))
          .toList();
    }
    return entries;
  }

  List<BoxIdEntry>? _visibleEntries(List<BoxIdEntry>? entries) {
    return entries
        ?.where(
          (entry) =>
              entry.status == MovementType.entry ||
              entry.status == MovementType.materialReturn,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final entries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Entradas'),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppTextField(
              label: 'Buscar',
              hint: 'No. de parte, folio o detalle',
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
                  label: 'Entradas',
                  color:
                      isDark ? AppColors.darkSuccess : AppColors.lightSuccess,
                  isSelected: _selectedFilter == MovementType.entry,
                  onTap: () =>
                      setState(() => _selectedFilter = MovementType.entry),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Retornos',
                  color: isDark ? AppColors.darkError : AppColors.lightError,
                  isSelected: _selectedFilter == MovementType.materialReturn,
                  onTap: () => setState(
                    () => _selectedFilter = MovementType.materialReturn,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
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
                                  scannedAt: entry.scannedAt,
                                  partNumber: entry.partNumber,
                                  quantity: entry.quantity,
                                  rawCode: entry.rawCode,
                                  detail: entry.detail,
                                  notes: entry.notes,
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
            'No se encontraron entradas con este filtro.',
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
