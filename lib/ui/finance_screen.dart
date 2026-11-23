/// Экран «Финансовый учёт»: доходы и расходы по источникам,
/// распределение по блокам годового плана (цвета совпадают с кругом
/// «Продуктивность по блокам») и итоги для анализа перераспределения.
/// Кнопка-кошелёк на экране «Статистика» открывает этот экран.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'block_wheel.dart';
import 'common.dart';
import 'finance_period_screen.dart';

/// Психоэмоциональная градация активов и пассивных расходов (1..5):
/// от самой тяжёлой (человечек с ношей) до самой радостной
/// (человечек в позе лотоса, «парящий»). Срединные — напряжённость,
/// нейтралитет, лёгкость/умиротворение.
const kFinEmotions = <(int, String, IconData, Color)>[
  (1, 'Тяжёлое — тяжёлая ноша', Icons.backpack_outlined, AppTheme.danger),
  (2, 'Напряжённое', Icons.sentiment_dissatisfied_outlined, AppTheme.warn),
  (3, 'Нейтральное', Icons.sentiment_neutral_outlined, AppTheme.textDim),
  (4, 'Лёгкость, умиротворение', Icons.sentiment_satisfied_outlined,
      AppTheme.done),
  (5, 'Радость — лотос над землёй', Icons.self_improvement_outlined,
      AppTheme.accent),
];

/// Периодичность пассивной статьи: код → подпись.
const kFinRecurNames = <String, String>{
  'day': 'ежедневно',
  'month': 'ежемесячно',
  'quarter': 'ежеквартально',
  'year': 'раз в год',
};

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  /// Число денег: 12 500 (без копеек, если сумма целая).
  static String fmtMoney(double v) {
    final neg = v < 0;
    var s = v.abs().toStringAsFixed(v.abs() == v.abs().roundToDouble() ? 0 : 2);
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');
    return '${neg ? '−' : ''}$intPart${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.finTotals();
    final now = DateTime.now();
    final month = store.finTotals(
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month + 1, 0, 23, 59));
    final byIncome = store.finBySource('income');
    final byExpense = store.finBySource('expense');
    final byBlock = store.finByBlock();
    final blocks = store.blockGoals();
    final entries = store.finEntries.toList()
      ..sort((a, b) => b.day.compareTo(a.day));

    String blockTitle(String code) {
      for (final b in blocks) {
        final bc = b.externalId.startsWith('block:')
            ? b.externalId.substring(6)
            : b.externalId;
        if (bc.toLowerCase().trim() == code.toLowerCase().trim()) {
          return b.title;
        }
      }
      return code.isEmpty ? 'Без блока' : code;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Финансовый учёт'),
        actions: [
          // Период: статистика, график движения денег, калькулятор.
          IconButton(
            icon: const Icon(Icons.date_range, color: AppTheme.accent),
            tooltip: 'Финансы за период',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const FinancePeriodScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          // --- Итоги ---
          Card(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Итоги',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 10),
                  _totalRow('За этот месяц', month.income, month.expense),
                  // Пассивные расходы вычитаются из доходов месяца —
                  // сразу видно, что остаётся свободным.
                  if (store.passiveMonthly('expense') > 0) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Пассивные расходы (в мес)',
                              style: TextStyle(
                                  color: AppTheme.textDim, fontSize: 13)),
                        ),
                        Text(
                          '−${fmtMoney(store.passiveMonthly('expense'))}',
                          style: const TextStyle(
                              color: AppTheme.danger, fontSize: 13),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'свободно: ${fmtMoney(month.income - store.passiveMonthly('expense'))}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: month.income -
                                        store.passiveMonthly('expense') >=
                                    0
                                ? AppTheme.done
                                : AppTheme.danger,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: 18),
                  _totalRow('За всё время', all.income, all.expense),
                  const SizedBox(height: 6),
                  const Text(
                      'Сопоставьте доходы и расходы по блокам — так видно, '
                      'куда уходят ресурсы и что стоит перераспределить.',
                      style:
                          TextStyle(color: AppTheme.textDim, fontSize: 11)),
                ],
              ),
            ),
          ),
          // --- Источники доходов ---
          SectionHeader('Источники доходов (${byIncome.length})',
              color: AppTheme.done),
          if (byIncome.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Пока нет записей о доходах',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            ),
          for (final e in byIncome.entries)
            _sourceTile(context, store, 'income', e.key, e.value,
                AppTheme.done),
          // --- Статьи расходов ---
          SectionHeader('Статьи расходов (${byExpense.length})',
              color: AppTheme.danger),
          if (byExpense.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Пока нет записей о расходах',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            ),
          for (final e in byExpense.entries)
            _sourceTile(context, store, 'expense', e.key, e.value,
                AppTheme.danger),
          // --- Распределение по блокам ---
          SectionHeader('Распределение по блокам (${byBlock.length})'),
          if (byBlock.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                  'Привяжите запись к блоку годового плана — появится '
                  'распределение, как в планировании по блокам.',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            ),
          for (final e in byBlock.entries)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: e.key.isEmpty
                        ? AppTheme.textDim
                        : BlockProductivityWheel.blockColorOf(store, e.key),
                    width: 1.2),
              ),
              child: ListTile(
                dense: true,
                title: Text(blockTitle(e.key),
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  [
                    if (e.value.income > 0) 'доход ${fmtMoney(e.value.income)}',
                    if (e.value.expense > 0)
                      'расход ${fmtMoney(e.value.expense)}',
                  ].join(' · '),
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 11),
                ),
                trailing: Text(
                  fmtMoney(e.value.income - e.value.expense),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: e.value.income - e.value.expense >= 0
                        ? AppTheme.done
                        : AppTheme.danger,
                  ),
                ),
                // Тап по карточке блока — записи этого блока, каждую
                // можно отредактировать.
                onTap: () {
                  final list = store.finEntries
                      .where((x) => x.block == e.key)
                      .toList()
                    ..sort((a, b) => b.day.compareTo(a.day));
                  _showEntriesSheet(
                      context, store, blockTitle(e.key), list);
                },
              ),
            ),
          // --- Активы (пассивный доход) ---
          SectionHeader(
            'Активы (${store.finPassive.where((e) => e.isAsset).length})',
            subtitle:
                'ресурсы, приносящие стабильный доход почти без участия',
            color: AppTheme.done,
          ),
          for (final e in store.finPassive.where((e) => e.isAsset))
            _passiveTile(context, store, e),
          _passiveTotalRow(store, 'asset'),
          _addPassiveButton(context, store, 'asset'),
          // --- Пассивные расходы ---
          SectionHeader(
            'Пассивные расходы (${store.finPassive.where((e) => !e.isAsset).length})',
            subtitle:
                'постоянные расходы: ежедневные, ежемесячные, ежеквартальные, раз в год — вычитаются из доходов',
            color: AppTheme.danger,
          ),
          for (final e in store.finPassive.where((e) => !e.isAsset))
            _passiveTile(context, store, e),
          _passiveTotalRow(store, 'expense'),
          _addPassiveButton(context, store, 'expense'),
          // --- Планируемые покупки ---
          SectionHeader(
            'Планируемые покупки (${store.finPurchases.length})',
            subtitle:
                'название, цена, цель инвестиции, срок и довод необходимости',
          ),
          for (final p in store.finPurchases)
            _purchaseTile(context, store, p),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: TextButton.icon(
                onPressed: () => _purchaseDialog(context, store),
                icon: const Icon(Icons.add_shopping_cart,
                    size: 18, color: AppTheme.accent),
                label: const Text('Запланировать покупку'),
              ),
            ),
          ),
          // --- Последние записи ---
          if (entries.isNotEmpty) SectionHeader('Записи (${entries.length})'),
          for (final e in entries.take(50))
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                dense: true,
                // Тап по записи — редактирование введённых данных.
                onTap: () => _entryDialog(context, store, existing: e),
                leading: Icon(
                  e.isIncome
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  size: 18,
                  color: e.isIncome ? AppTheme.done : AppTheme.danger,
                ),
                title: Text(
                  e.source.isEmpty
                      ? (e.isIncome ? 'Доход' : 'Расход')
                      : e.source,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  [
                    fmtDate(e.day),
                    if (e.block.isNotEmpty) blockTitle(e.block),
                    if (e.note.isNotEmpty) e.note,
                  ].join(' · '),
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${e.isIncome ? '+' : '−'}${fmtMoney(e.amount)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: e.isIncome ? AppTheme.done : AppTheme.danger,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 17, color: AppTheme.textDim),
                      tooltip: 'Убрать запись',
                      onPressed: () async {
                        await store.deleteFinEntry(e.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Запись убрана')));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addEntry(context, store),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ---------- Активы / пассивные расходы ----------

  (String, IconData, Color) _emotionOf(int v) {
    for (final e in kFinEmotions) {
      if (e.$1 == v) return (e.$2, e.$3, e.$4);
    }
    return (kFinEmotions[2].$2, kFinEmotions[2].$3, kFinEmotions[2].$4);
  }

  Widget _passiveTile(BuildContext context, AppStore store, FinPassive e) {
    final (label, icon, color) = _emotionOf(e.emotion);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.5), width: 1),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _passiveDialog(context, store, e.kind, existing: e),
        leading: Tooltip(
          message: label,
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
            e.title.isEmpty
                ? (e.isAsset ? 'Ресурс' : 'Статья расхода')
                : e.title,
            style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          [
            '${fmtMoney(e.amount)} ₽ · ${kFinRecurNames[e.recur] ?? e.recur}',
            'в месяц: ${fmtMoney(e.perMonth)} ₽',
            if (e.note.isNotEmpty) e.note,
          ].join(' · '),
          style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 17, color: AppTheme.textDim),
          tooltip: 'Убрать',
          onPressed: () => store.deleteFinPassive(e.id),
        ),
      ),
    );
  }

  /// Строка «ИТОГО» мини-блока — сумма, нормализованная к месяцу.
  Widget _passiveTotalRow(AppStore store, String kind) {
    final total = store.passiveMonthly(kind);
    final color = kind == 'asset' ? AppTheme.done : AppTheme.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Expanded(
            child: Text('ИТОГО (в месяц)',
                style: TextStyle(
                    color: AppTheme.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Text('${fmtMoney(total)} ₽',
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _addPassiveButton(BuildContext context, AppStore store, String kind) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 2),
        child: TextButton.icon(
          onPressed: () => _passiveDialog(context, store, kind),
          icon: Icon(
              kind == 'asset'
                  ? Icons.savings_outlined
                  : Icons.money_off_outlined,
              size: 18,
              color: AppTheme.accent),
          label: Text(kind == 'asset'
              ? 'Добавить актив'
              : 'Добавить пассивный расход'),
        ),
      ),
    );
  }

  /// Диалог актива / пассивного расхода: название, сумма, периодичность,
  /// психоэмоциональная градация (иконки 1..5) и заметка о состоянии.
  Future<void> _passiveDialog(BuildContext context, AppStore store,
      String kind,
      {FinPassive? existing}) async {
    final titleC = TextEditingController(text: existing?.title ?? '');
    final amountC = TextEditingController(
        text: existing != null && existing.amount > 0
            ? fmtMoney(existing.amount).replaceAll(' ', '')
            : '');
    final noteC = TextEditingController(text: existing?.note ?? '');
    String recur = existing?.recur ?? 'month';
    int emotion = existing?.emotion ?? 3;
    final isAsset = kind == 'asset';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            existing == null
                ? (isAsset ? 'Новый актив' : 'Новый пассивный расход')
                : (isAsset ? 'Править актив' : 'Править пассивный расход'),
            style: const TextStyle(fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleC,
                  decoration: InputDecoration(
                      hintText: isAsset
                          ? 'Название ресурса (вклад, аренда, подписка...)'
                          : 'Название статьи (аренда, интернет, подписки...)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: amountC,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            hintText: 'Сумма', suffixText: '₽'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: recur,
                        items: [
                          for (final r in kFinRecurNames.entries)
                            DropdownMenuItem(
                                value: r.key, child: Text(r.value)),
                        ],
                        onChanged: (v) => setS(() => recur = v ?? 'month'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Психоэмоциональная окраска',
                      style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final em in kFinEmotions)
                      Tooltip(
                        message: em.$2,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setS(() => emotion = em.$1),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: emotion == em.$1
                                  ? em.$4.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: emotion == em.$1
                                    ? em.$4
                                    : Colors.transparent,
                                width: 1.4,
                              ),
                            ),
                            child: Icon(em.$3,
                                size: 26,
                                color: emotion == em.$1
                                    ? em.$4
                                    : AppTheme.textDim),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_emotionOf(emotion).$1,
                      style: TextStyle(
                          color: _emotionOf(emotion).$3, fontSize: 11)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteC,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      hintText:
                          'Заметка: чем это состояние помогает или как негативно сказывается'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amount =
        double.tryParse(amountC.text.replaceAll(',', '.').replaceAll(' ', '')) ??
            0;
    if (amount <= 0) return;
    if (existing != null) {
      existing.title = titleC.text.trim();
      existing.amount = amount;
      existing.recur = recur;
      existing.emotion = emotion;
      existing.note = noteC.text.trim();
      await store.updateFinPassive(existing);
    } else {
      await store.addFinPassive(FinPassive(
        kind: kind,
        title: titleC.text.trim(),
        amount: amount,
        recur: recur,
        emotion: emotion,
        note: noteC.text.trim(),
      ));
    }
  }

  // ---------- Планируемые покупки ----------

  Widget _purchaseTile(BuildContext context, AppStore store, FinPurchase p) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: (p.term == 'long' ? AppTheme.warn : AppTheme.shortTerm)
                .withOpacity(0.5)),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _purchaseDialog(context, store, existing: p),
        leading: Icon(
          p.term == 'long' ? Icons.savings_outlined : Icons.shopping_bag_outlined,
          color: p.term == 'long' ? AppTheme.warn : AppTheme.shortTerm,
          size: 22,
        ),
        title: Text(
            p.title.isEmpty ? 'Покупка' : p.title,
            style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          [
            '${fmtMoney(p.price)} ₽',
            p.term == 'long' ? 'долгосрочная' : 'краткосрочная',
            if (p.goal.isNotEmpty) 'цель: ${p.goal}',
            if (p.reason.isNotEmpty) 'довод: ${p.reason}',
            if (p.note.isNotEmpty) p.note,
          ].join(' · '),
          style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 17, color: AppTheme.textDim),
          tooltip: 'Убрать',
          onPressed: () => store.deleteFinPurchase(p.id),
        ),
      ),
    );
  }

  /// Диалог планируемой покупки: название, цена, цель инвестиции, срок,
  /// примечание и обязательный вопрос-довод «необходима ли она именно
  /// в данном финансовом положении?».
  Future<void> _purchaseDialog(BuildContext context, AppStore store,
      {FinPurchase? existing}) async {
    final titleC = TextEditingController(text: existing?.title ?? '');
    final priceC = TextEditingController(
        text: existing != null && existing.price > 0
            ? fmtMoney(existing.price).replaceAll(' ', '')
            : '');
    final goalC = TextEditingController(text: existing?.goal ?? '');
    final noteC = TextEditingController(text: existing?.note ?? '');
    final reasonC = TextEditingController(text: existing?.reason ?? '');
    String term = existing?.term ?? 'short';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
              existing == null ? 'Запланировать покупку' : 'Править покупку',
              style: const TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleC,
                  decoration: const InputDecoration(hintText: 'Название'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      hintText: 'Цена', suffixText: '₽'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: goalC,
                  decoration:
                      const InputDecoration(hintText: 'Цель инвестиции'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Краткосрочная'),
                        selected: term == 'short',
                        onSelected: (_) => setS(() => term = 'short'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Долгосрочная'),
                        selected: term == 'long',
                        onSelected: (_) => setS(() => term = 'long'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteC,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(hintText: 'Примечание'),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppTheme.accent.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Крайне необходима ли эта покупка именно в данной '
                          'ситуации и оправдана ли она в данном финансовом '
                          'положении? Если да — почему?',
                          style: TextStyle(
                              color: AppTheme.accent, fontSize: 11)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: reasonC,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            hintText: 'Довод: почему необходима...'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final price =
        double.tryParse(priceC.text.replaceAll(',', '.').replaceAll(' ', '')) ??
            0;
    if (titleC.text.trim().isEmpty && price <= 0) return;
    if (existing != null) {
      existing.title = titleC.text.trim();
      existing.price = price;
      existing.goal = goalC.text.trim();
      existing.term = term;
      existing.note = noteC.text.trim();
      existing.reason = reasonC.text.trim();
      await store.updateFinPurchase(existing);
    } else {
      await store.addFinPurchase(FinPurchase(
        title: titleC.text.trim(),
        price: price,
        goal: goalC.text.trim(),
        term: term,
        note: noteC.text.trim(),
        reason: reasonC.text.trim(),
      ));
    }
  }

  Widget _totalRow(String label, double income, double expense) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style:
                    const TextStyle(color: AppTheme.textDim, fontSize: 13))),
        Text('+${fmtMoney(income)}',
            style: const TextStyle(color: AppTheme.done, fontSize: 13)),
        const SizedBox(width: 12),
        Text('−${fmtMoney(expense)}',
            style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
        const SizedBox(width: 12),
        Text(
          '= ${fmtMoney(income - expense)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: income - expense >= 0 ? AppTheme.done : AppTheme.danger,
          ),
        ),
      ],
    );
  }

  /// Карточка источника дохода / статьи расхода. Тап — список записей
  /// этого источника: каждую можно открыть и отредактировать.
  Widget _sourceTile(BuildContext context, AppStore store, String kind,
      String name, double sum, Color color) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.5), width: 1),
      ),
      child: ListTile(
        dense: true,
        title: Text(
            name.isEmpty ? (kind == 'income' ? 'Доход' : 'Расход') : name,
            style: const TextStyle(fontSize: 13)),
        trailing: Text(fmtMoney(sum),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        onTap: () {
          final entries = store.finEntries
              .where((e) => e.kind == kind && e.source == name)
              .toList()
            ..sort((a, b) => b.day.compareTo(a.day));
          _showEntriesSheet(context, store,
              name.isEmpty
                  ? (kind == 'income' ? 'Доход' : 'Расход')
                  : name,
              entries);
        },
      ),
    );
  }

  /// Шторка с записями (источник/статья/блок): тап по записи —
  /// окно редактирования её данных.
  void _showEntriesSheet(BuildContext context, AppStore store, String title,
      List<FinEntry> entries) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.textDim,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 10),
            Text('$title — записи (${entries.length}):',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (entries.isEmpty)
              const Text('Записей нет',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            for (final e in entries)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    e.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 18,
                    color: e.isIncome ? AppTheme.done : AppTheme.danger,
                  ),
                  title: Text(
                    '${e.isIncome ? '+' : '−'}${fmtMoney(e.amount)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    [
                      fmtDate(e.day),
                      if (e.source.isNotEmpty) e.source,
                      if (e.note.isNotEmpty) e.note,
                    ].join(' · '),
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 11),
                  ),
                  trailing: const Icon(Icons.edit_outlined,
                      size: 17, color: AppTheme.textDim),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _entryDialog(context, store, existing: e);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Добавление записи: вид (доход/расход), источник (с подсказками
  /// из уже встречавшихся), сумма, блок годового плана, заметка.
  Future<void> _addEntry(BuildContext context, AppStore store) =>
      _entryDialog(context, store);

  /// Окно записи финучёта: без [existing] — новая запись, с [existing] —
  /// редактирование сохранённой карточки (все поля предзаполнены,
  /// изменения пишутся в БД).
  Future<void> _entryDialog(BuildContext context, AppStore store,
      {FinEntry? existing}) async {
    var kind = existing?.kind ?? 'expense';
    final sourceC = TextEditingController(text: existing?.source ?? '');
    final amountC = TextEditingController(
        text: existing == null ? '' : fmtMoney(existing.amount));
    final noteC = TextEditingController(text: existing?.note ?? '');
    var block = existing?.block ?? '';
    final blocks = store.blockGoals();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final hints = store.finSources(kind);
          return AlertDialog(
            title: Text(existing == null
                ? 'Новая запись'
                : 'Редактировать запись'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'income',
                          label: Text('Доход'),
                          icon: Icon(Icons.arrow_downward, size: 16)),
                      ButtonSegment(
                          value: 'expense',
                          label: Text('Расход'),
                          icon: Icon(Icons.arrow_upward, size: 16)),
                    ],
                    selected: {kind},
                    onSelectionChanged: (v) =>
                        setD(() => kind = v.first),
                  ),
                  const SizedBox(height: 12),
                  Autocomplete<String>(
                    initialValue:
                        TextEditingValue(text: existing?.source ?? ''),
                    optionsBuilder: (v) => v.text.isEmpty
                        ? hints
                        : hints.where((h) =>
                            h.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (val) => sourceC.text = val,
                    fieldViewBuilder:
                        (ctx, c, focus, onSubmit) => TextField(
                              controller: c..addListener(() {
                                sourceC.text = c.text;
                              }),
                              focusNode: focus,
                              decoration: InputDecoration(
                                hintText: kind == 'income'
                                    ? 'Источник дохода (зарплата, подработка…)'
                                    : 'Статья расхода (продукты, транспорт…)',
                              ),
                            ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountC,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration:
                        const InputDecoration(hintText: 'Сумма'),
                  ),
                  const SizedBox(height: 10),
                  if (blocks.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: block,
                      decoration: const InputDecoration(
                          hintText: 'Блок годового плана'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Без блока')),
                        for (final b in blocks)
                          DropdownMenuItem(
                            value: b.externalId.startsWith('block:')
                                ? b.externalId.substring(6)
                                : b.externalId,
                            child: Text(b.title,
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setD(() => block = v ?? ''),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteC,
                    decoration: const InputDecoration(
                        hintText: 'Заметка (необязательно)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Сохранить')),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    final amount = double.tryParse(amountC.text
            .trim()
            .replaceAll(RegExp(r'\s'), '')
            .replaceAll(',', '.')) ??
        0;
    if (amount <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Укажите сумму больше нуля')));
      }
      return;
    }
    if (existing != null) {
      // Редактирование: запись остаётся на месте (id, дата), меняются
      // только введённые данные.
      existing
        ..kind = kind
        ..source = sourceC.text.trim()
        ..amount = amount
        ..block = block
        ..note = noteC.text.trim();
      await store.updateFinEntry(existing);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Запись обновлена')));
      }
      return;
    }
    await store.addFinEntry(FinEntry(
      kind: kind,
      source: sourceC.text.trim(),
      amount: amount,
      block: block,
      note: noteC.text.trim(),
    ));
  }
}
