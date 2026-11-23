/// Экран «Ассистент»: чат с LLM. Три движка на выбор:
/// «На устройстве» — встроенная GGUF-модель через fllama (офлайн),
/// «Ollama» — локальный сервер 127.0.0.1:11434,
/// «API» — облачная модель по ключу (структурирует сумбурный
/// голосовой ввод и перед добавлением показывает список записей
/// на подтверждение: добавить / переделать / отменить).
/// Список установленных моделей: скачанная Qwen2.5-0.5B и любые .gguf,
/// уже лежащие на телефоне — можно добавить без скачивания и выбрать.
/// Ассистенту можно дать имя — он откликается на него.
/// Голосовой ввод (ru), fallback при любых сбоях — сохранение в заметку.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../profile.dart';
import 'lock_screen.dart';
import '../services/api_llm_service.dart';
import '../services/custom_commands.dart';
import '../services/diag_log.dart';
import '../services/local_commands.dart';
import '../services/local_llm_service.dart';
import '../services/ollama_service.dart';
import '../services/system_voice_input.dart';
import '../services/voice_input.dart';
import '../store.dart';
import '../theme.dart';
import 'commands_screen.dart';
import 'common.dart';
import 'daily_diag.dart';
import 'edit_dialogs.dart';

class _Msg {
  final String text;
  final bool isUser;
  const _Msg(this.text, this.isUser);
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _ollama = OllamaService();
  final _local = LocalLlmService();
  // Облачная LLM по API-ключу (ключ — только из настроек).
  final _api = ApiLlmService();
  // Офлайн-распознавание русской речи (sherpa-onnx, модель на устройстве).
  final _voice = VoiceInputService();
  // Резервный канал: стандартное (системное) распознавание, когда
  // офлайн-модель не скачана и пользователь нажал «Позже».
  final _sysVoice = SystemVoiceInput();
  // Какой канал микрофона активен сейчас: 'sherpa' или 'system'.
  String _micEngine = 'sherpa';
  // Пользователь нажал «Позже» в диалоге скачивания: микрофон
  // работает через системное распознавание, диалог не донимает.
  bool _voiceLater = false;
  // Есть ли на телефоне системное распознавание речи (на устройствах
  // без Google-сервисов его нет — тогда голос возможен только через
  // офлайн-модель, и мы сразу ведём пользователя к скачиванию).
  bool _sysAvailable = true;
  final List<_Msg> _messages = [];
  bool _busy = false;
  bool _listening = false;

  /// Голосовая модель скачана и готова (проверяется при открытии экрана).
  bool _voiceReady = false;

  /// Идёт финальное распознавание после отпускания кнопки микрофона.
  bool _recognizingVoice = false;

  /// Движок ассистента: 'local' — на устройстве, 'ollama' — Termux,
  /// 'api' — облачная модель по ключу. Старое имя оставлено геттером,
  /// чтобы не трогать рабочую логику локального движка.
  String _engine = 'local';
  bool get _useLocal => _engine == 'local';

  // Контроллеры карточки облачной модели.
  final _apiUrlC = TextEditingController(text: ApiLlmService.baseUrl);
  final _apiModelC = TextEditingController(text: ApiLlmService.model);
  final _apiKeyC = TextEditingController();
  String _apiStatus = '';
  bool _apiTesting = false;

  /// false = режим «Команды» (JSON-действия), true = «Диалог»
  /// (свободное общение с моделью, как с обычной LLM).
  bool _chatMode = false;
  bool _modelDownloaded = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  int _modelSizeMb = 0;
  List<ModelInfo> _models = [];
  String? _activeModelPath;

  /// Модели, установленные в Ollama (Termux) — показываются списком
  /// при выбранном движке Ollama. null = сервер не ответил.
  List<String>? _ollamaModels;

  /// Панель настроек (движок, режим, модели, напоминания) скрыта за
  /// значком шестерёнки рядом с колокольчиком: нажатие разворачивает,
  /// повторное — сворачивает обратно. Пока модель не выбрана,
  /// панель открыта сама.
  bool _settingsOpen = true;

  @override
  void initState() {
    super.initState();
    _restoreEngine();
    _checkModel();
    _refreshOllamaModels();
    _checkVoiceModel();
  }

  Future<void> _checkVoiceModel() async {
    final ready = await _voice.isModelReady();
    try {
      final prefs = await SharedPreferences.getInstance();
      _voiceLater = prefs.getBool('voiceLater') ?? false;
      if (ready && _voiceLater) {
        // Модель появилась — возвращаемся на офлайн-распознавание.
        _voiceLater = false;
        await prefs.setBool('voiceLater', false);
      }
    } catch (_) {}
    // Проверяем доступность системного распознавания только у тех, кто
    // уже нажимал «Позже» (разрешение на микрофон у них уже запрошено —
    // проверка не вызовет лишний системный диалог у остальных).
    var sysOk = true;
    if (!ready && _voiceLater) {
      sysOk = await _sysVoice.isAvailable();
    }
    if (mounted) {
      setState(() {
        _voiceReady = ready;
        _sysAvailable = sysOk;
      });
    }
  }

  Future<void> _restoreEngine() async {
    final prefs = await SharedPreferences.getInstance();
    final om = prefs.getString('ollamaModel');
    if (om != null && om.isNotEmpty) OllamaService.model = om;
    await ApiLlmService.load();
    if (mounted) {
      setState(() {
        // Миграция со старой схемы (bool assistantLocal) на строку движка.
        _engine = prefs.getString('assistantEngine') ??
            ((prefs.getBool('assistantLocal') ?? true) ? 'local' : 'ollama');
        _chatMode = prefs.getBool('assistantChatMode') ?? false;
        _apiUrlC.text = ApiLlmService.baseUrl;
        _apiModelC.text = ApiLlmService.model;
        _apiKeyC.text = ApiLlmService.apiKey;
      });
    }
  }

  /// Загрузить список моделей Ollama (из Termux) для карточки выбора.
  Future<void> _refreshOllamaModels() async {
    final list = await _ollama.listModels();
    if (mounted) {
      setState(() => _ollamaModels = list);
    }
  }

  Future<void> _selectOllamaModel(String name) async {
    OllamaService.model = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ollamaModel', name);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Модель Ollama: $name')),
      );
    }
  }

  Future<void> _saveEngine(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assistantEngine', v);
  }

  Future<void> _saveChatMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('assistantChatMode', v);
  }

  Future<void> _checkModel() async {
    final ok = await _local.isModelDownloaded();
    final size = await _local.modelSizeMb();
    final models = await _local.availableModels();
    final active = await _local.activeModelPath();
    if (mounted) {
      setState(() {
        _modelDownloaded = ok;
        _modelSizeMb = size;
        _models = models;
        _activeModelPath = active;
        // Модель готова — настройки можно свернуть за шестерёнку,
        // чтобы не занимали место чата. Если модели нет — панель
        // остаётся открытой.
        if (ok && _settingsOpen && _messages.isEmpty) _settingsOpen = false;
      });
      // Ассистент спрашивает своё имя при первом запуске экрана,
      // когда модель уже выбрана/скачана.
      if (ok && UserProfile.assistantName.isEmpty) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _askAssistantName());
      }
    }
  }

  /// «Как ты хочешь ко мне обращаться?» — имя, на которое ассистент
  /// будет откликаться. Запомненное имя показывается в поле; кнопка
  /// «Изменить» включает редактирование, подтверждение — «Запомнить».
  Future<void> _askAssistantName() async {
    if (!mounted) return;
    final existing = UserProfile.assistantName;
    final c = TextEditingController(text: existing);
    var editing = existing.isEmpty; // новое имя — сразу редактируем
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: existing.isNotEmpty,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing.isEmpty
              ? (UserProfile.name.isEmpty
                  ? 'Модель готова к работе!'
                  : '${UserProfile.name}, модель готова к работе!')
              : 'Имя ассистента'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing.isEmpty
                  ? 'Как ты хочешь ко мне обращаться? Дай мне имя — '
                      'я буду откликаться на него.'
                  : 'Я откликаюсь на это имя:'),
              const SizedBox(height: 14),
              TextField(
                controller: c,
                enabled: editing,
                autofocus: editing,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    hintText: 'Имя ассистента (например, Ася)'),
                onSubmitted: (v) {
                  if (editing) Navigator.pop(ctx, v.trim());
                },
              ),
            ],
          ),
          actions: [
            if (!editing)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Закрыть'),
              ),
            FilledButton(
              onPressed: () {
                if (editing) {
                  Navigator.pop(ctx, c.text.trim());
                } else {
                  setD(() => editing = true);
                }
              },
              child: Text(editing ? 'Запомнить' : 'Изменить'),
            ),
          ],
        ),
      ),
    );
    if (name != null && name.isNotEmpty && name != existing) {
      await UserProfile.saveAssistantName(name);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _apiUrlC.dispose();
    _apiModelC.dispose();
    _apiKeyC.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _downloadModel() async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });
    try {
      await _local.downloadModel(
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      await _checkModel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Модель скачана и готова к работе офлайн')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Добавить уже установленную на телефоне модель (.gguf) — без скачивания.
  Future<void> _importModel() async {
    try {
      final m = await _local.importModelFile();
      if (m != null) {
        await _checkModel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Модель «${m.name}» добавлена и выбрана')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _selectModel(ModelInfo m) async {
    await _local.selectModel(m);
    await _checkModel();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Выбрана модель «${m.name}»')),
      );
    }
  }

  Future<void> _send() async {
    var text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (_listening) {
      // Отправка набранного текста при включённом микрофоне —
      // запись гасим без распознавания (оба канала).
      await _voice.cancel();
      await _sysVoice.cancel();
      setState(() => _listening = false);
    }
    if (_engine == 'local' && !_modelDownloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Сначала выберите или скачайте модель (выше)')),
      );
      return;
    }
    if (_engine == 'api' && !ApiLlmService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Введите API-ключ в настройках ассистента (выше)')),
      );
      return;
    }
    // Ассистент откликается на своё имя В ЛЮБОМ МЕСТЕ фразы:
    // обращение по имени убирается из текста перед обработкой.
    final an = UserProfile.assistantName;
    if (an.isNotEmpty) {
      final nameRe = RegExp(
          '(^|\\s)${RegExp.escape(an)}(?=\\s|[,.!?;:]|\$)',
          caseSensitive: false);
      if (nameRe.hasMatch(text)) {
        text = text
            .replaceAll(nameRe, ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(RegExp(r'^[\s,!:.\-]+|[\s,!:.\-]+$'), '')
            .trim();
        if (text.isEmpty) {
          setState(() {
            _messages.add(_Msg(an, true));
            _messages.add(_Msg(
                UserProfile.name.isEmpty
                    ? 'Слушаю тебя!'
                    : 'Слушаю тебя, ${UserProfile.name}!',
                false));
          });
          _input.clear();
          _scrollDown();
          return;
        }
      }
    }
    final store = context.read<AppStore>();
    _input.clear();
    setState(() {
      _messages.add(_Msg(text, true));
      _busy = true;
    });
    _scrollDown();

    String reply;
    if (store.flowActive) {
      // Диалоговый сценарий создания цели (блок → задачи → шаги):
      // пока он активен, весь ввод уходит в него, минуя парсеры.
      reply = await store.handleFlowInput(text);
    } else if (_chatMode) {
      // Режим «Диалог»: свободное общение с моделью без JSON-команд.
      final res = switch (_engine) {
        'local' => await _local.sendChat(text),
        'api' => await _api.sendChat(text),
        _ => await _ollama.sendChat(text),
      };
      if (res.error != null) {
        reply = switch (_engine) {
          'local' =>
            'Модель не ответила (не хватило памяти?). Попробуй ещё раз.',
          'api' => 'Облачная модель не ответила: ${res.error}',
          _ => 'Ollama недоступна (127.0.0.1:11434). Проверь, что сервер запущен.',
        };
      } else {
        reply = res.rawText.isNotEmpty ? res.rawText : 'Модель промолчала.';
      }
    } else {
      // Режим «Команды»: СНАЧАЛА пользовательские команды (экран
      // «Мои команды») — иначе встроенный парсер перехватывал их раньше
      // и личные команды никогда не срабатывали.
      final custom = CustomCommands.match(text);
      if (custom != null) {
        reply = await store.handleAssistantJson(custom);
        if (reply.isEmpty) {
          reply = 'Команда распознана, но выполнить не удалось.';
        }
      } else {
        // Затем ЛОКАЛЬНЫЙ парсер (понимает русские даты словами —
        // «на восьмое 11-е 26-й год»), надёжнее слабой модели.
        final localJson = LocalCommands.parse(text);
        if (localJson != null) {
          reply = await store.handleAssistantJson(localJson);
          if (reply.isEmpty) {
            await store.addNote(Note(title: 'Ассистент', text: text));
            reply = 'Не распознал команду — сохранил как заметку.';
          }
        } else if (_engine == 'api') {
          // Облачный движок: модель структурирует сумбурный ввод в список
          // записей, список показывается на подтверждение — добавить /
          // переделать / отменить.
          reply = await _sendViaApi(text, store);
        } else {
          final res =
              _useLocal ? await _local.send(text) : await _ollama.send(text);
          if (res.error != null) {
            // Движок недоступен — не падаем, сохраняем команду как заметку.
            await store.addNote(Note(title: 'Ассистент', text: text));
            reply = _useLocal
                ? 'Встроенная модель не ответила. Сохранил команду как заметку.'
                : 'Ollama недоступна (127.0.0.1:11434). Сохранил команду как заметку.';
          } else if (res.json != null) {
            // Исходная фраза — контекст для стора (например, поиск блока
            // цели по названию, если модель не заполнила поле block).
            res.json!.putIfAbsent('text', () => text);
            reply = await store.handleAssistantJson(res.json!);
            if (reply.isEmpty) {
              // JSON есть, но действие не распознано -> заметка с сырым текстом.
              await store.addNote(Note(
                title: 'Ассистент',
                text: res.rawText.isNotEmpty ? res.rawText : text,
              ));
              reply = 'Не распознал команду — сохранил как заметку.';
            }
          } else {
            // Парсинг упал -> НЕ крашимся, создаём заметку с сырым текстом.
            await store.addNote(Note(
              title: 'Ассистент',
              text: res.rawText.isNotEmpty ? res.rawText : text,
            ));
            reply = 'Модель ответила не JSON — сохранил как заметку.';
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(reply, false));
      _busy = false;
    });
    _scrollDown();
    // Новая цель/задача/событие, добавленные голосом или текстом:
    // уточняющие вопросы — ресурсы и шаги.
    final created = store.justCreated;
    if (created != null && mounted) {
      await showPlanQuestions(context, store,
          kind: created.kind, id: created.id);
      store.clearJustCreated();
    }
  }

  /// Облачный парсинг сумбурного ввода: модель структурирует текст
  /// в список задач/событий/целей, список показывается пользователю —
  /// добавить / переделать / отменить. Ошибки показываются как есть.
  Future<String> _sendViaApi(String text, AppStore store) async {
    var res = await _api.parseItems(text);
    if (res.error != null) {
      await store.addNote(Note(title: 'Ассистент', text: text));
      return 'Облачная модель не ответила: ${res.error}\n'
          'Сохранил команду как заметку.';
    }
    var items = res.items;
    if (items.isEmpty) {
      await store.addNote(Note(title: 'Ассистент', text: text));
      return 'Не нашёл в тексте поручений — сохранил как заметку.';
    }
    var retry = 0;
    while (mounted) {
      final decision = await _confirmParsed(items);
      if (decision == null || decision == 'cancel') {
        return 'Парсинг отменён — ничего не добавлял.';
      }
      if (decision == 'redo') {
        retry++;
        if (retry >= 3) {
          return 'Три варианта парсинга не подошли — отменил, '
              'ничего не добавлял.';
        }
        res = await _api.parseItems(text,
            retryHint: 'пересмотри разбор внимательнее');
        if (res.error != null) {
          return 'Ошибка повторного парсинга: ${res.error}';
        }
        if (res.items.isEmpty) {
          return 'При повторном разборе поручений не нашлось — отменил.';
        }
        items = res.items;
        continue;
      }
      // decision == 'add': добавляем всё из подтверждённого списка.
      final added = <String>[];
      for (final it in items) {
        final r = await store.handleAssistantJson(it.toCommandJson());
        if (r.isNotEmpty) added.add(r);
        // Шаги — сразу на шкалу пути созданной задачи.
        if (it.type == 'task' && it.steps.isNotEmpty) {
          final cr = store.justCreated;
          if (cr != null && cr.kind == 'task') {
            for (final s in it.steps) {
              await store.addStep(cr.id, s);
            }
          }
        }
        // Диалоги «ресурсы+шаги» для пачки записей не открываем.
        if (it.type != 'goal') store.clearJustCreated();
      }
      if (added.isEmpty) return 'Ничего не добавилось.';
      return 'Добавил ${added.length} записей:\n• ${added.join('\n• ')}';
    }
    return 'Парсинг отменён.';
  }

  /// Диалог подтверждения распознанного списка. «Добавить» — сразу
  /// в планировщик; «Нет» — уточняющий вопрос: переделать парсинг
  /// (новое предложение) или отменить совсем.
  Future<String?> _confirmParsed(List<ParsedItem> items) async {
    IconData iconOf(String type) => switch (type) {
          'event' => Icons.event,
          'goal' => Icons.flag_outlined,
          _ => Icons.check_circle_outline,
        };
    String labelOf(String type) => switch (type) {
          'event' => 'событие',
          'goal' => 'цель',
          _ => 'задача',
        };
    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Проверь список'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('Перед добавлением проверь, что всё верно:',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
              const SizedBox(height: 8),
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(iconOf(it.type),
                          size: 18, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.title,
                                style: const TextStyle(fontSize: 13)),
                            Text(
                              [
                                labelOf(it.type),
                                if (it.date != null) it.date!,
                                if (it.time != null) it.time!,
                                if (it.block.isNotEmpty)
                                  'блок: ${it.block}',
                                if (it.steps.isNotEmpty)
                                  'шагов: ${it.steps.length}',
                              ].join(' · '),
                              style: const TextStyle(
                                  color: AppTheme.textDim, fontSize: 11),
                            ),
                          ],
                        ),
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
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Добавить (${items.length})'),
          ),
        ],
      ),
    );
    if (add == true) return 'add';
    if (add == null) return null; // жест назад — отмена без вопросов
    if (!mounted) return 'cancel';
    // Пользователь выбрал «нет»: переделать разбор или отменить?
    final redo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Что сделать?'),
        content: const Text(
            'Переделать парсинг и выдать новое предложение '
            'или отменить его совсем?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отменить парсинг'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Переделать'),
          ),
        ],
      ),
    );
    return redo == true ? 'redo' : 'cancel';
  }

  /// Микрофон работает в ручном режиме: первое нажатие начинает запись,
  /// ВТОРОЕ нажатие завершает её и СРАЗУ отправляет фразу в чат.
  /// Основной канал — офлайн (sherpa-onnx, русская модель на устройстве);
  /// если модель не скачана и в диалоге выбрано «Позже», работает
  /// стандартное (системное) распознавание — голосом можно пользоваться
  /// и без скачивания.
  Future<void> _toggleMic() async {
    if (_listening) {
      setState(() {
        _listening = false;
        _recognizingVoice = true;
      });
      String text = '';
      Object? decodeError;
      try {
        text = _micEngine == 'system'
            ? await _sysVoice.stop()
            : await _voice.stop();
      } catch (e) {
        decodeError = e;
      }
      if (!mounted) return;
      setState(() => _recognizingVoice = false);
      if (decodeError != null) {
        // Ошибку НЕ прячем: показываем как есть.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Распознавание не удалось: $decodeError')),
        );
        return;
      }
      if (text.isNotEmpty) {
        setState(() => _input.text = text);
        await _send();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Ничего не расслышал — нажмите микрофон и '
                'повторите фразу'),
          ),
        );
      }
      return;
    }
    // Модель не скачана: один раз предлагаем скачать; «Позже»
    // запоминается — дальше микрофон работает через системное
    // распознавание, диалог больше не всплывает.
    if (!_voiceReady && !_voiceLater && _sysAvailable) {
      await _offerVoiceDownload();
      if (!mounted) return;
      if (!_voiceReady && !_voiceLater) return; // диалог просто закрыли
    }
    // Системного распознавания на телефоне нет (нет Google-сервисов):
    // единственный рабочий канал — офлайн-модель. Ведём к скачиванию
    // сразу, без заведомо нерабочей попытки.
    if (!_voiceReady && !_sysAvailable) {
      final got = await _offerVoiceDownload(systemUnavailable: true);
      if (!mounted || !got) return;
      return _toggleMic(); // модель появилась — стартуем офлайн-запись
    }
    // Перед записью выгружаем встроенную LLM из памяти, если она
    // загружена: распознавателю нужны сотни МБ, а держать оба
    // одновременно (ещё и при работающем Ollama в Termux) — верный
    // вылет по нехватке памяти. Модель подгрузится сама при
    // следующем сообщении (send() делает это лениво).
    if (_local.isLoaded) {
      DiagLog.add('voice', 'выгрузил встроенную LLM перед записью');
      await _local.unload();
    }
    final useSystem = !_voiceReady;
    var errorShown = false;
    bool ok;
    if (useSystem) {
      _micEngine = 'system';
      ok = await _sysVoice.start(
        onResult: (t, isFinal) {
          if (!mounted) return;
          setState(() => _input.text = t);
        },
        onError: (error) {
          if (!mounted) return;
          errorShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Микрофон (системный): $error')),
          );
        },
        onDone: () {
          if (mounted) setState(() => _listening = false);
        },
      );
    } else {
      _micEngine = 'sherpa';
      ok = await _voice.start(
        onResult: (t, isFinal) {
          if (!mounted) return;
          setState(() => _input.text = t);
        },
        onError: (error) {
          if (!mounted) return;
          errorShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Микрофон: $error')),
          );
        },
        onDone: () {
          if (mounted) setState(() => _listening = false);
        },
      );
    }
    if (!mounted) return;
    setState(() => _listening = ok);
    if (!ok) {
      if (useSystem) {
        // Системное распознавание не завелось (на этом телефоне его
        // нет) — сбрасываем «Позже» и сразу предлагаем офлайн-модель:
        // это единственный рабочий путь голосового ввода здесь.
        _sysAvailable = false;
        _voiceLater = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('voiceLater', false);
        } catch (_) {}
        if (!mounted) return;
        setState(() {});
        final got = await _offerVoiceDownload(systemUnavailable: true);
        if (got && mounted) return _toggleMic();
        return;
      }
      if (!errorShown) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Микрофон не запустился. Проверьте разрешение '
                'на микрофон в настройках системы.'),
          ),
        );
      }
    }
  }

  /// Диалог скачивания голосовой модели (один раз, ~70 МБ).
  /// «Позже» — запоминаем выбор: микрофон продолжает работать через
  /// стандартное (системное) распознавание, диалог не всплывает снова.
  /// [systemUnavailable] — на телефоне НЕТ системного распознавания:
  /// текст диалога честно объясняет, что офлайн-модель — единственный
  /// рабочий канал голосового ввода на этом устройстве.
  /// true — модель готова (скачана или уже была).
  Future<bool> _offerVoiceDownload({bool systemUnavailable = false}) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Голосовой ввод'),
        content: Text(systemUnavailable
            ? 'На этом телефоне нет встроенного распознавания речи, '
                'поэтому голосовой ввод возможен только через '
                'офлайн-модель (~70 МБ, скачивается один раз, дальше '
                'работает без интернета).\n\nСкачать сейчас?'
            : 'Можно один раз скачать голосовую модель (~70 МБ) — '
                'распознавание будет работать на устройстве и без '
                'интернета.\n\nЕсли скачивание не удаётся — нажмите '
                '«Позже»: микрофон будет работать через стандартное '
                'системное распознавание, и это окно больше не '
                'появится.\n\nСкачать сейчас?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Позже')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Скачать')),
        ],
      ),
    );
    if (agreed != true) {
      // «Позже» (или закрытие диалога): запоминаем выбор — голос
      // работает через системное распознавание без скачивания.
      // Если системного распознавания нет, флаг не ставим: при
      // следующем нажатии снова предложим единственный рабочий путь.
      if (!systemUnavailable) {
        _voiceLater = true;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('voiceLater', true);
        } catch (_) {}
        if (mounted) setState(() {});
      }
      return false;
    }
    if (!mounted) return false;
    // Прогресс и запуск закачки живут ВНЕ builder: иначе каждый
    // перерисованный кадр запускал бы закачку заново. При ошибке
    // диалог НЕ закрывается: показываем точную причину (какое зеркало
    // и что ответило) и даём кнопку «Повторить».
    var progress = 0.0;
    var status = 'Подготовка…';
    String? error;
    var running = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) {
          if (!running && error == null) {
            running = true;
            () async {
              try {
                await _voice.downloadModel(
                  onProgress: (p) => setDlg(() => progress = p),
                  onStatus: (s) => setDlg(() => status = s),
                );
                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              } catch (e) {
                setDlg(() {
                  running = false;
                  error = '$e';
                  status = 'Ошибка скачивания';
                });
              }
            }();
          }
          return AlertDialog(
            title: const Text('Скачиваю голосовую модель'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10),
                Text('${(progress * 100).toStringAsFixed(0)}% · $status',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textDim)),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.danger)),
                ],
              ],
            ),
            actions: error == null
                ? null
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(dlgCtx),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => setDlg(() {
                        error = null;
                        progress = 0.0;
                        status = 'Повторная попытка…';
                      }),
                      child: const Text('Повторить'),
                    ),
                  ],
          );
        },
      ),
    );
    final ready = await _voice.isModelReady();
    if (ready) {
      // Модель скачалась — возвращаемся на офлайн-распознавание.
      _voiceLater = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('voiceLater', false);
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _voiceReady = ready);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ready
              ? 'Голосовая модель готова — нажмите микрофон и говорите'
              : _sysAvailable
                  ? 'Модель не скачалась. Проверьте интернет и попробуйте '
                      'ещё раз — а пока микрофон работает через системное '
                      'распознавание'
                  : 'Модель не скачалась. Проверьте интернет и нажмите '
                      'микрофон ещё раз — без неё голосовой ввод на этом '
                      'телефоне недоступен'),
        ),
      );
    }
    return ready;
  }

  /// Пользователь указывает папку, где лежит модель (например, куда
  /// её положил Termux) — все .gguf в ней появятся в списке.
  Future<void> _importFolder() async {
    try {
      final found = await _local.importModelsFromFolder();
      await _checkModel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(found.isEmpty
              ? 'В выбранной папке .gguf не найдены'
              : 'Найдено моделей: ${found.length}. Выберите в списке.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assistantTitle = UserProfile.assistantName.isEmpty
        ? 'Ассистент'
        : UserProfile.assistantName;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(assistantTitle),
            Text(
                UserProfile.assistantName.isEmpty
                    ? 'Qwen2.5 · полный доступ к спискам'
                    : 'откликается на имя · полный доступ к спискам',
                style: const TextStyle(fontSize: 12, color: AppTheme.textDim, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          if (UserProfile.assistantName.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.badge_outlined, size: 20),
              tooltip: 'Имя ассистента',
              onPressed: _askAssistantName,
            ),
          // Мегафон «Мои команды»: полный список команд ассистента,
          // создание своих и правка существующих.
          IconButton(
            icon: const Icon(Icons.campaign_outlined,
                size: 20, color: AppTheme.textDim),
            tooltip: 'Мои команды',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommandsScreen()),
            ),
          ),
          // Шестерёнка настроек: разворачивает/сворачивает панель
          // (движок, режим, модели, напоминания, будильник).
          IconButton(
            icon: Icon(
                _settingsOpen ? Icons.settings : Icons.settings_outlined,
                size: 20,
                color: _settingsOpen ? AppTheme.accent : AppTheme.textDim),
            tooltip: 'Настройки ассистента',
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
          ),
          const FontScaleButton(),
          const AlertBell(),
        ],
      ),
      body: Column(
        children: [
          if (_settingsOpen) ...[
            // ---- Переключатель движка ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'local',
                    icon: Icon(Icons.phone_android, size: 16),
                    label: Text('На устройстве'),
                  ),
                  ButtonSegment(
                    value: 'ollama',
                    icon: Icon(Icons.dns_outlined, size: 16),
                    label: Text('Ollama'),
                  ),
                  ButtonSegment(
                    value: 'api',
                    icon: Icon(Icons.cloud_outlined, size: 16),
                    label: Text('API'),
                  ),
                ],
                selected: {_engine},
                onSelectionChanged: (s) {
                  setState(() => _engine = s.first);
                  _saveEngine(_engine);
                  if (_engine == 'ollama') _refreshOllamaModels();
                },
              ),
            ),
            // ---- Режим: «Команды» (действия в планировщике) или
            // «Диалог» (свободное общение с моделью, как с обычной LLM) ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.bolt, size: 16),
                    label: Text('Команды'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.chat_bubble_outline, size: 16),
                    label: Text('Диалог'),
                  ),
                ],
                selected: {_chatMode},
                onSelectionChanged: (s) {
                  setState(() => _chatMode = s.first);
                  _saveChatMode(_chatMode);
                },
              ),
            ),
            // ---- Управление моделями (только для локального движка) ----
            if (_engine == 'local') _buildModelCard(),
            // ---- Список моделей Ollama (Termux) ----
            if (_engine == 'ollama') _buildOllamaCard(),
            // ---- Облачная модель по API-ключу ----
            if (_engine == 'api') _buildApiCard(),
            _buildNotifCard(),
            _buildSecurityCard(),
            _buildDiagCard(),
            _buildDailyDiagCard(),
          ],
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Примеры команд:\n«Добавь задачу распланировать день на завтра»\n«Добавь событие „выход на Wildberries" завтра»\n«Добавь цель „подтянуть английский" в блок учёба»\n«Позвонить маме в пятницу в 18:00»\n«Срочно добавь задачу оплатить счёт»\n«Свяжи задачу ремонт отопления с блоком финансы»\n«Что у меня сегодня?»\n\nНазвание удобно ставить в кавычки — оно попадёт в заголовок целиком. Микрофон: нажмите — говорите, нажмите ещё раз — фраза отправится. В режиме «Диалог» можно просто общаться с моделью.'
                        '${UserProfile.assistantName.isEmpty ? '' : '\n«${UserProfile.assistantName}, что просрочено?»'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.6),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      return Align(
                        alignment:
                            m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(ctx).size.width * 0.8,
                          ),
                          decoration: BoxDecoration(
                            color: m.isUser ? AppTheme.accentSoft : AppTheme.card,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            m.text,
                            style: TextStyle(
                              color: m.isUser ? AppTheme.bg : AppTheme.text,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_listening)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                  _micEngine == 'system'
                      ? 'Слушаю (системное распознавание)… нажмите '
                          'микрофон ещё раз — фраза отправится'
                      : 'Слушаю (офлайн, русская модель)… нажмите микрофон '
                          'ещё раз — фраза распознается и отправится',
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 11)),
            ),
          // Режим «Позже»: модель не скачана — работает системное
          // распознавание; офлайн-модель можно докачать в любой момент.
          // Если системного распознавания на телефоне нет — честно
          // пишем, что без офлайн-модели голос не заработает.
          if (!_voiceReady && (_voiceLater || !_sysAvailable) && !_listening)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        _sysAvailable
                            ? 'Голос: системное распознавание '
                                '(офлайн-модель не скачана)'
                            : 'Системного распознавания нет — для голоса '
                                'нужна офлайн-модель',
                        style: const TextStyle(
                            color: AppTheme.textDim, fontSize: 11)),
                  ),
                  InkWell(
                    onTap: () async {
                      await _offerVoiceDownload(
                          systemUnavailable: !_sysAvailable);
                    },
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text('Скачать офлайн-модель',
                          style: TextStyle(
                              color: AppTheme.accent, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
          if (_recognizingVoice)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text('Распознаю…',
                  style:
                      TextStyle(color: AppTheme.textDim, fontSize: 11)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(hintText: 'Введите сообщение...'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                _RoundBtn(
                  icon: _recognizingVoice
                      ? Icons.graphic_eq
                      : (_listening ? Icons.mic : Icons.mic_none),
                  color: _listening
                      ? AppTheme.warn
                      : (_recognizingVoice
                          ? AppTheme.accent
                          : AppTheme.card),
                  iconColor: (_listening || _recognizingVoice)
                      ? AppTheme.bg
                      : AppTheme.accent,
                  onTap: _toggleMic,
                ),
                const SizedBox(width: 8),
                _RoundBtn(
                  icon: Icons.send,
                  color: AppTheme.accent,
                  iconColor: AppTheme.bg,
                  onTap: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Настройки оповещений: push-напоминания и дублирование горящих
  /// дедлайнов системным будильником телефона.
  Widget _buildNotifCard() {
    final store = context.watch<AppStore>();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          SwitchListTile(
            dense: true,
            secondary: Icon(
              store.remindersEnabled
                  ? Icons.notifications_active
                  : Icons.notifications_off_outlined,
              size: 20,
              color: store.remindersEnabled ? AppTheme.accent : AppTheme.textDim,
            ),
            title:
                const Text('Напоминания о дедлайнах', style: TextStyle(fontSize: 13)),
            subtitle: const Text('push за 4× времени выполнения',
                style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
            value: store.remindersEnabled,
            activeColor: AppTheme.accent,
            onChanged: (v) => store.setRemindersEnabled(v),
          ),
          // Автоматический системный будильник убран по требованию:
          // будильник ставится и снимается ТОЛЬКО вручную из меню задачи
          // (за 240 минут до дедлайна), push-напоминания — выше.
        ],
      ),
    );
  }

  /// Диагностика: текущее состояние движков + журнал последних событий
  /// голосового ввода и скачивания. Текст копируется одной кнопкой —
  /// его можно прислать разработчику для разбора сбоя.
  /// Ничего никуда не отправляется само.
  Widget _buildDiagCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.monitor_heart_outlined,
            size: 20, color: AppTheme.textDim),
        title: const Text('Диагностика', style: TextStyle(fontSize: 13)),
        subtitle: const Text(
            'состояние движков и журнал голосового ввода — для разбора сбоев',
            style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
        trailing: const Icon(Icons.copy_all, size: 18, color: AppTheme.accent),
        onTap: _showDiagnostics,
      ),
    );
  }

  /// Диагностика ежедневных задач (разбор задвоений): полный снимок
  /// ежедневных задач + журнал создания экземпляров. Тот же отчёт
  /// доступен с экрана «Календарь» (иконка в шапке).
  Widget _buildDailyDiagCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.fact_check_outlined,
            size: 20, color: AppTheme.textDim),
        title: const Text('Ежедневные задачи: диагностика',
            style: TextStyle(fontSize: 13)),
        subtitle: const Text(
            'снимок ежедневных задач и дублей — для разбора задвоений',
            style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
        trailing: const Icon(Icons.copy_all, size: 18, color: AppTheme.accent),
        onTap: () =>
            showDailyDiagDialog(context, context.read<AppStore>()),
      ),
    );
  }

  /// Пароль при входе: включить/выключить/сменить + контрольные вопросы.
  Widget _buildSecurityCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.lock_outline,
            size: 20, color: AppTheme.textDim),
        title: const Text('Безопасность (пароль при входе)',
            style: TextStyle(fontSize: 13)),
        subtitle: const Text(
            'включение и отключение пароля; восстановление по контрольным вопросам',
            style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right,
            size: 18, color: AppTheme.accent),
        onTap: () => showSecuritySettings(context),
      ),
    );
  }

  Future<void> _showDiagnostics() async {
    final state = <String, String>{
      'Движок ассистента': _engine,
      'Режим': _chatMode ? 'Диалог' : 'Команды',
      'Встроенная LLM загружена в память': _local.isLoaded ? 'да' : 'нет',
      'Голосовая офлайн-модель': _voiceReady ? 'скачана' : 'нет',
      'Системное распознавание': _sysAvailable ? 'доступно' : 'НЕТ на устройстве',
      'Канал микрофона сейчас': _micEngine,
      'Свободно в журнале событий': '${DiagLog.lines.length}',
    };
    final report = DiagLog.report(state);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Диагностика'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(report,
                style: const TextStyle(fontSize: 11, color: AppTheme.text)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy_all, size: 16),
            label: const Text('Копировать'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text(
                        'Диагностика скопирована — пришлите её разработчику')));
              }
            },
          ),
        ],
      ),
    );
  }

  /// Карточка управления моделями: список установленных (.gguf),
  /// выбор активной, добавление с телефона без скачивания,
  /// скачивание Qwen2.5-0.5B по кнопке.
  Widget _buildModelCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Модели на устройстве',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (_modelDownloaded)
                  Text('активна: $_modelSizeMb МБ',
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            if (_models.isEmpty)
              const Text(
                'Установленных моделей нет. Скачайте Qwen2.5-0.5B (~400 МБ) '
                'или добавьте файл .gguf, уже лежащий на телефоне.',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12),
              )
            else
              for (final m in _models)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selectModel(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _activeModelPath == m.path ||
                                  (_activeModelPath != null &&
                                      _activeModelPath!
                                          .endsWith(m.name) &&
                                      !m.external)
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: _activeModelPath == m.path
                              ? AppTheme.accent
                              : AppTheme.textDim,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13)),
                              Text(
                                '${m.sizeMb} МБ'
                                '${m.external ? ' · на телефоне (добавить)' : ' · установлена'}',
                                style: const TextStyle(
                                    color: AppTheme.textDim, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 10),
            if (_downloading) ...[
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 6),
              Text('${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
            ] else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _importModel,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Добавить .gguf'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _importFolder,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Указать папку'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadModel,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Скачать Qwen2.5-0.5B'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Карточка моделей Ollama: что реально установлено в Termux
  /// (запрос /api/tags). Тап по модели делает её активной.
  Widget _buildOllamaCard() {
    final list = _ollamaModels;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Модели Ollama (Termux)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Обновить список',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refreshOllamaModels,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (list == null || list.isEmpty)
              const Text(
                'Модели не видны: Ollama не отвечает на 127.0.0.1:11434. '
                'Запустите сервер в Termux (ollama serve) и обновите список.',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12),
              )
            else
              for (final name in list)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selectOllamaModel(name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          OllamaService.model == name
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: OllamaService.model == name
                              ? AppTheme.accent
                              : AppTheme.textDim,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
  /// Карточка облачной модели: базовый URL, выбор модели, ввод ключа.
  /// Ключ хранится только на устройстве (в коде его нет и не будет).
  Widget _buildApiCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Облачная модель (API-ключ)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Модель структурирует сумбурный голосовой ввод в задачи, '
              'события и цели и перед добавлением показывает список на '
              'подтверждение. Ключ хранится только на этом устройстве.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiUrlC,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Базовый URL API',
                hintText: 'https://api.openai.com/v1',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiModelC,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Модель',
                hintText: 'gpt-4o-mini',
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in ApiLlmService.suggestedModels)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _apiModelC.text = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _apiModelC.text == m
                            ? AppTheme.accentSoft
                            : AppTheme.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: _apiModelC.text == m
                                ? AppTheme.accent
                                : AppTheme.textDim.withOpacity(0.3)),
                      ),
                      child: Text(m,
                          style: TextStyle(
                              fontSize: 11,
                              color: _apiModelC.text == m
                                  ? AppTheme.bg
                                  : AppTheme.text)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyC,
              obscureText: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'API-ключ',
                hintText: 'sk-...',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Сохранить'),
                  onPressed: () async {
                    await ApiLlmService.save(
                      url: _apiUrlC.text,
                      modelName: _apiModelC.text,
                      key: _apiKeyC.text,
                    );
                    if (mounted) {
                      setState(() => _apiStatus =
                          ApiLlmService.isConfigured
                              ? 'Сохранено. Модель: ${ApiLlmService.model}'
                              : 'Сохранено, но ключ пуст — введите его.');
                    }
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: _apiTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Проверить'),
                  onPressed: _apiTesting
                      ? null
                      : () async {
                          setState(() {
                            _apiTesting = true;
                            _apiStatus = 'Проверяю подключение…';
                          });
                          await ApiLlmService.save(
                            url: _apiUrlC.text,
                            modelName: _apiModelC.text,
                            key: _apiKeyC.text,
                          );
                          final res = await _api.sendChat(
                              'Ответь одним словом: ок');
                          if (mounted) {
                            setState(() {
                              _apiTesting = false;
                              _apiStatus = res.error != null
                                  ? 'Ошибка: ${res.error}'
                                  : 'Подключение работает: '
                                      '${res.rawText.trim()}';
                            });
                          }
                        },
                ),
              ],
            ),
            if (_apiStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_apiStatus,
                  style:
                      const TextStyle(color: AppTheme.textDim, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor),
      ),
    );
  }
}
