/// «Стратегия на год»: загрузка tasks.json (file_picker) с распределением
/// по всем экранам приложения. Файл закрепляется и переживает перезапуск;
/// при загрузке нового файла старые импортированные данные заменяются.
library;

import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../import_tasks.dart';
import '../store.dart';
import '../theme.dart';
import 'common.dart';

class StrategyScreen extends StatefulWidget {
  const StrategyScreen({super.key});

  @override
  State<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends State<StrategyScreen> {
  String? _error;
  bool _loading = false;

  Future<void> _pick(AppStore store) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // FileType.any + ручная проверка расширения: кастомный фильтр
      // на части устройств падает с PlatformException «Unsupported filter».
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (res == null) {
        setState(() => _loading = false);
        return;
      }
      final f = res.files.single;
      if (!f.name.toLowerCase().endsWith('.json')) {
        throw const FormatException(
            'Это не JSON: выберите файл стратегии с расширением .json');
      }
      String raw;
      if (f.bytes != null) {
        raw = utf8.decode(f.bytes!);
      } else if (!kIsWeb && f.path != null) {
        raw = await File(f.path!).readAsString();
      } else {
        throw const FormatException('Не удалось прочитать файл');
      }
      // Файл полной выгрузки (сохранённый из «Статистики») восстанавливаем
      // 1-в-1; обычный tasks.json импортируем как стратегию.
      final message = AppStore.looksLikeFullBackup(raw)
          ? await store.restoreFullBackup(raw)
          : await store.importStrategy(raw, f.name);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } on FormatException catch (e) {
      setState(() {
        _error = 'Ошибка формата: ${e.message}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка чтения файла: $e';
        _loading = false;
      });
    }
  }

  Future<void> _unpin(AppStore store) async {
    await store.clearStrategy();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Файл отвязан, импортированные данные убраны')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = store.importedTasks;
    final fileName = store.importedFileName;
    final doneCount = items.where((t) => t.done).length;
    final byMonth = summarizeByMonth(items);

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        const SectionHeader(
          'Стратегия на год',
          subtitle: 'Загрузите tasks.json — задачи разойдутся по Целям, Задачам, '
              'Календарю и «Сегодня». Файл полной выгрузки (planner_export.json '
              'из «Статистики») восстановит все данные 1-в-1 после переустановки',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: _loading ? null : () => _pick(store),
            icon: const Icon(Icons.upload_file),
            label: Text(_loading
                ? 'Загрузка…'
                : fileName == null
                    ? 'Загрузить tasks.json'
                    : 'Заменить tasks.json'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.bg,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: AppTheme.warn, fontSize: 13)),
          ),
        if (fileName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.attach_file, size: 16, color: AppTheme.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Закреплён файл: $fileName',
                      style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _unpin(store),
                  child: const Text('Отвязать', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        if (items.isEmpty && _error == null)
          const EmptyHint('Файл не загружен'),
        if (items.isNotEmpty) ...[
          // Сводка
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _SummaryChip('Всего', items.length),
                const SizedBox(width: 8),
                _SummaryChip('Выполнено', doneCount),
                const SizedBox(width: 8),
                _SummaryChip(
                  'Прогресс',
                  items.isEmpty ? 0 : ((doneCount / items.length) * 100).round(),
                  suffix: '%',
                ),
              ],
            ),
          ),
          const SectionHeader('Диаграмма по месяцам'),
          SizedBox(height: 200, child: _MonthBarChart(data: byMonth)),
          const SectionHeader('Таблица задач'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppTheme.card),
              dataRowColor: WidgetStateProperty.all(AppTheme.bgDeep),
              columns: const [
                DataColumn(label: Text('Задача', style: TextStyle(color: AppTheme.accent))),
                DataColumn(label: Text('Блок', style: TextStyle(color: AppTheme.accent))),
                DataColumn(label: Text('Дедлайн', style: TextStyle(color: AppTheme.accent))),
                DataColumn(label: Text('Приоритет', style: TextStyle(color: AppTheme.accent))),
                DataColumn(label: Text('Статус', style: TextStyle(color: AppTheme.accent))),
              ],
              rows: [
                for (final t in items)
                  DataRow(cells: [
                    DataCell(SizedBox(
                      width: 200,
                      child: Text(t.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.text, fontSize: 13)),
                    )),
                    DataCell(Text(blockTitle(t.block),
                        style: const TextStyle(color: AppTheme.textDim, fontSize: 12))),
                    DataCell(Text(t.isDaily ? 'ежедневно' : (t.deadlineRaw.isEmpty ? '—' : t.deadlineRaw),
                        style: const TextStyle(color: AppTheme.textDim, fontSize: 12))),
                    DataCell(Text(t.priorityLetter,
                        style: const TextStyle(color: AppTheme.textDim, fontSize: 12))),
                    DataCell(Text(t.done ? 'Выполнено' : (t.status == 'in_progress' ? 'В работе' : 'Бэклог'),
                        style: TextStyle(
                            color: t.done ? AppTheme.done : AppTheme.warn, fontSize: 12))),
                  ]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final String suffix;
  const _SummaryChip(this.label, this.value, {this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text('$value$suffix',
                style: const TextStyle(
                    color: AppTheme.accent, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppTheme.textDim, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _MonthBarChart extends StatelessWidget {
  final Map<String, ({int total, int done})> data;
  const _MonthBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final keys = data.keys.toList();
    if (keys.isEmpty) return const EmptyHint('Нет данных');
    final maxY = data.values.fold<int>(1, (m, v) => v.total > m ? v.total : m).toDouble();

    String label(String k) {
      if (k == 'daily') return 'ежедн.';
      if (k.length >= 7) return k.substring(5); // MM из YYYY-MM
      return k;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: BarChart(
        BarChartData(
          maxY: maxY,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= keys.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label(keys[i]),
                        style: const TextStyle(color: AppTheme.textDim, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < keys.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[keys[i]]!.total.toDouble(),
                    color: AppTheme.accent,
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  BarChartRodData(
                    toY: data[keys[i]]!.done.toDouble(),
                    color: AppTheme.done,
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
