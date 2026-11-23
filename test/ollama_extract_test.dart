import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/services/ollama_service.dart';

void main() {
  group('OllamaService.extractJson', () {
    test('чистый JSON парсится', () {
      final j = OllamaService.extractJson('{"action":"add_task","title":"позвонить"}');
      expect(j, isNotNull);
      expect(j!['action'], 'add_task');
      expect(j['title'], 'позвонить');
    });

    test('JSON с текстом вокруг вырезается', () {
      final j = OllamaService.extractJson(
          'Вот ответ: {"action":"add_note","title":"идея"} надеюсь помогло');
      expect(j, isNotNull);
      expect(j!['action'], 'add_note');
    });

    test('одинарные кавычки заменяются', () {
      final j = OllamaService.extractJson("{'action':'add_goal','title':'цель'}");
      expect(j, isNotNull);
      expect(j!['title'], 'цель');
    });

    test('многострочный JSON', () {
      final j = OllamaService.extractJson('{\n  "action": "list_today"\n}');
      expect(j, isNotNull);
      expect(j!['action'], 'list_today');
    });

    test('без JSON -> null (не падаем)', () {
      expect(OllamaService.extractJson('просто текст без джсона'), isNull);
      expect(OllamaService.extractJson(''), isNull);
    });

    test('битый JSON -> null (не падаем)', () {
      expect(OllamaService.extractJson('{"action": "add_task", битый}'), isNull);
    });
  });
}
