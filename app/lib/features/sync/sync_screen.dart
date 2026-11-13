import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../core/utils/date_x.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/common_widgets.dart';
import '../../di/providers.dart';
import '../../domain/entities/sync_queue_item.dart';
import '../../domain/enums/sync_enums.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_screen.dart';
import 'sync_controller.dart';

/// Centre de synchronisation : état, file d'attente, erreurs, actions.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counters = ref.watch(syncCountersProvider);
    final runtime = ref.watch(syncControllerProvider);
    final settings = ref.watch(settingsProvider);
    final items = ref.watch(syncQueueItemsProvider).valueOrNull ??
        const <SyncQueueItem>[];
    final errors =
        items.where((item) => item.status == SyncState.error).toList();
    final recent = items.reversed.take(25).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Synchronisation'),
        actions: [
          IconButton(
            tooltip: 'Réglages',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _StatusCard(
            isOnline: runtime.isOnline,
            isSyncing: runtime.isSyncing,
            isConfigured: settings.isConfigured,
            targetLabel: settings.syncTargetLabel,
            lastSyncAt: settings.lastSyncAt,
            lastError: runtime.lastError ?? settings.lastSyncError,
            pending: counters.outstanding,
            onSyncNow: () async {
              final report =
                  await ref.read(syncControllerProvider.notifier).syncNow();
              if (!context.mounted) return;
              if (report == null) {
                showAppSnack(
                  context,
                  ref.read(syncControllerProvider).lastError ??
                      'Synchronisation impossible.',
                  color: AppColors.red,
                  icon: Icons.error_outline_rounded,
                );
              } else if (report.isEmpty) {
                showAppSnack(
                  context,
                  'Tout est déjà à jour.',
                  icon: Icons.check_circle_rounded,
                );
              } else {
                showAppSnack(
                  context,
                  report.error ??
                      '${report.succeeded} élément(s) synchronisé(s)'
                          '${report.failed > 0 ? " · ${report.failed} en erreur" : ""}',
                  icon: report.isSuccess
                      ? Icons.cloud_done_rounded
                      : Icons.error_outline_rounded,
                  color: report.isSuccess ? AppColors.navy : AppColors.red,
                );
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CounterTile(
                  label: 'En attente',
                  value: counters.pending,
                  color: AppColors.amber,
                  icon: Icons.cloud_upload_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CounterTile(
                  label: 'Erreurs',
                  value: counters.error,
                  color: AppColors.red,
                  icon: Icons.error_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CounterTile(
                  label: 'Envoyés',
                  value: counters.synced,
                  color: AppColors.green,
                  icon: Icons.cloud_done_rounded,
                ),
              ),
            ],
          ),
          if (errors.isNotEmpty) ...[
            SectionHeader(
              title: 'À corriger (${errors.length})',
              subtitle: 'Réessayez après avoir vérifié la connexion',
              actionLabel: 'Tout réessayer',
              onAction: () => ref
                  .read(syncControllerProvider.notifier)
                  .retryAllErrors(),
            ),
            for (final item in errors.take(5))
              _QueueTile(
                item: item,
                onRetry: () => ref
                    .read(syncControllerProvider.notifier)
                    .retryItem(item.id),
              ),
          ],
          const SectionHeader(
            title: 'File d\'attente',
            subtitle: 'Dernières opérations locales',
          ),
          if (recent.isEmpty)
            AppCard(
              child: EmptyState(
                icon: Icons.cloud_queue_rounded,
                title: 'File vide',
                message:
                    'Chaque pointage ou transaction apparaît ici jusqu\'à sa '
                    'confirmation par Google Sheets.',
              ),
            )
          else
            for (final item in recent) _QueueTile(item: item),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final message = await ref
                          .read(syncControllerProvider.notifier)
                          .testConnection();
                      if (!context.mounted) return;
                      showAppSnack(
                        context,
                        'Webhook OK : $message',
                        icon: Icons.wifi_tethering_rounded,
                      );
                    } catch (error) {
                      if (!context.mounted) return;
                      showAppSnack(
                        context,
                        error.toString().replaceFirst('Exception: ', ''),
                        color: AppColors.red,
                        icon: Icons.error_outline_rounded,
                      );
                    }
                  },
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Tester'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: counters.synced == 0
                      ? null
                      : () async {
                          await ref
                              .read(syncControllerProvider.notifier)
                              .clearHistory();
                          if (!context.mounted) return;
                          showAppSnack(
                            context,
                            'Historique des envois nettoyé.',
                            icon: Icons.cleaning_services_rounded,
                          );
                        },
                  icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: const Text('Nettoyer'),
                ),
              ),
            ],
          ),
          const SectionHeader(title: 'Comment ça marche ?'),
          AppCard(
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _HowItWorksLine(
                  index: '1',
                  text:
                      'Chaque action est écrite immédiatement sur le téléphone '
                      'et ajoutée à la file (statut PENDING).',
                ),
                _HowItWorksLine(
                  index: '2',
                  text:
                      'Au retour du réseau (ou sur « Synchroniser maintenant »), '
                      'la file part vers la cible active : Edge Function '
                      'Supabase (PostgreSQL) ou webhook Apps Script (Sheet).',
                ),
                _HowItWorksLine(
                  index: '3',
                  text:
                      'Le serveur insère ou met à jour la ligne grâce à l\'ID '
                      'unique (upsert idempotent), puis confirme chaque item '
                      '(SYNCED).',
                ),
                _HowItWorksLine(
                  index: '4',
                  text:
                      'En cas d\'échec, l\'item passe en ERROR avec un message '
                      'lisible et un compteur de tentatives.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isOnline,
    required this.isSyncing,
    required this.isConfigured,
    required this.targetLabel,
    required this.lastSyncAt,
    required this.lastError,
    required this.pending,
    required this.onSyncNow,
  });

  final bool isOnline;
  final bool isSyncing;
  final bool isConfigured;

  /// Libellé de la cible active (Supabase / Google Sheets).
  final String targetLabel;

  final DateTime? lastSyncAt;
  final String? lastError;
  final int pending;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final Color accent;
    final IconData icon;
    final String title;
    final String subtitle;

    if (!isConfigured) {
      accent = AppColors.amber;
      icon = Icons.link_off_rounded;
      title = 'Synchronisation non configurée';
      subtitle =
          'Renseignez l\'URL et le secret de la cible « $targetLabel » dans '
          'les réglages pour activer l\'envoi des données.';
    } else if (!isOnline) {
      accent = AppColors.amber;
      icon = Icons.cloud_off_rounded;
      title = 'Hors-ligne';
      subtitle =
          'Les données restent en sécurité sur le téléphone. L\'envoi reprendra '
          'automatiquement dès le retour du réseau.';
    } else if (lastError != null) {
      accent = AppColors.red;
      icon = Icons.error_outline_rounded;
      title = 'Dernier envoi en échec';
      subtitle = lastError!;
    } else if (pending > 0) {
      accent = AppColors.orange;
      icon = Icons.cloud_upload_rounded;
      title = '$pending élément(s) à envoyer';
      subtitle = 'Lancez l\'envoi ou laissez la synchronisation automatique agir.';
    } else {
      accent = AppColors.green;
      icon = Icons.cloud_done_rounded;
      title = 'Tout est synchronisé';
      subtitle = lastSyncAt == null
          ? 'Cible : $targetLabel · aucune donnée en attente.'
          : 'Cible : $targetLabel · dernier envoi : ${lastSyncAt!.dmy} '
              'à ${lastSyncAt!.hm}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.35), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LoadingButton(
            label: isSyncing ? 'Synchronisation…' : 'Synchroniser maintenant',
            icon: Icons.sync_rounded,
            loading: isSyncing,
            onPressed: isConfigured ? onSyncNow : null,
          ),
        ],
      ),
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.item, this.onRetry});

  final SyncQueueItem item;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final visual = visualForSync(item.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(visual.icon, size: 18, color: visual.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.entityType.sheetName} · ${_title(item)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.status == SyncState.error
                      ? (item.lastError ?? 'Erreur inconnue')
                      : 'Créé à ${item.createdAt.hm} · ${item.attempts} tentative(s)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: item.status == SyncState.error
                        ? AppColors.red
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: item.status.label,
            color: visual.color,
            background: visual.background,
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Réessayer',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  String _title(SyncQueueItem item) {
    final payload = item.payload;
    if (payload['joueur'] != null) return '${payload['joueur']}';
    if (payload['categorie'] != null) return '${payload['categorie']}';
    if (payload['nom'] != null) return '${payload['nom']}';
    if (payload['montant'] != null) return '${payload['montant']} Ar';
    return item.entityId.substring(0, 8);
  }
}

class _HowItWorksLine extends StatelessWidget {
  const _HowItWorksLine({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.navy,
              shape: BoxShape.circle,
            ),
            child: Text(
              index,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
