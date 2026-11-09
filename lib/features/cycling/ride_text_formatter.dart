import 'package:flutter/services.dart';

/// Formats user input only; loading or saving existing text does not invoke it.
class RideTextFormatter extends TextInputFormatter {
  const RideTextFormatter();
  static final _letter = RegExp(r'\p{L}', unicode: true);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final committed = !oldValue.composing.isCollapsed;
    if (oldValue.text == newValue.text && !committed) return newValue;
    final first = _letter.firstMatch(newValue.text);
    if (first == null) return newValue;
    final upper = first.group(0)!.toUpperCase();
    if (upper == first.group(0)) return newValue;
    final delta = upper.length - (first.end - first.start);
    int offset(int value) => value <= first.start
        ? value
        : value >= first.end
        ? value + delta
        : first.start + upper.length;
    return newValue.copyWith(
      text: newValue.text.replaceRange(first.start, first.end, upper),
      selection: newValue.selection.copyWith(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
      ),
      composing: newValue.composing.isValid
          ? TextRange(
              start: offset(newValue.composing.start),
              end: offset(newValue.composing.end),
            )
          : newValue.composing,
    );
  }
}
