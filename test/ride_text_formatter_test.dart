import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/features/cycling/ride_text_formatter.dart';

void main() {
  const formatter = RideTextFormatter();
  TextEditingValue input(String text, {int? cursor}) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length),
  );
  test(
    'capitalizes only the first alphabetic character and preserves remainder/cursor',
    () {
      for (final pair in [
        ('standing Bear w Wes', 'Standing Bear w Wes'),
        ('test', 'Test'),
        ('great ride with wes', 'Great ride with wes'),
        ('  123 - standing Bear', '  123 - Standing Bear'),
        ('?cole w WES', '?cole w WES'),
        ('GREAT ride', 'GREAT ride'),
        ('123 !', '123 !'),
        ('', ''),
      ]) {
        final value = input(pair.$1, cursor: pair.$1.isEmpty ? 0 : 1);
        final result = formatter.formatEditUpdate(
          TextEditingValue.empty,
          value,
        );
        expect(result.text, pair.$2);
        expect(result.selection, value.selection);
      }
    },
  );
  test(
    'preserves selection when editing in the middle, including Unicode case expansion',
    () {
      final result = formatter.formatEditUpdate(
        input('Standing Bear'),
        input('Standing xBear', cursor: 10),
      );
      expect(result.text, 'Standing xBear');
      expect(result.selection.baseOffset, 10);
      final expanded = formatter.formatEditUpdate(
        TextEditingValue.empty,
        input('?eta', cursor: 1),
      );
      expect(expanded.text, '${'?'.toUpperCase()}eta');
      expect(expanded.selection.baseOffset, '?'.toUpperCase().length);
    },
  );
  test(
    'leaves saved text unchanged without an edit and waits for IME composition to commit',
    () {
      final existing = input('standing Bear w Wes');
      expect(formatter.formatEditUpdate(existing, existing), existing);
      const composing = TextEditingValue(
        text: 'test',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, composing),
        composing,
      );
      expect(formatter.formatEditUpdate(composing, input('test')).text, 'Test');
      expect(
        formatter.formatEditUpdate(input('Test'), TextEditingValue.empty),
        TextEditingValue.empty,
      );
    },
  );
}
