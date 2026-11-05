import 'package:flutter/material.dart';

import '../../domain/enums/team_category.dart';
import '../theme/app_colors.dart';
import '../theme/status_styles.dart';

/// Sélecteur de catégorie d'âge (4 catégories du club).
///
/// Chaque catégorie a une couleur stable : le coach associe l'écran à l'équipe
/// d'un coup d'œil, sans relire le libellé.
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final TeamCategory selected;
  final ValueChanged<TeamCategory> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 42 : 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: TeamCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = TeamCategory.values[index];
          final isSelected = category == selected;
          final color = colorForCategoryIndex(index);

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onChanged(category),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 16,
                  vertical: compact ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? color : AppColors.border,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: TextStyle(
                        fontSize: compact ? 13.5 : 15,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (!compact)
                      Text(
                        category.ageRange,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? Colors.white.withOpacity(0.85)
                              : AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
