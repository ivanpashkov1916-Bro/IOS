/// Финансы за период: выбор периода (пресеты + произвольный диапазон),
/// итоги, график движения денег (накопительные кривые доходов и
/// расходов с автоматической гранулярностью от минуты до года),
/// точки пересечения кривых — «точки безубыточности» с позитивной
/// отметкой, доли блоков в % от итогов периода и калькулятор
/// «сумма ÷ интервал = значение за единицу времени».
/// Открывается иконкой календаря на экране «Финансовый учёт».
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'finance_screen.dart' show FinanceScreen;

/// Одно деление графика: начало интервала + накопленные суммы.
class _Bucket {
  final DateTime at;
  final double income; // накопительный доход к концу деления
  final double expense; // накопительный расход
  const _Bucket(this.at, this.income, this.expense);
}

class FinancePeriodScreen extends StatefulWidget {
  const FinancePeriodScreen({super.key});

  @override
  State<FinancePeriodScreen> createState() => _FinancePeriodScreenState();
}

class _FinancePeriodScreenState extends State<FinancePeriodScreen> {
  // null = «всё время»
  DateTime? _from;
  DateTime? _to;
  String _preset = 'month';

  bool _showIncome = true;
  bool _showExpense = true;

  /// Предупреждение о замедлении показываем один раз за открытие экрана
  /// (убирается крестиком; вернётся при следующем входе, если тренд
  /// не исправлен).
  bool _warned = false;

  // Калькулятор-конвертер: сумма за интервал-источник → значение
  // за целевой интервал (16 800 ₽ за 1 неделю → 100 ₽/час).
  final _sumC = TextEditingController();
  final _srcCountC = TextEditingController(text: '1');
  String _srcUnit = 'week'; // minute|hour|day|week|month|year
  String _dstUnit = 'hour';
  bool _calcIncome = true;

  @override
  void initState() {
    super.initState();
    _applyPreset('month');
  }

  @override
  void dispose() {
    _sumC.dispose();
    _srcCountC.dispose();
    super.dispose();
  }

  void _applyPreset(String p) {
    final now = DateTime.now();
    setState(() {
      _preset = p;
      switch (p) {
        case 'day':
          _from = DateTime(now.year, now.month, now.day);
          _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'week':
          final monday = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _from = monday;
          _to = monday.add(const Duration(days: 7))
              .subtract(const Duration(seconds: 1));
          break;
        case 'month':
          _from = DateTime(now.year, now.month, 1);
          _to = DateTime(now.year, now.month + 1, 1)
              .subtract(const Duration(seconds: 1));
          break;
        case 'quarter':
          final qm = ((now.month - 1) ~/ 3) * 3 + 1;
          _from = DateTime(now.year, qm, 1);
          _to = DateTime(now.year, qm + 3, 1)
              .subtract(const Duration(seconds: 1));
          break;
        case 'year':
          _from = DateTime(now.year, 1, 1);
          _to = DateTime(now.year, 12, 31, 23, 59, 59);
          break;
        default: // all
          _from = null;
          _to = null;
      }
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
      initialDateRange: (_from != null && _to != null)
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (r == null) return;
    setState(() {
      _preset = 'custom';
      _from = r.start;
      _to = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
    });
  }

  /// Записи периода.
  List<FinEntry> _entriesIn(AppStore store) {
    return store.finEntries.where((e) {
      if (_from != null && e.day.isBefore(_from!)) return false;
      if (_to != null && e.day.isAfter(_to!)) return false;
      return true;
    }).toList();
  }

  /// Автогранулярность: от минуты (короткий диапазон) до года
  /// (очень длинный). Возвращает функцию «пола» даты и подпись деления.
  (DateTime Function(DateTime), String Function(DateTime)) _granularity(
      DateTime from, DateTime to) {
    final span = to.difference(from);
    if (span <= const Duration(hours: 6)) {
      return (
        (d) => DateTime(d.year, d.month, d.day, d.hour, d.minute),
        (d) => fmtTime(d),
      );
    }
    if (span <= const Duration(days: 3)) {
      return (
        (d) => DateTime(d.year, d.month, d.day, d.hour),
        (d) => '${two(d.day)}.${two(d.month)} ${two(d.hour)}:00',
      );
    }
    if (span <= const Duration(days: 62)) {
      return (
        (d) => DateTime(d.year, d.month, d.day),
        (d) => '${two(d.day)}.${two(d.month)}',
      );
    }
    if (span <= const Duration(days: 370)) {
      return (
        (d) => DateTime(d.year, d.month, d.day)
            .subtract(Duration(days: d.weekday - 1)),
        (d) => '${two(d.day)}.${two(d.month)}',
      );
    }
    if (span <= const Duration(days: 365 * 6)) {
      return (
        (d) => DateTime(d.year, d.month),
        (d) => '${two(d.month)}.${d.year}',
      );
    }
    return ((d) => DateTime(d.year), (d) => '${d.year}');
  }

  /// Накопительные кривые по делениям периода.
  List<_Bucket> _buckets(List<FinEntry> entries) {
    final from = _from ??
        (entries.isEmpty
            ? DateTime.now()
            : entries
                .map((e) => e.day)
                .reduce((a, b) => a.isBefore(b) ? a : b));
    final to = _to ?? DateTime.now();
    final (floor, _) = _granularity(from, to);
    final raw = <DateTime, (double, double)>{};
    for (final e in entries) {
      final k = floor(e.day);
      final cur = raw[k] ?? (0.0, 0.0);
      raw[k] = e.isIncome
          ? (cur.$1 + e.amount, cur.$2)
          : (cur.$1, cur.$2 + e.amount);
    }
    final keys = raw.keys.toList()..sort();
    final out = <_Bucket>[];
    var inc = 0.0, exp = 0.0;
    for (final k in keys) {
      inc += raw[k]!.$1;
      exp += raw[k]!.$2;
      out.add(_Bucket(k, inc, exp));
    }
    return out;
  }

  String get _periodLabel {
    if (_from == null || _to == null) return 'Всё время';
    return '${fmtDate(_from!)} — ${fmtDate(_to!)}';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final entries = _entriesIn(store);
    var inc = 0.0, exp = 0.0;
    for (final e in entries) {
      if (e.isIncome) {
        inc += e.amount;
      } else {
        exp += e.amount;
      }
    }
    final buckets = _buckets(entries);

    // Тренд последних 7 дней (по всем записям, независимо от выбранного
    // периода): расходы превышают доходы — «замедление»: оранжевая
    // подложка графика + одноразовое предупреждение с крестиком.
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    var incW = 0.0, expW = 0.0;
    for (final e in store.finEntries) {
      if (e.day.isBefore(weekAgo)) continue;
      if (e.isIncome) {
        incW += e.amount;
      } else {
        expW += e.amount;
      }
    }
    final slowdown = expW > incW;
    if (slowdown && !_warned) {
      _warned = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showSlowdownWarning());
    }

    // Доли блоков в % от итогов периода.
    final byBlock = <String, (double, double)>{};
    for (final e in entries) {
      final cur = byBlock[e.block] ?? (0.0, 0.0);
      byBlock[e.block] = e.isIncome
          ? (cur.$1 + e.amount, cur.$2)
          : (cur.$1, cur.$2 + e.amount);
    }
    String blockTitle(String code) {
      for (final b in store.blockGoals()) {
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
          title: const Text('Финансы за период',
              style: TextStyle(fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          // --- Выбор периода ---
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in const [
                  ('day', 'День'),
                  ('week', 'Неделя'),
                  ('month', 'Месяц'),
                  ('quarter', 'Квартал'),
                  ('year', 'Год'),
                  ('all', 'Всё'),
                ])
                  ChoiceChip(
                    label: Text(p.$2),
                    selected: _preset == p.$1,
                    onSelected: (_) => _applyPreset(p.$1),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 17),
                  label: Text(_preset == 'custom' ? _periodLabel : 'Свой…'),
                  onPressed: _pickRange,
                ),
              ],
            ),
          ),
          // --- Итоги периода ---
          Card(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_periodLabel,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: _stat('Доходы', inc, AppTheme.done)),
                      Expanded(
                          child: _stat('Расходы', exp, AppTheme.danger)),
                      Expanded(
                          child: _stat('Баланс', inc - exp,
                              inc >= exp ? AppTheme.accent : AppTheme.warn)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Результирующая: текущий тренд графика за период.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (inc >= exp ? AppTheme.done : AppTheme.warn)
                          .withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: inc >= exp ? AppTheme.done : AppTheme.warn),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          inc >= exp
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 16,
                          color: inc >= exp ? AppTheme.done : AppTheme.warn,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          inc >= exp
                              ? 'Результирующая: позитивная'
                              : 'Результирующая: замедление',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color:
                                inc >= exp ? AppTheme.done : AppTheme.warn,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // --- График движения денег ---
          Card(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            // При замедлении (расходы > доходов за неделю) — вызывающая
            // оранжевая подложка; возвращается в норму сама.
            color: slowdown ? const Color(0xFF3A2A1C) : null,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: slowdown
                    ? const BorderSide(color: Color(0xFFE0A05C), width: 1.2)
                    : BorderSide.none),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Движение денег',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      _curveToggle('Доходы', AppTheme.done, _showIncome,
                          () => setState(() {
                                _showIncome = !_showIncome;
                                if (!_showIncome && !_showExpense) {
                                  _showExpense = true;
                                }
                              })),
                      const SizedBox(width: 6),
                      _curveToggle('Расходы', AppTheme.danger, _showExpense,
                          () => setState(() {
                                _showExpense = !_showExpense;
                                if (!_showIncome && !_showExpense) {
                                  _showIncome = true;
                                }
                              })),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (buckets.length < 2)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                            'За этот период слишком мало записей для графика',
                            style: TextStyle(
                                color: AppTheme.textDim, fontSize: 12)),
                      ),
                    )
                  else
                    SizedBox(
                      height: 220,
                      child: CustomPaint(
                        painter: _FinChartPainter(
                          buckets: buckets,
                          showIncome: _showIncome,
                          showExpense: _showExpense,
                          labelOf: _granularity(
                                  _from ?? buckets.first.at,
                                  _to ?? DateTime.now())
                              .$2,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  if (buckets.length >= 2 &&
                      _showIncome &&
                      _showExpense) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (ctx) {
                      final xs = _breakEvenPoints(buckets);
                      if (xs.isEmpty) {
                        return const Text(
                            'Кривые не пересекались: доходы и расходы '
                            'не сравнивались накопительно',
                            style: TextStyle(
                                color: AppTheme.textDim, fontSize: 11));
                      }
                      return Row(
                        children: [
                          const Icon(Icons.sentiment_satisfied_alt,
                              size: 16, color: AppTheme.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Точки безубыточности (${xs.length}): '
                              '${xs.map((d) => _granularity(_from ?? d, _to ?? DateTime.now()).$2(d)).join(' · ')}',
                              style: const TextStyle(
                                  color: AppTheme.accent, fontSize: 11),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          // --- Доли блоков в % от итогов периода ---
          if (byBlock.isNotEmpty)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Доли блоков за период',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text('Процент — от итога периода по виду (доходы '
                        'или расходы)',
                        style: TextStyle(
                            color: AppTheme.textDim, fontSize: 11)),
                    const SizedBox(height: 8),
                    for (final e in byBlock.entries.toList()
                      ..sort((a, b) => (b.value.$1 + b.value.$2)
                          .compareTo(a.value.$1 + a.value.$2))) ...[
                      if (e.value.$1 > 0 && inc > 0)
                        _shareRow(blockTitle(e.key), 'доходы', e.value.$1,
                            e.value.$1 / inc, AppTheme.done),
                      if (e.value.$2 > 0 && exp > 0)
                        _shareRow(blockTitle(e.key), 'расходы', e.value.$2,
                            e.value.$2 / exp, AppTheme.danger),
                    ],
                  ],
                ),
              ),
            ),
          // --- Калькулятор ---
          Card(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Builder(builder: (ctx) => _buildCalculator(ctx)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, double v, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textDim, fontSize: 11)),
          const SizedBox(height: 2),
          Text('${FinanceScreen.fmtMoney(v)} ₽',
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _curveToggle(
          String label, Color color, bool on, VoidCallback onTap) =>
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          SystemSound.play(SystemSoundType.click);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? color.withOpacity(0.18) : AppTheme.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: on ? color : AppTheme.textDim.withOpacity(0.35)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: on ? color : AppTheme.textDim,
                  fontWeight: FontWeight.w600)),
        ),
      );

  Widget _shareRow(
      String title, String kind, double sum, double share, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$title · $kind',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(
                  '${FinanceScreen.fmtMoney(sum)} ₽ · ${(share * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppTheme.bg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  /// Точки пересечения накопительных кривых (смена знака разницы).
  static List<DateTime> _breakEvenPoints(List<_Bucket> bs) {
    final out = <DateTime>[];
    for (var i = 1; i < bs.length; i++) {
      final prev = bs[i - 1].income - bs[i - 1].expense;
      final cur = bs[i].income - bs[i].expense;
      if ((prev < 0 && cur >= 0) || (prev > 0 && cur <= 0)) {
        out.add(bs[i].at);
      }
    }
    return out;
  }

  /// Всплывающее предупреждение о замедлении (один раз за открытие
  /// экрана, убирается крестиком).
  void _showSlowdownWarning() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF3A2A1C),
        title: Row(
          children: [
            const Expanded(
              child: Text('Внимание! Проведите аудит!',
                  style:
                      TextStyle(fontSize: 16, color: Color(0xFFE0A05C))),
            ),
            IconButton(
              icon: const Icon(Icons.close,
                  size: 20, color: AppTheme.textDim),
              tooltip: 'Закрыть',
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: const Text(
            'За последнюю неделю расходы превышают доходы — результирующая '
            '«замедление». Подложка графика подсвечена оранжевым; когда '
            'доходы сравняются с расходами или кривая доходов пойдёт вверх, '
            'оформление вернётся в стандартный режим.',
            style: TextStyle(fontSize: 13)),
      ),
    );
  }

  // --- Калькулятор-конвертер: сумма за интервал → за единицу целевого ---
  static const _unitMinutes = <String, double>{
    'minute': 1,
    'hour': 60,
    'day': 1440,
    'week': 10080,
    'month': 43200, // 30 дней
    'year': 525600, // 365 дней
  };
  static const _unitNames = <String, String>{
    'minute': 'минут',
    'hour': 'часов',
    'day': 'дней',
    'week': 'недель',
    'month': 'месяцев',
    'year': 'лет',
  };
  // Винительный падеж для «₽/час», «₽/неделю»...
  static const _unitAcc = <String, String>{
    'minute': 'минуту',
    'hour': 'час',
    'day': 'день',
    'week': 'неделю',
    'month': 'месяц',
    'year': 'год',
  };

  Widget _buildCalculator(BuildContext ctx) {
    final sum = double.tryParse(
            _sumC.text.replaceAll(',', '.').replaceAll(' ', '')) ??
        0;
    final n = double.tryParse(_srcCountC.text.replaceAll(',', '.')) ?? 0;
    final srcMinutes = n * (_unitMinutes[_srcUnit] ?? 1);
    final perMin = (sum > 0 && srcMinutes > 0) ? sum / srcMinutes : 0.0;
    final dstMin = _unitMinutes[_dstUnit] ?? 1;
    // Сколько целевых единиц помещается в интервал-источник (168 ч в неделе).
    final dstCount = srcMinutes / dstMin;
    final word = _calcIncome ? 'доход' : 'расход';
    final color = _calcIncome ? AppTheme.done : AppTheme.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Калькулятор стоимости времени',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        const Text(
            'Сумма ÷ интервал, за который она сложилась = значение за '
            'целевой интервал: 16 800 ₽ за 1 неделю → 100 ₽/час.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
        const SizedBox(height: 10),
        TextField(
          controller: _sumC,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Сумма', hintText: '16 800', suffixText: '₽'),
        ),
        const SizedBox(height: 8),
        // Интервал, ЗА КОТОРЫЙ сложилась сумма: число + единица.
        Row(
          children: [
            const Text('за',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextField(
                controller: _srcCountC,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: '1'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _srcUnit,
                decoration:
                    const InputDecoration(hintText: 'интервал суммы'),
                items: [
                  for (final u in _unitNames.entries)
                    DropdownMenuItem(value: u.key, child: Text(u.value)),
                ],
                onChanged: (v) => setState(() => _srcUnit = v ?? 'week'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Доход'),
              selected: _calcIncome,
              onSelected: (_) => setState(() => _calcIncome = true),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Расход'),
              selected: !_calcIncome,
              onSelected: (_) => setState(() => _calcIncome = false),
            ),
            const Spacer(),
            // Целевой интервал: В ЧЁМ нужен ответ.
            const Text('в',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _dstUnit,
              underline: Container(height: 1, color: AppTheme.accent),
              items: [
                for (final u in _unitAcc.entries)
                  DropdownMenuItem(value: u.key, child: Text(u.value)),
              ],
              onChanged: (v) => setState(() => _dstUnit = v ?? 'hour'),
            ),
          ],
        ),
        if (perMin > 0) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${FinanceScreen.fmtMoney(sum)} ₽ ÷ '
                    '${FinanceScreen.fmtMoney(dstCount)} ${_unitNames[_dstUnit]} =',
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                    '${FinanceScreen.fmtMoney(perMin * dstMin)} '
                    '₽/${_unitAcc[_dstUnit]} — $word',
                    style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('В других интервалах:',
                    style:
                        TextStyle(color: AppTheme.textDim, fontSize: 11)),
                const SizedBox(height: 2),
                for (final u in _unitMinutes.keys)
                  if (u != _dstUnit)
                    Text(
                        '${FinanceScreen.fmtMoney(perMin * (_unitMinutes[u] ?? 1))} '
                        '₽/${_unitAcc[u]}',
                        style: const TextStyle(
                            color: AppTheme.textDim, fontSize: 12)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// График движения денег: накопительные кривые доходов (зелёная)
/// и расходов (красная), сетка, подписи делений и точки
/// безубыточности — позитивный смайлик в месте пересечения.
class _FinChartPainter extends CustomPainter {
  final List<_Bucket> buckets;
  final bool showIncome;
  final bool showExpense;
  final String Function(DateTime) labelOf;

  _FinChartPainter({
    required this.buckets,
    required this.showIncome,
    required this.showExpense,
    required this.labelOf,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 46.0, bottomPad = 22.0, topPad = 10.0, rightPad = 8.0;
    final w = size.width - leftPad - rightPad;
    final h = size.height - topPad - bottomPad;
    if (w <= 0 || h <= 0 || buckets.length < 2) return;

    var maxY = 1.0;
    for (final b in buckets) {
      if (showIncome && b.income > maxY) maxY = b.income;
      if (showExpense && b.expense > maxY) maxY = b.expense;
    }
    maxY *= 1.08;

    double xAt(int i) => leftPad + w * i / (buckets.length - 1);
    double yAt(double v) => topPad + h * (1 - v / maxY);

    // Сетка и подписи сумм слева.
    final grid = Paint()
      ..color = AppTheme.textDim.withOpacity(0.14)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
        color: AppTheme.textDim.withOpacity(0.9), fontSize: 9.5);
    for (var g = 0; g <= 4; g++) {
      final v = maxY * g / 4;
      final y = yAt(v);
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + w, y), grid);
      final tp = TextPainter(
          text: TextSpan(
              text: FinanceScreen.fmtMoney(v), style: labelStyle),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: leftPad - 4);
      tp.paint(canvas, Offset(leftPad - 4 - tp.width, y - 6));
    }

    // Подписи делений снизу: первое, середина, последнее.
    for (final i in {0, (buckets.length - 1) ~/ 2, buckets.length - 1}) {
      final tp = TextPainter(
          text: TextSpan(text: labelOf(buckets[i].at), style: labelStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      var dx = xAt(i) - tp.width / 2;
      dx = dx.clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, size.height - bottomPad + 6));
    }

    void drawCurve(List<double> vals, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(xAt(0), yAt(vals[0]));
      for (var i = 1; i < vals.length; i++) {
        path.lineTo(xAt(i), yAt(vals[i]));
      }
      canvas.drawPath(path, paint);
      // Заливка под кривой — полупрозрачная.
      final fill = Paint()
        ..color = color.withOpacity(0.08)
        ..style = PaintingStyle.fill;
      final fp = Path.from(path)
        ..lineTo(xAt(vals.length - 1), yAt(0))
        ..lineTo(xAt(0), yAt(0))
        ..close();
      canvas.drawPath(fp, fill);
      // Точки на кривой — по датам внесения записей (каждое деление
      // графика соответствует внесённым доходам/расходам).
      final dot = Paint()..color = color;
      for (var i = 0; i < vals.length; i++) {
        canvas.drawCircle(Offset(xAt(i), yAt(vals[i])), 2.6, dot);
      }
    }

    final incVals = buckets.map((b) => b.income).toList();
    final expVals = buckets.map((b) => b.expense).toList();
    if (showExpense) drawCurve(expVals, AppTheme.danger);
    if (showIncome) drawCurve(incVals, AppTheme.done);

    // Точки безубыточности: пересечения кривых — смайлик.
    if (showIncome && showExpense) {
      for (var i = 1; i < buckets.length; i++) {
        final prev = incVals[i - 1] - expVals[i - 1];
        final cur = incVals[i] - expVals[i];
        if ((prev < 0 && cur >= 0) || (prev > 0 && cur <= 0)) {
          // Интерполяция позиции пересечения между делениями.
          final frac =
              prev == cur ? 0.5 : (0 - prev) / (cur - prev);
          final fx = xAt(i - 1) + (xAt(i) - xAt(i - 1)) * frac;
          final fv = incVals[i - 1] +
              (incVals[i] - incVals[i - 1]) * frac;
          _drawSmiley(canvas, Offset(fx, yAt(fv)), 9);
        }
      }
    }
  }

  /// Позитивная отметка точки безубыточности — смайлик.
  void _drawSmiley(Canvas canvas, Offset c, double r) {
    final fill = Paint()..color = AppTheme.bg;
    final line = Paint()
      ..color = AppTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final dot = Paint()..color = AppTheme.accent;
    canvas.drawCircle(c, r, fill);
    canvas.drawCircle(c, r, line);
    canvas.drawCircle(Offset(c.dx - r * 0.34, c.dy - r * 0.22), r * 0.13, dot);
    canvas.drawCircle(Offset(c.dx + r * 0.34, c.dy - r * 0.22), r * 0.13, dot);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(c.dx, c.dy + r * 0.05), radius: r * 0.55),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(_FinChartPainter old) =>
      old.buckets != buckets ||
      old.showIncome != showIncome ||
      old.showExpense != showExpense;
}
