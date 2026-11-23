# Планер — планировщик с голосовым ассистентом (Flutter)

Offline-first MVP: заметки, события, задачи, цели, статистика, архив и чат-ассистент
на локальной LLM (Ollama). Данные хранятся в sqflite на устройстве.

## Возможности

- **7 вкладок** (как в макетах): Сегодня, Заметки, Календарь, Задачи, Цели, Статистика, Ассистент.
- **Архивация вместо удаления**: выполненные задачи и достигнутые цели уходят в архив
  автоматически; любую сущность можно отправить в архив кнопкой и вернуть обратно
  на экране «Архив». Удаления навсегда в приложении нет.
- **CRUD**: на каждом экране карандаш открывает модальное окно с заполненными полями.
- **Статистика**: прогресс за День / Неделю / Месяц / Квартал / Год по задачам и целям +
  круговая диаграмма продуктивности (fl_chart).
- **Стратегия на год**: загрузка `tasks.json` (file_picker) → сводка, таблица, диаграмма по месяцам.
- **Ассистент**: чат с Ollama (`qwen2.5:0.5b`, `http://127.0.0.1:11434/api/chat`,
  temperature 0.1). JSON вырезается из ответа регулярным выражением
  `RegExp(r'\{[\s\S]*\}')` с заменой одинарных кавычек; при сбое парсинга или сети
  приложение не падает, а сохраняет текст в заметку.
- **Голосовой ввод**: русская речь (speech_to_text, ru_RU). Аудио не сохраняется.
- **Напоминания**: flutter_local_notifications v17 — за 15 минут и в начало события,
  за 30 минут до дедлайна задачи.

## Запуск ассистента

```bash
ollama pull qwen2.5:0.5b
ollama serve   # слушает http://127.0.0.1:11434
```

Для эмулятора Android вместо `127.0.0.1` используйте `10.0.2.2`
(правится в `lib/services/ollama_service.dart`, поле `baseUrl`).

Без Ollama ассистент честно сообщает о недоступности и сохраняет команду в заметку.

## Сборка APK

```bash
flutter create --platforms android --project-name planner_app .
flutter pub get
flutter build apk --release
```

CI: `.github/workflows/build-apk.yml` сам генерирует `android/`, патчит
Kotlin 2.0.21 / AGP 8.7.2 / compileSdk 35 / NDK 28 / Core Library Desugaring
и собирает APK.

## Сборка iOS (IPA)

CI: `.github/workflows/build-ios.yml` (macOS-раннер GitHub) сам генерирует
`ios/`, прописывает разрешения (микрофон, распознавание речи, камера, галерея),
bundle id `com.pashkov.planner` и собирает IPA — ручных правок не нужно.

- **Без секретов**: артефакт `PASHKOV-PLANER-unsigned.ipa` — установка через
  AltStore / SideStore / Sideloadly с бесплатным Apple ID (бесплатная подпись
  живёт 7 дней; AltStore переподписывает сам по Wi-Fi).
- **С платным Apple Developer**: добавьте секреты репозитория `IOS_TEAM_ID`,
  `IOS_P12_BASE64`, `IOS_P12_PASSWORD`, `IOS_MOBILEPROVISION_BASE64`
  (development-сертификат и профиль с UDID вашего iPhone) → соберётся
  подписанный `PASHKOV-PLANER.ipa` для прямой установки. Если подпись падает,
  сборка сама откатывается на неподписанный вариант.

Локально (на Mac):

```bash
flutter create --platforms ios --project-name planner_app .
flutter pub get
flutter build ios --release --no-codesign
```

## Тесты

```bash
flutter test
```

Покрыты: извлечение JSON из ответа LLM, парсер tasks.json, периоды статистики.

## Структура

```
lib/
  main.dart                     — запуск, тема, провайдер стора
  theme.dart                    — дизайн-токены (#1E1E24 / #2B2B36 / #E0E0E0 / бирюза)
  models.dart                   — Note, Task, Goal, EventItem (isArchived)
  db.dart                       — sqflite, схема v2
  store.dart                    — состояние, CRUD, архив, статистика, интенты ассистента
  import_tasks.dart             — парсер tasks.json
  util.dart                     — форматирование дат
  services/
    ollama_service.dart         — HTTP-клиент Ollama + extractJson
    speech_service.dart         — распознавание русской речи
    notification_service.dart   — локальные уведомления (v17 API)
  ui/
    home_shell.dart             — нижняя навигация (7 вкладок)
    today_screen.dart           — Сегодня + быстрое добавление
    notes_screen.dart           — Заметки (поиск, «Архив»)
    calendar_screen.dart        — Календарь (события + дедлайны)
    tasks_screen.dart           — Задачи
    goals_screen.dart           — Цели (прогресс)
    stats_screen.dart           — Статистика (прогресс-бары + pie chart)
    strategy_screen.dart        — Стратегия на год (tasks.json, таблица + bar chart)
    assistant_screen.dart       — чат с Ollama + микрофон
    archive_screen.dart         — Архив (восстановление)
    edit_dialogs.dart           — модальные окна CRUD
test/                           — юнит-тесты
```
