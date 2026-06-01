import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/optimistic_update_service.dart';
import '../../shared/widgets/connection_indicator.dart';
import '../scan/scan_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';

/// Pantalla principal con navegación inferior (Mockup).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeTabDefinition {
  final String id;
  final Widget screen;
  final NavigationDestination destination;

  const _HomeTabDefinition({
    required this.id,
    required this.screen,
    required this.destination,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  List<_HomeTabDefinition> _availableTabs() {
    final tabs = <_HomeTabDefinition>[];
    final hasOperationalAccess = AuthService.hasMobileOperationalAccess;

    if (!hasOperationalAccess) {
      tabs.add(
        const _HomeTabDefinition(
          id: 'no_access',
          screen: _NoPermissionsTab(),
          destination: NavigationDestination(
            icon: Icon(Icons.lock_outline_rounded),
            selectedIcon: Icon(Icons.lock_rounded),
            label: 'Acceso',
          ),
        ),
      );
    }

    if (AuthService.canViewDashboard) {
      tabs.add(
        const _HomeTabDefinition(
          id: 'dashboard',
          screen: _DashboardTab(),
          destination: NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Inicio',
          ),
        ),
      );
    }

    if (AuthService.canViewHistory) {
      tabs.add(
        const _HomeTabDefinition(
          id: 'history',
          screen: HistoryScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Historial',
          ),
        ),
      );
    }

    if (AuthService.canViewSettings) {
      tabs.add(
        const _HomeTabDefinition(
          id: 'settings',
          screen: SettingsScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Ajustes',
          ),
        ),
      );
    }

    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabs = _availableTabs();
    final selectedIndex = _currentIndex >= tabs.length ? 0 : _currentIndex;
    final showNavigation = tabs.length > 1 || tabs.first.id != 'no_access';

    return Scaffold(
      body: tabs[selectedIndex].screen,
      bottomNavigationBar: showNavigation
          ? Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color:
                        isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 1,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) =>
                    setState(() => _currentIndex = index),
                destinations: tabs.map((tab) => tab.destination).toList(),
              ),
            )
          : null,
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
  int _pendingSync = 0;
  StreamSubscription<int>? _pendingSyncSubscription;

  @override
  void initState() {
    super.initState();
    _pendingSyncSubscription =
        OptimisticUpdateService.pendingCountStream.listen((
      count,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingSync = count;
      });
    });
    _loadData();
    // Iniciar monitoreo de conectividad
    ConnectivityService.startMonitoring();
  }

  @override
  void dispose() {
    _pendingSyncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _pendingSync = OptimisticUpdateService.pendingOperations.length;
    });
  }

  Future<void> _onRefresh() async {
    await OptimisticUpdateService.syncAllPending();
    setState(() {
      _pendingSync = OptimisticUpdateService.pendingOperations.length;
    });
  }

  String _getGreeting() {
    final user = AuthService.currentUser;
    final name = user?.fullName ?? 'Operador';
    return 'Hola, $name';
  }

  String _getDateShift() {
    final now = DateTime.now();
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];
    final user = AuthService.currentUser;
    final department = user?.department.isNotEmpty == true
        ? user!.department
        : 'Registro móvil';
    return '${now.day} ${months[now.month - 1]}, ${now.year} • $department';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canWriteEntries = AuthService.canWriteEntries;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: const _EntriesHeaderBar(),
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
            const SizedBox(height: 24),

            if (canWriteEntries) ...[
              EntryScanForm(
                embedded: true,
                onRegistered: () => unawaited(_onRefresh()),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoPermissionsTab extends StatelessWidget {
  const _NoPermissionsTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: const _EntriesHeaderBar(),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_person_rounded,
                size: 56,
                color: isDark ? AppColors.darkWarning : AppColors.lightWarning,
              ),
              const SizedBox(height: 16),
              Text(
                'Sin permisos asignados',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tu usuario no tiene permisos para registrar o consultar movimientos en la app móvil.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntriesHeaderBar extends StatelessWidget {
  const _EntriesHeaderBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Stack(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: _EntriesHeaderLogo(),
            ),
            const Positioned.fill(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 72),
                  child: _EntriesHeaderBrand(),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ConnectionIndicator(compact: true),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntriesHeaderLogo extends StatelessWidget {
  const _EntriesHeaderLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'LOGO.png',
      height: 28,
      fit: BoxFit.contain,
    );
  }
}

class _EntriesHeaderBrand extends StatelessWidget {
  const _EntriesHeaderBrand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Entradas',
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 0.9,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'Almacén de Embarques',
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.darkTextSecondary.withValues(alpha: 0.92),
            height: 0.95,
          ),
          textAlign: TextAlign.center,
        ),
      ],
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
