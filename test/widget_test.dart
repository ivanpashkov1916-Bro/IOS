import 'package:flutter_test/flutter_test.dart';

// Smoke-тест: раньше здесь лежал шаблонный тест из flutter create
// с конструктором MyApp — его в приложении нет, тест падал и ломал
// шаг «flutter test». Полноценный виджет-тест AppStore требует
// sqflite (доступен только на устройстве), поэтому здесь — простая
// проверка, что тестовый раннер работает. Логика покрыта тестами
// import_tasks_test.dart, ollama_extract_test.dart и stats_test.dart.
void main() {
  test('smoke: тестовый раннер жив', () {
    expect(40 + 2, 42);
  });
}
