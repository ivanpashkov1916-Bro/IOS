/// Офлайн-распознавание русской речи на sherpa-onnx (next-gen Kaldi).
///
/// Системный Google-распознаватель НЕ используется вообще — поэтому
/// ошибки error_network / error_speech_timeout исчезают как класс.
/// Модель zipformer-ru (int8) скачивается в приложении ОДИН раз
/// (как GGUF-модель LLM) и лежит в документах приложения.
///
/// Ручной режим: запись останавливается ТОЛЬКО кнопкой микрофона.
/// По ходу речи текст обновляется (черновой прогон каждые ~2 с),
/// после остановки — финальный точный прогон всей записи.
/// Аудио нигде не сохраняется: PCM-сэмплы живут только в памяти
/// на время записи.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'diag_log.dart';

class VoiceInputService {
  // Модель: sherpa-onnx-zipformer-ru-int8-2025-04-20 (русская, int8).
  // Берём только нужные файлы: ~70 МБ вместо ~320 МБ полного набора.
  // ВАЖНО: репозиторий и имена файлов сверены с HuggingFace напрямую
  // (старая ссылка 2024-09-18 вела на несуществующий репозиторий —
  // все зеркала отвечали 404, поэтому скачивание падало).
  static const _repo = 'csukuangfj/sherpa-onnx-zipformer-ru-int8-2025-04-20';
  // Зеркала по порядку: hf-mirror.com — доступен из РФ (huggingface.co
  // на части сетей недоступен), huggingface.co — запасной.
  static const _hosts = ['https://hf-mirror.com', 'https://huggingface.co'];
  static const _files = <String, int>{
    'encoder.int8.onnx': 70000000, // 70 876 638 байт (~67.6 МБ)
    'decoder.onnx': 2000000, // 2 093 080 байт (~2 МБ)
    'joiner.int8.onnx': 250000, // 259 417 байт (~253 КБ)
    'tokens.txt': 6000, // 6 388 байт
  };

  final AudioRecorder _recorder = AudioRecorder();
  sherpa_onnx.OfflineRecognizer? _recognizer;
  static bool _bindingsReady = false;

  StreamSubscription<Uint8List>? _sub;
  List<double> _samples = [];
  Timer? _partialTimer;
  bool _listening = false;
  bool _recognizingFinal = false;
  // Черновой прогон идёт в отдельном потоке C++, но всё равно ест CPU:
  // не даём ему накладываться сам на себя (при загруженном процессоре —
  // например, параллельно работает Ollama — это давало видимые
  // тормоза и вылеты по нехватке памяти).
  bool _decodingPartial = false;

  /// Окно чернового распознавания: декодируем только ПОСЛЕДНИЕ 8 с
  /// речи, а не всю запись целиком каждые несколько секунд (старый
  /// вариант на длинных фразах грузил CPU квадратично). Финальный
  /// прогон после остановки по-прежнему обрабатывает запись целиком.
  static const _partialWindowSec = 8;

  void Function(String text, bool isFinal)? _onResult;

  bool get isListening => _listening;

  /// Идёт финальное распознавание после остановки записи.
  bool get recognizingFinal => _recognizingFinal;

  Future<Directory> _modelDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/voice_model');
  }

  /// Все файлы модели на месте и правдоподобного размера.
  Future<bool> isModelReady() async {
    try {
      final dir = await _modelDir();
      for (final e in _files.entries) {
        final f = File('${dir.path}/${e.key}');
        if (!f.existsSync()) return false;
        if (await f.length() < e.value) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Размер закачки для UI (~70 МБ).
  int get approxDownloadBytes => 74000000;

  /// Скачивание модели (один раз). onProgress: 0..1, onStatus: подпись.
  /// Каждый файл пробуем с каждого зеркала (два круга); в ошибке
  /// перечисляем, что ответило каждое зеркало — для диагностики.
  Future<void> downloadModel({
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    final dir = await _modelDir();
    await dir.create(recursive: true);
    DiagLog.add('voice', 'скачивание модели: старт (репозиторий $_repo)');
    final names = _files.keys.toList();
    var fileIndex = 0;
    for (final name in names) {
      onStatus?.call('Файл ${fileIndex + 1} из ${names.length}: $name');
      final target = File('${dir.path}/$name');
      if (target.existsSync() && await target.length() >= _files[name]!) {
        fileIndex++;
        onProgress?.call(fileIndex / names.length);
        continue;
      }
      final part = File('${target.path}.part');
      final errors = <String>[];
      var ok = false;
      for (var round = 0; round < 2 && !ok; round++) {
        for (final host in _hosts) {
          IOSink? sink;
          http.Client? client;
          try {
            final url = '$host/$_repo/resolve/main/$name';
            onStatus?.call(
                'Файл ${fileIndex + 1} из ${names.length}: $name · '
                '${Uri.parse(host).host}');
            client = http.Client();
            final req = http.Request('GET', Uri.parse(url));
            req.headers['User-Agent'] = 'planner-app/1.0';
            final resp = await client
                .send(req)
                .timeout(const Duration(seconds: 45));
            if (resp.statusCode != 200) {
              errors.add('${Uri.parse(host).host}: HTTP ${resp.statusCode}');
              client.close();
              client = null;
              continue;
            }
            final total = resp.contentLength ?? 0;
            var received = 0;
            sink = part.openWrite();
            await for (final chunk in resp.stream) {
              sink.add(chunk);
              received += chunk.length;
              final fileFrac = total > 0 ? received / total : 0.5;
              onProgress?.call((fileIndex + fileFrac) / names.length);
            }
            await sink.close();
            sink = null;
            client.close();
            client = null;
            if (await part.length() >= _files[name]!) {
              await part.rename(target.path);
              ok = true;
              break;
            }
            errors.add('${Uri.parse(host).host}: файл слишком мал '
                '(${await part.length()} байт)');
          } catch (e) {
            errors.add('${Uri.parse(host).host}: $e');
          } finally {
            await sink?.close();
            client?.close();
          }
        }
      }
      if (!ok) {
        DiagLog.add('voice', 'скачивание: сбой на $name — ${errors.join('; ')}');
        throw Exception('Не удалось скачать $name. ${errors.join('; ')}');
      }
      fileIndex++;
      onProgress?.call(fileIndex / names.length);
    }
    // Чистим файл старой модели, если он остался от прошлых попыток.
    try {
      final legacy = File('${dir.path}/decoder.int8.onnx');
      if (legacy.existsSync()) await legacy.delete();
    } catch (_) {}
    DiagLog.add('voice', 'скачивание модели: готово');
    onStatus?.call('Модель готова');
  }

  Future<void> deleteModel() async {
    try {
      _freeRecognizer();
      final dir = await _modelDir();
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  void _freeRecognizer() {
    _recognizer?.free();
    _recognizer = null;
  }

  /// Ленивая инициализация распознавателя (модель ~67 МБ в памяти).
  Future<sherpa_onnx.OfflineRecognizer> _ensureRecognizer() async {
    final r = _recognizer;
    if (r != null) return r;
    if (!_bindingsReady) {
      sherpa_onnx.initBindings();
      _bindingsReady = true;
    }
    final dir = await _modelDir();
    final p = dir.path;
    final config = sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        transducer: sherpa_onnx.OfflineTransducerModelConfig(
          encoder: '$p/encoder.int8.onnx',
          decoder: '$p/decoder.onnx',
          joiner: '$p/joiner.int8.onnx',
        ),
        tokens: '$p/tokens.txt',
        numThreads: 2,
        debug: false,
      ),
    );
    final created = sherpa_onnx.OfflineRecognizer(config);
    _recognizer = created;
    return created;
  }

  /// Старт записи. Остановка — только stop() (кнопка микрофона).
  /// onResult получает черновой текст по ходу речи и финальный
  /// после stop(). onError — только реальные отказы.
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(String error)? onError,
    void Function()? onDone,
  }) async {
    _onResult = onResult;
    if (!await isModelReady()) {
      onError?.call('Голосовая модель не скачана');
      onDone?.call();
      return false;
    }
    try {
      if (!await _recorder.hasPermission()) {
        onError?.call('Нет разрешения на микрофон');
        onDone?.call();
        return false;
      }
      await _ensureRecognizer();
      _samples = [];
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _sub = stream.listen((data) {
        // PCM16 little-endian -> float [-1, 1].
        final n = data.length ~/ 2;
        for (var i = 0; i < n; i++) {
          final v = (data[i * 2] | (data[i * 2 + 1] << 8));
          final s = v >= 0x8000 ? v - 0x10000 : v;
          _samples.add(s / 32768.0);
        }
      });
      // Черновой прогон каждые 3 с по короткому окну: текст появляется
      // по ходу речи, CPU почти не тратится даже на длинных фразах.
      _partialTimer?.cancel();
      _partialTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _decodePartial());
      _listening = true;
      DiagLog.add('voice', 'запись началась (офлайн-модель)');
      return true;
    } catch (e) {
      DiagLog.add('voice', 'ошибка старта записи: $e');
      onError?.call('Микрофон: $e');
      onDone?.call();
      return false;
    }
  }

  void _decodePartial() {
    if (!_listening ||
        _recognizingFinal ||
        _decodingPartial ||
        _samples.length < 16000) {
      return;
    }
    _decodingPartial = true;
    try {
      // Только хвост записи — иначе каждый черновой прогон декодирует
      // ВСЮ накопленную фразу и чем длиннее запись, тем тяжелее.
      const win = 16000 * _partialWindowSec;
      final slice = _samples.length <= win
          ? _samples
          : _samples.sublist(_samples.length - win);
      _decodeSlice(slice, _onResult, isFinal: false);
    } finally {
      _decodingPartial = false;
    }
  }

  void _decodeSlice(List<double> samples, void Function(String, bool)? cb,
      {required bool isFinal}) {
    final r = _recognizer;
    if (r == null || samples.isEmpty) return;
    sherpa_onnx.OfflineStream? stream;
    try {
      stream = r.createStream();
      final buf = Float32List.fromList(samples);
      stream.acceptWaveform(samples: buf, sampleRate: 16000);
      r.decode(stream);
      final text = r.getResult(stream).text.trim();
      if (text.isNotEmpty) cb?.call(text, isFinal);
    } catch (e) {
      // Черновой прогон не критичен; финальный ошибок не прячем.
      if (isFinal) {
        DiagLog.add('voice', 'ошибка финального распознавания: $e');
        rethrow;
      }
    } finally {
      stream?.free();
    }
  }

  /// Остановка записи кнопкой и ФИНАЛЬНОЕ распознавание всей фразы.
  /// Возвращает распознанный текст ('' — если ничего не услышано).
  Future<String> stop() async {
    _listening = false;
    _partialTimer?.cancel();
    _partialTimer = null;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    if (_samples.length < 8000) return ''; // меньше 0.5 с — не шумим
    _recognizingFinal = true;
    final secs = _samples.length / 16000;
    final sw = Stopwatch()..start();
    String text = '';
    sherpa_onnx.OfflineStream? stream;
    try {
      final r = await _ensureRecognizer();
      stream = r.createStream();
      final buf = Float32List.fromList(_samples);
      stream.acceptWaveform(samples: buf, sampleRate: 16000);
      r.decode(stream);
      text = r.getResult(stream).text.trim();
    } finally {
      stream?.free();
      _samples = [];
      _recognizingFinal = false;
      // Диагностика скорости: если распознавание идёт дольше самой
      // записи — телефону не хватает CPU (параллельный Ollama и т.п.).
      DiagLog.add('voice',
          'финальный прогон: ${secs.toStringAsFixed(1)} с речи за '
          '${sw.elapsedMilliseconds} мс');
    }
    if (text.isNotEmpty) _onResult?.call(text, true);
    return text;
  }

  Future<void> cancel() async {
    _listening = false;
    _partialTimer?.cancel();
    _partialTimer = null;
    try {
      await _sub?.cancel();
      await _recorder.stop();
    } catch (_) {}
    _sub = null;
    _samples = [];
  }
}
