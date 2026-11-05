import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../di/providers.dart';
import '../attendance/attendance_screen.dart';
import '../finance/finance_screen.dart';
import '../history/history_screen.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_screen.dart';

/// Coque de navigation (4 onglets) : pointage, finances, historique, sync.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const List<Widget> _screens = <Widget>[
    AttendanceScreen(),
    FinanceScreen(),
    HistoryScreen(),
    SyncScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final counters = ref.watch(syncCountersProvider);
    final runtime = ref.watch(syncControllerProvider);

    // Remonte le résultat des synchronisations automatiques.
    ref.listen<SyncRuntimeState>(syncControllerProvider, (previous, next) {
      final report = next.lastReport;
      final previousReport = previous?.lastReport;
      if (report == null || identical(report, previousReport)) return;
      if (report.attempted == 0) return;
      if (!mounted) return;
      if (report.isSuccess) {
        showAppSnack(
          context,
          '${report.succeeded} élément(s) synchronisé(s) avec Google Sheets.',
          icon: Icons.cloud_done_rounded,
          duration: const Duration(seconds: 3),
        );
      } else if (report.error != null) {
        showAppSnack(
          context,
          'Synchronisation incomplète : ${report.error}',
          color: AppColors.red,
          icon: Icons.error_outline_rounded,
        );
      }
    });

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'Pointage',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Finances',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Historique',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: counters.outstanding,
              isLabelVisible: counters.outstanding > 0,
              backgroundColor:
                  counters.error > 0 ? AppColors.red : AppColors.orange,
              child: Icon(
                runtime.isSyncing
                    ? Icons.cloud_sync_rounded
                    : Icons.cloud_queue_rounded,
              ),
            ),
            selectedIcon: Badge.count(
              count: counters.outstanding,
              isLabelVisible: counters.outstanding > 0,
              backgroundColor:
                  counters.error > 0 ? AppColors.red : AppColors.orange,
              child: const Icon(Icons.cloud_done_rounded),
            ),
            label: 'Synchro',
          ),
        ],
      ),
    );
  }
}
