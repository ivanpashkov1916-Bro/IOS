/// Стандартное (системное) распознавание речи — резервный канал
/// голосового ввода. Используется, когда офлайн-модель sherpa-onnx
/// не скачана и пользователь нажал «Позже» в диалоге скачивания:
/// микрофон продолжает работать через распознаватель системы
/// (пакет speech_to_text, локаль ru_RU).
///
/// Ручной режим сохраняется: первое нажатие начинает запись,
/// второе — завершает и отправляет фразу. Аудио не сохраняется.
library;

import 'package:speech_to_text/speech_to_text.dart';

import 'diag_log.dart';

class SystemVoiceInput {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  bool _listening = false;
  String _lastText = '';

  bool get isListening => _listening;

  /// Есть ли на устройстве системное распознавание речи вообще
  /// (на части телефонов без Google-сервисов его нет — тогда
  /// единственный рабочий канал голоса: офлайн-модель sherpa-onnx).
  Future<bool> isAvailable() async => _ensureInit();

  Future<bool> _ensureInit({void Function(String error)? onError}) async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onError: (e) => onError?.call(e.errorMsg),
      );
    } catch (e) {
      _ready = false;
      onError?.call('$e');
    }
    return _ready;
  }

  /// Старт записи. onResult получает текст по ходу речи (partial) и
  /// финальный вариант. onError — только реальные отказы.
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(String error)? onError,
    void Function()? onDone,
  }) async {
    if (!await _ensureInit(onError: onError)) {
      DiagLog.add('voice', 'системное распознавание недоступно');
      onError?.call('Системное распознавание недоступно на этом устройстве');
      onDone?.call();
      return false;
    }
    _lastText = '';
    try {
      await _stt.listen(
        onResult: (r) {
          _lastText = r.recognizedWords;
          if (_lastText.isNotEmpty) onResult(_lastText, r.finalResult);
        },
        listenOptions: SpeechListenOptions(
          localeId: 'ru_RU',
          partialResults: true,
          cancelOnError: false,
          onDevice: false,
          listenMode: ListenMode.dictation,
        ),
      );
      _listening = true;
      DiagLog.add('voice', 'запись началась (системное распознавание)');
      return true;
    } catch (e) {
      _listening = false;
      DiagLog.add('voice', 'системное распознавание: ошибка старта: $e');
      onError?.call('$e');
      onDone?.call();
      return false;
    }
  }

  /// Остановка кнопкой: возвращает последний распознанный текст.
  Future<String> stop() async {
    _listening = false;
    try {
      await _stt.stop();
    } catch (_) {}
    return _lastText;
  }

  Future<void> cancel() async {
    _listening = false;
    try {
      await _stt.cancel();
    } catch (_) {}
    _lastText = '';
  }
}
