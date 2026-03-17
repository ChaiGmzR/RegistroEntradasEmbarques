import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/shipping_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/optimistic_update_service.dart';
import '../../core/services/update_service.dart';
import '../../core/config/update_config.dart';
import '../../models/box_id_entry.dart';
import '../../models/mock_data.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/connection_indicator.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../../shared/widgets/update_dialog.dart';
import '../scan/scan_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';

/// Pantalla principal con navegación inferior (Mockup).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    _DashboardTab(),
    ScanScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) =>
              setState(() => _currentIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_outlined),
              selectedIcon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Escanear',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'Historial',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab del Dashboard principal.
class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  bool _isLoading = true;
  Map<String, int> _stats = {};
  List<BoxIdEntry> _recentScans = [];
  int _pendingSync = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Iniciar monitoreo de conectividad
    ConnectivityService.startMonitoring();
    // Verificar actualizaciones al iniciar
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    if (!UpdateConfig.checkOnStartup) return;

    final updateInfo = await UpdateService.checkForUpdate();
    if (updateInfo != null && mounted) {
      // Mostrar dialogo de actualizacion disponible
      UpdateDialog.show(context, updateInfo);
    }
  }

  Future<void> _loadData() async {
    // 1. Cargar desde caché primero (instantáneo)
    final cachedStats = CacheService.get<Map<String, int>>('stats:today', 'stats');
    final cachedHistory = CacheService.get<List<BoxIdEntry>>('history:recent', 'history');
    
    if (cachedStats != null || cachedHistory != null) {
      setState(() {
        _stats = cachedStats ?? MockData.todayStats;
        _recentScans = cachedHistory ?? [];
        _isLoading = false;
      });
    }

    // 2. Actualizar pendientes de sync
    setState(() {
      _pendingSync = OptimisticUpdateService.pendingOperations.length;
    });

    // 3. Refrescar desde servidor en background
    await _refreshFromServer();
  }

  Future<void> _refreshFromServer() async {
    // Si estamos usando mock, usar datos mock
    if (AuthService.useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _stats = MockData.todayStats;
        _recentScans = MockData.recentScans;
        _isLoading = false;
      });
      // Guardar en caché
      CacheService.set('stats:today', _stats);
      CacheService.set('history:recent', _recentScans);
      return;
    }

    // Llamar API real
    try {
      final statsResult = await ShippingService.getTodayStats();
      final historyResult = await ShippingService.getHistory(limit: 10);
      
      if (mounted) {
        setState(() {
          _stats = {
            'total': statsResult.total,
            'released': statsResult.released,
            'pending': statsResult.pending,
            'rejected': statsResult.rejected,
            'inProcess': statsResult.inProcess,
          };
          _recentScans = historyResult;
          _isLoading = false;
        });
        
        // Actualizar caché
        CacheService.set('stats:today', _stats);
        CacheService.set('history:recent', _recentScans);
      }
    } catch (e) {
      // Si falla, mantener datos de caché/mock
      if (mounted && _isLoading) {
        setState(() {
          _stats = MockData.todayStats;
          _recentScans = MockData.recentScans;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    // Sincronizar pendientes
    await OptimisticUpdateService.syncAllPending();
    // Refrescar datos
    await _refreshFromServer();
    // Actualizar contador de pendientes
    setState(() {
      _pendingSync = OptimisticUpdateService.pendingOperations.length;
    });
  }

  String _getGreeting() {
    final user = AuthService.currentUser;
    final name = user?.fullName ?? 'Operador';
    return 'Hola, $name 👋';
  }

  String _getDateShift() {
    final now = DateTime.now();
    final months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 
                   'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final user = AuthService.currentUser;
    final shift = user?.shift ?? 'Turno A';
    return '${now.day} ${months[now.month - 1]}, ${now.year} • $shift';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warehouse_rounded,
              size: 22,
              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
            ),
            const SizedBox(width: 8),
            const Text('Registro Embarques'),
          ],
        ),
        actions: [
          // Indicador de conexión compacto
          const ConnectionIndicator(compact: true),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Banner de sincronización pendiente ──
            if (_pendingSync > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SyncPendingBanner(
                  count: _pendingSync,
                  onRetry: _onRefresh,
                ),
              ),

            // ── Bienvenida ──
            Text(_getGreeting(), style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              _getDateShift(),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),

            // ── Resumen rápido ──
            const SectionHeader(title: 'Resumen del día'),
            const SizedBox(height: 10),
            
            // Mostrar shimmer mientras carga, o datos reales
            if (_isLoading)
              const StatsGridShimmer()
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.4,
                children: [
                  StatCard(
                    label: 'Total Escaneados',
                    value: '${_stats['total'] ?? 0}',
                    icon: Icons.qr_code_scanner_rounded,
                    color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                  ),
                  StatCard(
                    label: 'Liberados',
                    value: '${_stats['released'] ?? 0}',
                    icon: Icons.check_circle_rounded,
                    color: isDark ? AppColors.darkSuccess : AppColors.lightSuccess,
                  ),
                  StatCard(
                    label: 'Pendientes',
                    value: '${_stats['pending'] ?? 0}',
                    icon: Icons.warning_amber_rounded,
                    color: isDark ? AppColors.darkWarning : AppColors.lightWarning,
                  ),
                  StatCard(
                    label: 'Rechazados',
                    value: '${_stats['rejected'] ?? 0}',
                    icon: Icons.cancel_rounded,
                    color: isDark ? AppColors.darkError : AppColors.lightError,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Acción principal ──
            _QuickScanCard(isDark: isDark),
            const SizedBox(height: 24),

            // ── Últimos escaneos ──
            SectionHeader(
              title: 'Últimos escaneos',
              actionLabel: 'Ver todo',
              onAction: () =>
                  Navigator.pushNamed(context, AppConstants.historyRoute),
            ),
            const SizedBox(height: 10),
            
            if (_isLoading)
              const ScanListShimmer(itemCount: 3)
            else if (_recentScans.isEmpty)
              _EmptyStateCard(isDark: isDark)
            else
              ..._recentScans.take(4).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ScanEntryCard(
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
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Banner de sincronización pendiente.
class _SyncPendingBanner extends StatelessWidget {
  final int count;
  final VoidCallback? onRetry;

  const _SyncPendingBanner({required this.count, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.darkInfo : AppColors.lightInfo;
    final bgColor = isDark ? AppColors.darkInfoSoft : AppColors.lightInfoSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count registro${count > 1 ? 's' : ''} pendiente${count > 1 ? 's' : ''} de sincronizar',
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
          if (onRetry != null)
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'Reintentar',
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Estado vacío cuando no hay escaneos.
class _EmptyStateCard extends StatelessWidget {
  final bool isDark;

  const _EmptyStateCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Sin escaneos hoy',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Los registros aparecerán aquí',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de acción rápida para iniciar escaneo.
class _QuickScanCard extends StatelessWidget {
  final bool isDark;

  const _QuickScanCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide.none,
      ),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, AppConstants.scanRoute),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Escanear Box ID',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Usa el scanner del PDA para registrar entrada',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
