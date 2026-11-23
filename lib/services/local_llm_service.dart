/// Встроенная (on-device) LLM через fllama (llama.cpp). Работает офлайн.
/// Поддерживается СПИСОК моделей: скачанная Qwen2.5-0.5B + любые .gguf,
/// уже лежащие на телефоне (импортируются через выбор файла и видны
/// в списке — скачивать заново не нужно). Тот же JSON-протокол, что у Ollama.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fllama/fllama.dart';
import 'package:fllama/fllama_type.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ollama_service.dart';

/// Модель на устройстве (файл .gguf).
class ModelInfo {
  final String name; // имя файла
  final String path; // абсолютный путь
  final int sizeMb;
  final bool external; // найдена вне папки приложения (Загрузки и т.п.)
  const ModelInfo({
    required this.name,
    required this.path,
    required this.sizeMb,
    this.external = false,
  });
}

class LocalLlmService {
  static const String modelFileName = 'qwen2.5-0.5b-instruct-q4_k_m.gguf';
  static const String modelUrl =
      'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/$modelFileName';
  // Зеркало на случай недоступности huggingface.co
  static const String modelUrlMirror =
      'https://hf-mirror.com/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/$modelFileName';
  static const int _minValidBytes = 300 * 1024 * 1024; // ~300 МБ

  double? _contextId;
  String? _loadedPath;
  bool get isLoaded => _contextId != null;

  // ---------- Каталог моделей ----------
  Future<Directory> _modelsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir;
  }

  /// Доступ ко «всем файлам» (Android 11+). Без него .gguf в Download
  /// и других общих папках НЕ видны через обычный файловый API —
  /// модель «лежит в папке, но приложение её не видит».
  /// Разрешение запрашивается только по явному действию пользователя
  /// (кнопки «Добавить .gguf» / «Указать папку»), не при старте.
  Future<bool> ensureStorageAccess() async {
    try {
      if (await Permission.manageExternalStorage.isGranted) return true;
      final st = await Permission.manageExternalStorage.request();
      if (st.isGranted) return true;
      // Старые Android (<=10): достаточно обычного storage.
      if (await Permission.storage.isGranted) return true;
      final st2 = await Permission.storage.request();
      return st2.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Папка, которую пользователь указал кнопкой «Указать папку» —
  /// запоминаем и сканируем при КАЖДОМ обновлении списка моделей,
  /// чтобы после перезапуска модель не «пропадала».
  Future<String?> _savedFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('llmModelFolder');
    } catch (_) {
      return null;
    }
  }

  /// Все .gguf в папке приложения + найденные на телефоне
  /// (Загрузки, Документы и подпапки — поиск рекурсивный, глубина до 3):
  /// «уже установленные» модели можно просто выбрать.
  Future<List<ModelInfo>> availableModels() async {
    final result = <ModelInfo>[];
    final seen = <String>{};

    Future<void> scan(Directory dir, bool external, int depth) async {
      try {
        if (depth < 0 || !dir.existsSync()) return;
        await for (final e in dir.list(recursive: false)) {
          if (e is Directory) {
            final name = e.path.split('/').last;
            // Системные и скрытые папки пропускаем (нет доступа / мусор).
            if (name.startsWith('.') || name == 'Android') continue;
            await scan(e, external, depth - 1);
            continue;
          }
          if (e is! File) continue;
          final name = e.path.split('/').last;
          if (!name.toLowerCase().endsWith('.gguf')) continue;
          if (seen.contains(e.path)) continue;
          int size = 0;
          try {
            size = await e.length();
          } catch (_) {}
          if (size < 10 * 1024 * 1024) continue; // битые/пустые не показываем
          seen.add(e.path);
          result.add(ModelInfo(
            name: name,
            path: e.path,
            sizeMb: size ~/ (1024 * 1024),
            external: external,
          ));
        }
      } catch (_) {
        // нет доступа к папке — пропускаем
      }
    }

    await scan(await _modelsDir(), false, 1);
    // Папка, которую пользователь указал ранее («Указать папку») —
    // сканируется всегда, модель не нужно прикреплять заново.
    final savedFolder = await _savedFolder();
    if (savedFolder != null && savedFolder.isNotEmpty) {
      await scan(Directory(savedFolder), true, 4);
    }
    // Типовые папки Android, куда обычно скачивают модели
    // (в т.ч. подпапки, куда качает Termux/браузер).
    await scan(Directory('/storage/emulated/0/Download'), true, 3);
    await scan(Directory('/storage/emulated/0/Downloads'), true, 3);
    await scan(Directory('/storage/emulated/0/Documents'), true, 3);
    await scan(Directory('/storage/emulated/0'), true, 1);
    return result;
  }

  /// Импорт модели из произвольной папки телефона: пользователь
  /// указывает папку, все .gguf в ней (и подпапках) попадают в список.
  /// Папка запоминается — после перезапуска модели видны сразу.
  Future<List<ModelInfo>> importModelsFromFolder() async {
    // Без полного доступа к файлам Android 11+ не покажет .gguf
    // в общих папках — просим разрешение заранее.
    await ensureStorageAccess();
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('llmModelFolder', dirPath);
    } catch (_) {}
    final dir = Directory(dirPath);
    final found = <ModelInfo>[];
    Future<void> scan(Directory d, int depth) async {
      try {
        if (depth < 0 || !d.existsSync()) return;
        await for (final e in d.list(recursive: false)) {
          if (e is Directory) {
            if (!e.path.split('/').last.startsWith('.')) {
              await scan(e, depth - 1);
            }
            continue;
          }
          if (e is! File) continue;
          final name = e.path.split('/').last;
          if (!name.toLowerCase().endsWith('.gguf')) continue;
          int size = 0;
          try {
            size = await e.length();
          } catch (_) {}
          if (size < 10 * 1024 * 1024) continue;
          found.add(ModelInfo(
            name: name,
            path: e.path,
            sizeMb: size ~/ (1024 * 1024),
            external: true,
          ));
        }
      } catch (_) {}
    }

    await scan(dir, 4);
    return found;
  }

  /// Путь активной модели: выбранная пользователем, иначе скачанная по умолчанию.
  /// Если сохранённый путь пропал (файл лежит в общей папке, а доступ
  /// изменился) — ищем модель по ИМЕНИ ФАЙЛА среди видимых .gguf.
  Future<String?> activeModelPath() async {
    String? savedName;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('llmModelPath');
      if (saved != null) {
        if (File(saved).existsSync()) return saved;
        savedName = saved.split('/').last;
      }
    } catch (_) {}
    try {
      final def = File('${(await _modelsDir()).path}/$modelFileName');
      if (def.existsSync() && await def.length() > _minValidBytes) {
        return def.path;
      }
    } catch (_) {}
    // Любая другая модель из папки приложения или с телефона;
    // в первую очередь — та же самая по имени файла.
    final models = await availableModels();
    if (savedName != null) {
      for (final m in models) {
        if (m.name == savedName) return m.path;
      }
    }
    for (final m in models) {
      if (!m.external) return m.path;
    }
    if (models.isNotEmpty) return models.first.path;
    return null;
  }

  /// Выбрать модель из списка для использования в приложении.
  /// Внешний файл копируется в папку приложения (стабильный путь,
  /// чтобы llama.cpp не падал на временных разрешениях Android).
  Future<ModelInfo> selectModel(ModelInfo m) async {
    var path = m.path;
    if (m.external) {
      final dir = await _modelsDir();
      final target = File('${dir.path}/${m.name}');
      if (!target.existsSync() || await target.length() != await File(m.path).length()) {
        await File(m.path).copy(target.path);
      }
      path = target.path;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('llmModelPath', path);
    await unload(); // новая модель — новый контекст
    return ModelInfo(name: m.name, path: path, sizeMb: m.sizeMb);
  }

  /// Добавить модель, уже установленную на телефоне, через выбор файла.
  /// FileType.custom + 'gguf' на части устройств падает с
  /// PlatformException «Unsupported filter» — поэтому выбираем любой
  /// файл (FileType.any) и проверяем расширение сами.
  Future<ModelInfo?> importModelFile() async {
    await ensureStorageAccess();
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return null;
    if (!path.toLowerCase().endsWith('.gguf')) {
      throw const FormatException(
          'Это не файл модели: выберите файл с расширением .gguf');
    }
    final f = File(path);
    final size = await f.length();
    final m = ModelInfo(
      name: path.split('/').last,
      path: path,
      sizeMb: size ~/ (1024 * 1024),
      external: true,
    );
    return selectModel(m);
  }

  Future<void> removeModel(ModelInfo m) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('llmModelPath');
      if (saved == m.path) {
        await prefs.remove('llmModelPath');
        await unload();
      }
      final dir = await _modelsDir();
      // Удаляем только файлы внутри папки приложения.
      if (m.path.startsWith(dir.path)) {
        final f = File(m.path);
        if (f.existsSync()) await f.delete();
      }
    } catch (_) {}
  }

  // ---------- Скачивание модели по умолчанию ----------
  Future<bool> isModelDownloaded() async => (await activeModelPath()) != null;

  Future<String> modelPath() async {
    final dir = await _modelsDir();
    return '${dir.path}/$modelFileName';
  }

  /// Размер активной модели в МБ (0 если нет).
  Future<int> modelSizeMb() async {
    try {
      final p = await activeModelPath();
      if (p == null) return 0;
      return (await File(p).length()) ~/ (1024 * 1024);
    } catch (_) {
      return 0;
    }
  }

  /// Скачивание модели с прогрессом (0..1). Сначала huggingface.co,
  /// при неудаче — зеркало. Качаем во временный .part и переименовываем,
  /// чтобы обрыв не оставлял битый файл.
  Future<void> downloadModel({void Function(double progress)? onProgress}) async {
    final path = await modelPath();
    final part = File('$path.part');
    Object? lastError;
    for (final url in [modelUrl, modelUrlMirror]) {
      IOSink? sink;
      try {
        final client = http.Client();
        final resp = await client
            .send(http.Request('GET', Uri.parse(url)))
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          lastError = 'HTTP ${resp.statusCode}';
          client.close();
          continue;
        }
        final total = resp.contentLength ?? 0;
        var received = 0;
        sink = part.openWrite();
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
        await sink.close();
        sink = null;
        client.close();
        if (await part.length() > _minValidBytes) {
          await part.rename(path);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('llmModelPath', path);
          await unload();
          onProgress?.call(1);
          return;
        }
        lastError = 'файл слишком мал (${await part.length()} байт)';
      } catch (e) {
        lastError = e;
      } finally {
        await sink?.close();
      }
    }
    throw Exception('Не удалось скачать модель: $lastError');
  }

  Future<void> deleteModel() async {
    await unload();
    try {
      final f = File(await modelPath());
      if (f.existsSync()) await f.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('llmModelPath');
    } catch (_) {}
  }

  // ---------- Работа с моделью ----------
  /// Загружает модель в память (один раз, дальше контекст переиспользуется).
  /// Параметры минимальные (nCtx 512, 2 потока): причина вылетов — нехватка
  /// оперативной памяти при генерации, поэтому жертвуем длиной контекста.
  Future<bool> ensureLoaded() async {
    final path = await activeModelPath();
    if (path == null) return false;
    if (_contextId != null && _loadedPath == path) return true;
    await unload();
    try {
      final res = await Fllama.instance()?.initContext(
            path,
            nCtx: 512,
            nBatch: 64,
            nThreads: 2,
            useMlock: false,
            useMmap: true,
          );
      final id = res?['contextId'];
      if (id == null) return false;
      _contextId = (id as num).toDouble();
      _loadedPath = path;
      return true;
    } catch (_) {
      _contextId = null;
      _loadedPath = null;
      return false;
    }
  }

  /// Тот же контракт, что у OllamaService.send: OllamaResult с json/rawText/error.
  Future<OllamaResult> send(String userText) =>
      _sendWith(userText, OllamaService.systemPromptFull);

  /// Свободный диалог (режим «Диалог») — без JSON-команд.
  Future<OllamaResult> sendChat(String userText) =>
      _sendWith(userText, OllamaService.chatPromptFull);

  /// Запрос с произвольным системным промптом (дневник наблюдений,
  /// практики): промпт действует только на этот запрос.
  Future<OllamaResult> sendWithPrompt(
          String userText, String systemPromptText) =>
      _sendWith(userText, systemPromptText);

  /// Отправка с самовосстановлением: если нативный слой упал
  /// (нехватка памяти и т.п.), контекст сбрасывается, модель
  /// загружается заново и запрос повторяется ОДИН раз автоматически —
  /// пользователю не нужно перезапускать приложение.
  Future<OllamaResult> _sendWith(String userText, String systemPromptText) async {
    var res = await _trySend(userText, systemPromptText);
    if (res.error != null) {
      await unload();
      res = await _trySend(userText, systemPromptText);
    }
    return res;
  }

  Future<OllamaResult> _trySend(String userText, String systemPromptText) async {
    if (!await ensureLoaded()) {
      return OllamaResult(error: 'Модель не загружена в память');
    }
    try {
      String? prompt;
      try {
        prompt = await Fllama.instance()?.getFormattedChat(
          _contextId!,
          messages: [
            RoleContent(role: 'system', content: systemPromptText),
            RoleContent(role: 'user', content: userText),
          ],
        );
      } catch (_) {
        prompt = null; // форматирование недоступно — соберём ChatML вручную
      }
      // Запасной вариант: ChatML-шаблон вручную (Qwen использует его).
      prompt ??= '<|im_start|>system\n$systemPromptText<|im_end|>\n'
          '<|im_start|>user\n$userText<|im_end|>\n<|im_start|>assistant\n';
      final res = await Fllama.instance()?.completion(
        _contextId!,
        prompt: prompt,
        temperature: 0.1,
        nPredict: 160,
        stop: const ['<|im_end|>', '<|endoftext|>'],
      );
      final text = (res?['text'] ?? '').toString().trim();
      if (text.isEmpty) return OllamaResult(error: 'Пустой ответ модели');
      return OllamaResult(json: OllamaService.extractJson(text), rawText: text);
    } catch (e) {
      // Контекст мог «убить» нативный слой — сбрасываем, чтобы следующая
      // попытка загрузила модель заново, а не падала повторно.
      await unload();
      return OllamaResult(error: e.toString());
    }
  }

  Future<void> unload() async {
    final id = _contextId;
    _contextId = null;
    _loadedPath = null;
    if (id != null) {
      try {
        await Fllama.instance()?.releaseContext(id);
      } catch (_) {}
    }
  }
}
