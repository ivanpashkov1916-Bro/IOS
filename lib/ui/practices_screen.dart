/// Практики (по Палиенко/Зеланд): семь пошаговых мастеров-диалогов
/// (№1, 3, 4, 6, 7, 8, 9) в четырёх стилях оформления на выбор:
/// А «Сад», Б «Ритуал», В «Созвездия», Г «Карта дня».
/// Каждая практика — диалог по шагам в духе «Три плюса дня»: строка
/// ответа → уточняющий вопрос («почему это было хорошо? Поделишься?»)
/// → «приятно-принято» или пропуск → финальная подсказка.
/// Результат — запись дневника (kind='practice'): видна на экране
/// «Заметки», входит в полную JSON-выгрузку.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';

/// Один шаг практики: задание + необязательный уточняющий вопрос.
class PracticeStep {
  final String prompt;
  final String? why;
  const PracticeStep(this.prompt, {this.why});
}

/// Описание практики.
class PracticeDef {
  final String id;
  final int number;
  final String title;
  final String desc;
  final String tip; // финальная подсказка после последнего шага
  final List<PracticeStep> steps;
  const PracticeDef({
    required this.id,
    required this.number,
    required this.title,
    required this.desc,
    required this.tip,
    required this.steps,
  });
}

/// Семь практик (утверждённый набор: №1, 3, 4, 6, 7, 8, 9).
const kPractices = <PracticeDef>[
  PracticeDef(
    id: 'p1',
    number: 1,
    title: 'Три плюса дня',
    desc: 'Вечером — три хорошие вещи дня и почему они были хороши.',
    tip: 'Вспомни ещё раз все три — и насладись. Так день закрывается '
        'на тёплой ноте.',
    steps: [
      PracticeStep('Первая хорошая вещь сегодняшнего дня — что это было?',
          why: 'Почему это было хорошо? Поделишься?'),
      PracticeStep('Вторая хорошая вещь дня?',
          why: 'Почему это было хорошо? Поделишься?'),
      PracticeStep('И третья — какая она?',
          why: 'Почему это было хорошо? Поделишься?'),
    ],
  ),
  PracticeDef(
    id: 'p3',
    number: 3,
    title: 'Слайд на 60 секунд',
    desc: 'Утром — 60 секунд сцены цели и одно действие вслух.',
    tip: 'Зажги этот слайд ещё раз на 60 секунд — прямо сейчас, '
        'с закрытыми глазами.',
    steps: [
      PracticeStep(
          'Закрой глаза и представь одну сцену: цель достигнута. '
          'Что ты видишь? Опиши этот кадр.',
          why: 'Что ты чувствуешь внутри этого кадра?'),
      PracticeStep(
          'Назови (и запиши) одно действие, которое приближает этот '
          'кадр, — что сделаешь сегодня?'),
    ],
  ),
  PracticeDef(
    id: 'p4',
    number: 4,
    title: 'Снижение важности: «а что, если»',
    desc: 'Две минуты письменно: худший сценарий, реакция, план Б.',
    tip: 'Важность снижена: худшее проговорено, план Б есть. '
        'Возвращайся к делу спокойно.',
    steps: [
      PracticeStep('Что за задача или ситуация сейчас давит важностью?'),
      PracticeStep('А что, если не получится? Опиши худший сценарий.',
          why: 'Что ты почувствуешь, если это случится?'),
      PracticeStep('Как ты отреагируешь? Что сделаешь тогда?'),
      PracticeStep('План Б: какое действие-подстраховка придумаешь?'),
    ],
  ),
  PracticeDef(
    id: 'p6',
    number: 6,
    title: 'Формулировка намерения',
    desc: 'Одна строка: результат, дата и первый шаг сегодня.',
    tip: 'Намерение записано — оно уже работает. Вернись к строке '
        'вечером и отметь первый шаг.',
    steps: [
      PracticeStep(
          'Напиши строку намерения: «Я намерен(а) [результат] '
          'к [дата]».'),
      PracticeStep('Первый шаг — какое действие и во сколько сегодня? '
          '(«первый шаг — [действие] сегодня в [время]»)'),
    ],
  ),
  PracticeDef(
    id: 'p7',
    number: 7,
    title: 'Удовольствие как компас',
    desc: 'Один приятный элемент к рутинной задаче.',
    tip: 'Заметь, как изменилось ощущение от задачи. Компас работает.',
    steps: [
      PracticeStep('Какая рутинная задача ждёт тебя?'),
      PracticeStep(
          'Какой один приятный элемент добавишь к ней? '
          '(музыка, чай, свеча, другое место…)',
          why: 'Почему именно это будет приятно?'),
    ],
  ),
  PracticeDef(
    id: 'p8',
    number: 8,
    title: 'Честный лист',
    desc: 'Что говорю → что делаю → расхождение → действие.',
    tip: 'Честность с собой — уже шаг. Одно действие записано — '
        'сделай его сегодня.',
    steps: [
      PracticeStep('Что я говорю, что делаю? (какие обещания себе?)'),
      PracticeStep('Что я реально делаю?'),
      PracticeStep('Где расхождение между словами и делами?',
          why: 'Что стоит за этим расхождением?'),
      PracticeStep('Одно действие, чтобы сблизить слова и дела?'),
    ],
  ),
  PracticeDef(
    id: 'p9',
    number: 9,
    title: 'Течение дня',
    desc: 'Утром — один главный пункт, днём — одно «да», вечером — строка.',
    tip: 'День потёк по-твоему. Вечером вернись и допиши строку итога.',
    steps: [
      PracticeStep('Утро: один главный пункт сегодня — какой?'),
      PracticeStep('День: одно осознанное «да» — чему ты скажешь «да»?',
          why: 'Почему этому — «да»?'),
      PracticeStep('Вечер: одна строка итога — что напишешь?'),
    ],
  ),
];

/// Стиль оформления практик.
class PracticeStyle {
  final String id; // 'garden' | 'ritual' | 'stars' | 'card'
  final String letter;
  final String name;
  final String desc;
  final IconData icon;
  const PracticeStyle(this.id, this.letter, this.name, this.desc, this.icon);
}

const kPracticeStyles = <PracticeStyle>[
  PracticeStyle('garden', 'А', 'Сад',
      'Каждая практика — растение: 7 дней — цветок, 21 — дерево. '
      'Сад растёт от регулярности.', Icons.park_outlined),
  PracticeStyle('ritual', 'Б', 'Ритуал',
      'Вечерний ритуал: спокойный полноэкранный диалог, '
      'шаг за шагом, без спешки.', Icons.self_improvement_outlined),
  PracticeStyle('stars', 'В', 'Созвездия',
      'Каждое выполнение — звезда: семь звёзд складываются '
      'в созвездие.', Icons.auto_awesome_outlined),
  PracticeStyle('card', 'Г', 'Карта дня',
      'Практика как карта дня: принять карту — и пройти её '
      'по шагам.', Icons.style_outlined),
];

/// Экран выбора: сначала стиль оформления, затем практика из семи.
class PracticesScreen extends StatefulWidget {
  const PracticesScreen({super.key});

  @override
  State<PracticesScreen> createState() => _PracticesScreenState();
}

class _PracticesScreenState extends State<PracticesScreen> {
  String _styleId = 'garden';

  PracticeStyle get _style =>
      kPracticeStyles.firstWhere((s) => s.id == _styleId);

  /// Сколько раз практика пройдена (по записям дневника).
  int _completions(AppStore store, String practiceId) => store.diaryEntries
      .where((e) => e.kind == 'practice' && e.practiceId == practiceId)
      .length;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Практики')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('Стиль оформления',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          SizedBox(
            height: 132,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in kPracticeStyles)
                  _styleCard(s, s.id == _styleId),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('Практика',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          for (final p in kPractices)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.card,
                  child: Text('${p.number}',
                      style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w700)),
                ),
                title: Text(p.title, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  '${p.desc}'
                  '${_completions(store, p.id) > 0 ? '\nПройдено: ${_completions(store, p.id)}' : ''}',
                  style:
                      const TextStyle(color: AppTheme.textDim, fontSize: 11),
                ),
                isThreeLine: _completions(store, p.id) > 0,
                trailing:
                    const Icon(Icons.play_arrow, color: AppTheme.accent),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          PracticeWizardScreen(practice: p, style: _style)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _styleCard(PracticeStyle s, bool selected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _styleId = s.id),
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppTheme.accent : Colors.transparent,
                width: 1.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(s.icon,
                      size: 18,
                      color: selected ? AppTheme.accent : AppTheme.textDim),
                  const SizedBox(width: 6),
                  Text('${s.letter} «${s.name}»',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              selected ? AppTheme.accent : AppTheme.text)),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(s.desc,
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 10.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пошаговый мастер практики: задание → ответ → уточняющий вопрос
/// → «приятно-принято» → следующий шаг → финальная подсказка.
class PracticeWizardScreen extends StatefulWidget {
  final PracticeDef practice;
  final PracticeStyle style;
  const PracticeWizardScreen(
      {super.key, required this.practice, required this.style});

  @override
  State<PracticeWizardScreen> createState() => _PracticeWizardScreenState();
}

class _PracticeWizardScreenState extends State<PracticeWizardScreen> {
  final _answerC = TextEditingController();
  final _whyC = TextEditingController();

  /// Этап шага: false — основной ответ, true — уточняющий «почему?».
  bool _whyStage = false;
  int _index = 0;
  bool _finished = false;

  /// Собранные ответы: строки будущей записи дневника.
  final List<String> _lines = [];

  PracticeStep get _step => widget.practice.steps[_index];

  @override
  void dispose() {
    _answerC.dispose();
    _whyC.dispose();
    super.dispose();
  }

  void _acceptMain() {
    final answer = _answerC.text.trim();
    _lines.add('— ${_step.prompt}\n${answer.isEmpty ? '(пропущено)' : answer}');
    SystemSound.play(SystemSoundType.click);
    if (_step.why != null) {
      setState(() => _whyStage = true);
    } else {
      _nextStep();
    }
  }

  void _acceptWhy({required bool keep}) {
    final why = _whyC.text.trim();
    if (keep && why.isNotEmpty) _lines.add('Почему: $why');
    SystemSound.play(SystemSoundType.click);
    _nextStep();
  }

  void _nextStep() {
    if (_index + 1 < widget.practice.steps.length) {
      setState(() {
        _index++;
        _whyStage = false;
        _answerC.clear();
        _whyC.clear();
      });
    } else {
      setState(() => _finished = true);
    }
  }

  Future<void> _save(AppStore store) async {
    final p = widget.practice;
    final text = StringBuffer()
      ..writeln(
          'Практика №${p.number} «${p.title}» — стиль ${widget.style.letter} «${widget.style.name}»')
      ..writeln();
    for (final l in _lines) {
      text.writeln(l);
      text.writeln();
    }
    text.write('Подсказка: ${p.tip}');
    await store.addDiaryEntry(DiaryEntry(
      kind: 'practice',
      title: 'Практика «${p.title}»',
      text: text.toString().trim(),
      practiceId: p.id,
      style: widget.style.id,
    ));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Практика сохранена в дневник')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final p = widget.practice;
    final total = p.steps.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('№${p.number} ${p.title}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text('${widget.style.letter} «${widget.style.name}»',
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 12)),
            ),
          ),
        ],
      ),
      body: _finished
          ? _buildFinish(store)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // Прогресс мастера.
                LinearProgressIndicator(value: (_index + 1) / total),
                const SizedBox(height: 6),
                Text('Шаг ${_index + 1} из $total',
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 12)),
                const SizedBox(height: 18),
                if (!_whyStage) ...[
                  Text(_step.prompt,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _answerC,
                    maxLines: 3,
                    autofocus: true,
                    decoration:
                        const InputDecoration(hintText: 'Твой ответ…'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          _answerC.clear();
                          _acceptMain();
                        },
                        child: const Text('Пропустить'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _acceptMain,
                        child: Text(_step.why != null
                            ? 'Дальше'
                            : 'приятно-принято'),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(_step.why!,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _whyC,
                    maxLines: 3,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'Можно коротко, можно подробно…'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _acceptWhy(keep: false),
                        child: const Text('Пропустить'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => _acceptWhy(keep: true),
                        child: const Text('приятно-принято'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  /// Финал практики: подсказка + стилевое завершение (сад / ритуал /
  /// созвездие / карта) + сохранение записи в дневник.
  Widget _buildFinish(AppStore store) {
    final p = widget.practice;
    final done = store.diaryEntries
            .where((e) => e.kind == 'practice' && e.practiceId == p.id)
            .length +
        1; // включая текущую
    Widget styleBlock;
    switch (widget.style.id) {
      case 'garden':
        final stage = done >= 21
            ? ('дерево', Icons.park)
            : done >= 7
                ? ('цветок', Icons.local_florist)
                : ('росток', Icons.grass);
        styleBlock = _finishCard(
          icon: stage.$2,
          title: 'В твоём саду — ${stage.$1}',
          text: done >= 21
              ? 'Практика пройдена $done раз — выросло дерево. '
                  'Пропуск — не гибель: растение подвядает и ждёт воды.'
              : done >= 7
                  ? 'Практика пройдена $done раз — росток расцвёл. '
                      'До дерева — ${21 - done}.'
                  : 'Практика пройдена $done раз. До цветка — '
                      '${7 - done}, до дерева — ${21 - done}.',
        );
        break;
      case 'stars':
        final inConstellation = ((done - 1) % 7) + 1;
        final constellations = (done - 1) ~/ 7;
        styleBlock = _finishCard(
          icon: Icons.auto_awesome,
          title: done % 7 == 0
              ? 'Созвездие собрано!'
              : 'Звезда $inConstellation из 7',
          text: '${'★ ' * inConstellation}${'☆ ' * (7 - inConstellation)}'
              '\nВсего звёзд: $done'
              '${constellations > 0 ? ', созвездий: $constellations' : ''}.',
        );
        break;
      case 'ritual':
        styleBlock = _finishCard(
          icon: Icons.self_improvement,
          title: 'Ритуал завершён',
          text: 'Сделай три спокойных вдоха-выдоха. Вечер твой.',
        );
        break;
      default: // card
        styleBlock = _finishCard(
          icon: Icons.style,
          title: 'Карта дня принята',
          text: 'Карта «${p.title}» легла в дневник. '
              'Завтра ждёт новая.',
        );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      children: [
        const Icon(Icons.check_circle_outline,
            size: 44, color: AppTheme.done),
        const SizedBox(height: 12),
        Text(p.tip,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 18),
        styleBlock,
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => _save(store),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Сохранить в дневник'),
        ),
      ],
    );
  }

  Widget _finishCard(
      {required IconData icon, required String title, required String text}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: AppTheme.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(text,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
