import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/category_selector.dart';
import '../../core/widgets/common_widgets.dart';
import '../../di/providers.dart';
import '../../domain/entities/player.dart';
import '../../domain/enums/team_category.dart';
import 'demo_seed.dart';

/// Gestion de l'effectif (hors-ligne, synchronisé vers l'onglet `Joueurs`).
class RosterScreen extends ConsumerWidget {
  const RosterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players =
        ref.watch(playersStreamProvider).valueOrNull ?? const <Player>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('Effectif (${players.where((p) => p.isActive).length})'),
        actions: [
          IconButton(
            tooltip: 'Ajouter un joueur',
            onPressed: () => _openAddPlayer(context, ref),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: players.isEmpty
          ? EmptyState(
              icon: Icons.groups_2_outlined,
              title: 'Effectif vide',
              message:
                  'Ajoutez vos joueurs catégorie par catégorie, ou chargez '
                  'l\'effectif de démonstration pour tester l\'application.',
              actionLabel: 'Charger la démo',
              onAction: () async {
                final created = await DemoSeed(
                  ref.read(playerRepositoryProvider),
                ).seedRosterIfEmpty();
                if (!context.mounted) return;
                showAppSnack(
                  context,
                  created > 0
                      ? '$created joueurs ajoutés.'
                      : 'Effectif déjà rempli.',
                  icon: Icons.groups_rounded,
                );
              },
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                for (final category in TeamCategory.values)
                  ..._buildCategorySection(context, ref, category, players),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddPlayer(context, ref),
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  List<Widget> _buildCategorySection(
    BuildContext context,
    WidgetRef ref,
    TeamCategory category,
    List<Player> players,
  ) {
    final list = players
        .where((player) => player.category == category && player.isActive)
        .toList();
    if (list.isEmpty) return const <Widget>[];

    return <Widget>[
      SectionHeader(
        title: '${category.label} · ${list.length} joueur(s)',
        subtitle: category.ageRange,
      ),
      for (final player in list)
        AppCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorForCategoryIndex(category.index).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  player.jerseyNumber?.toString() ?? player.initials,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colorForCategoryIndex(category.index),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (player.phone != null)
                      Text(
                        player.phone!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              StatusPill.sync(player.syncState),
              IconButton(
                tooltip: 'Archiver',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await ref.read(playerRepositoryProvider).archive(player.id);
                  if (!context.mounted) return;
                  showAppSnack(
                    context,
                    '${player.fullName} archivé (l\'historique est conservé).',
                    icon: Icons.archive_rounded,
                  );
                },
                icon: const Icon(Icons.archive_outlined),
              ),
            ],
          ),
        ),
      const SizedBox(height: 4),
    ];
  }

  Future<void> _openAddPlayer(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _AddPlayerSheet(
          onSaved: (name, category, jersey, phone) async {
            await DemoSeed(ref.read(playerRepositoryProvider)).addPlayer(
              fullName: name,
              category: category,
              jerseyNumber: jersey,
              phone: phone,
            );
            if (!context.mounted) return;
            showAppSnack(
              context,
              '$name ajouté à ${category.label}.',
              icon: Icons.person_add_alt_1_rounded,
            );
          },
        ),
      ),
    );
  }
}

class _AddPlayerSheet extends StatefulWidget {
  const _AddPlayerSheet({required this.onSaved});

  final Future<void> Function(
    String name,
    TeamCategory category,
    int? jersey,
    String? phone,
  ) onSaved;

  @override
  State<_AddPlayerSheet> createState() => _AddPlayerSheetState();
}

class _AddPlayerSheetState extends State<_AddPlayerSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _jerseyController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  TeamCategory _category = TeamCategory.u12;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _jerseyController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ajouter un joueur',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom et prénom',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _jerseyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Numéro',
                      prefixIcon: Icon(Icons.numbers_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone (facultatif)',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Catégorie',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            CategorySelector(
              selected: _category,
              compact: true,
              onChanged: (value) => setState(() => _category = value),
            ),
            const SizedBox(height: 16),
            LoadingButton(
              label: _saving ? 'Ajout…' : 'Ajouter le joueur',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: () async {
                final name = _nameController.text.trim();
                if (name.isEmpty) return;
                setState(() => _saving = true);
                await widget.onSaved(
                  name,
                  _category,
                  int.tryParse(_jerseyController.text.trim()),
                  _phoneController.text.trim().isEmpty
                      ? null
                      : _phoneController.text.trim(),
                );
                if (!mounted) return;
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
