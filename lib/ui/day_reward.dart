/// Награда за продуктивный день (экран «Сегодня»).
///
/// После отметки выполнения задачи считаем долю закрытых задач дня
/// (включая закреплённые ежедневные — они учитываются каждый день
/// независимо от наличия дедлайна). Диалог показывается СТРОГО один
/// раз на порог: 60% — лёгкое уведомление, 80% — эмоциональное
/// подбадривание (если день закрыт на 100% — особое сообщение с учётом
/// рода обращения из профиля). Повторных всплытий нет: любой исход
/// диалога (выбор, «Пропустить», кнопка «назад») записывается в БД
/// (таблица day_rewards) и попадает в статистику и выгрузку.
library;

import 'package:flutter/material.dart';

import '../praise.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';

/// Защита от одновременного показа двух диалогов (двойной тап).
bool _dialogOpen = false;

/// Вызывается после отметки выполнения задачи на экране «Сегодня».
Future<void> checkDayReward(BuildContext context, AppStore store) async {
  if (_dialogOpen) return;
  final now = DateTime.now();
  // Задачи дня: с дедлайном сегодня (выполненные уже в архиве — тоже
  // считаем) + просроченные, которые висят на сегодняшнем экране, +
  // закреплённые ежедневные (активные сейчас или выполненные сегодня).
  final list = store.tasks.where((t) {
    if (t.isPinned) {
      if (!t.isArchived) return true;
      final da = t.doneAt;
      return da != null && isSameDay(da, now);
    }
    final dl = t.deadline;
    if (dl == null) return false;
    if (isSameDay(dl, now)) return true;
    return dl.isBefore(now) && !t.isDone;
  }).toList();
  if (list.isEmpty) return;
  final done = list.where((t) => t.isDone).length;
  final pct = done / list.length;
  // Пороги ровно два: 60% и 80%. Показ — один раз на порог в день.
  final tier = pct >= 0.8 ? 2 : (pct >= 0.6 ? 1 : 0);
  if (tier == 0) return;
  if (store.hasDayReward(now, tier)) return;
  if (!context.mounted) return;
  _dialogOpen = true;
  try {
    await _showRewardDialog(context, store, now, tier, pct, done, list.length);
  } finally {
    _dialogOpen = false;
  }
}

Future<void> _showRewardDialog(BuildContext context, AppStore store,
    DateTime day, int tier, double pct, int done, int total) async {
  String chosen = Praise.rewardIdeas.first;
  // День закрыт на 100% — особое сообщение (с учётом рода обращения).
  final message = pct >= 1.0 ? Praise.forDayFull() : Praise.forDay(tier);
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(pct >= 1.0 ? 'День закрыт полностью!' : 'Награда за день'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
            const SizedBox(height: 8),
            Text('Выполнено $done из $total задач (${(pct * 100).round()}%)',
                style:
                    const TextStyle(color: AppTheme.textDim, fontSize: 12)),
            const SizedBox(height: 14),
            const Text('Выбери себе награду:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: chosen,
              isExpanded: true,
              decoration: const InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [
                for (final r in Praise.rewardIdeas)
                  DropdownMenuItem(
                    value: r,
                    child: Text(r,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
              ],
              onChanged: (v) => setState(() => chosen = v ?? chosen),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Пропустить'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.card_giftcard, size: 18),
            onPressed: () => Navigator.pop(ctx, chosen),
            label: const Text('Получить награду'),
          ),
        ],
      ),
    ),
  );
  // Любой исход (выбор, «Пропустить», кнопка «назад») фиксируется —
  // диалог на этом пороге сегодня больше НЕ всплывёт.
  final skipped = result == null || result.isEmpty;
  await store.logDayReward(
      day: day, tier: tier, pct: pct, reward: result ?? '', skipped: skipped);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(skipped
            ? 'Записал: награду пропустил(а) — учту в статистике.'
            : 'Награда записана. Наслаждайся — заслужил(а)!'),
      ),
    );
  }
}
