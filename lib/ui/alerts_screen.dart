/// Экран «Оповещения»: все критические напоминания в одном месте —
/// просроченные дедлайны, ближайшие 24 часа, невыполненные ежедневные
/// привычки. Просроченное подсвечено и учитывается в статистике.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store.dart';
import '../theme.dart';
import 'common.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final alerts = store.criticalAlerts();

    return Scaffold(
      appBar: AppBar(title: const Text('Оповещения')),
      body: Column(
        children: [
          // Напоминания о дедлайнах: за время, равное 4× оценки выполнения
          // (15 мин -> за час, 1 день -> за 4 дня). Отключаются одним
          // переключателем. Горящие сроки подкрепляются настойчивой
          // «сиреной» критического канала.
          Card(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: SwitchListTile(
              secondary: Icon(
                store.remindersEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: store.remindersEnabled
                    ? AppTheme.accent
                    : AppTheme.textDim,
              ),
              title: const Text('Напоминания о дедлайнах',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Push за 4× времени выполнения; горящие — с сиреной',
                style: TextStyle(color: AppTheme.textDim, fontSize: 11),
              ),
              value: store.remindersEnabled,
              activeColor: AppTheme.accent,
              onChanged: (v) => store.setRemindersEnabled(v),
            ),
          ),
          Expanded(
            child: alerts.isEmpty
                ? const EmptyHint(
                    'Критических напоминаний нет. Всё под контролем!')
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 40, top: 6),
                    itemCount: alerts.length,
                    itemBuilder: (ctx, i) {
                      final a = alerts[i];
                      final (icon, color, label) = switch (a.kind) {
                        'overdue' =>
                          (Icons.error_outline, AppTheme.danger, 'Просрочено'),
                        'overload' => (
                            Icons.heart_broken,
                            AppTheme.critical,
                            'Перегруз плана'
                          ),
                        'soon' =>
                          (Icons.schedule, AppTheme.warn, 'Скоро дедлайн'),
                        _ => (Icons.repeat, AppTheme.daily, 'Привычка'),
                      };
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: a.kind == 'overdue' || a.kind == 'overload'
                              ? const BorderSide(
                                  color: AppTheme.critical, width: 1.2)
                              : BorderSide.none,
                        ),
                        child: ListTile(
                          leading: Icon(icon, color: color),
                          title: Text(a.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.detail,
                                  style: const TextStyle(
                                      color: AppTheme.textDim, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(label,
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
