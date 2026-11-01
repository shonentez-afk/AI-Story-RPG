import 'package:flutter/material.dart';
import 'reading_preferences.dart';

/// The same reading controls in a book and in the story game.
class ReadingSettingsSheet extends StatefulWidget {
  const ReadingSettingsSheet({super.key, required this.preferences, required this.onChanged});
  final ReadingPreferences preferences;
  final ValueChanged<ReadingPreferences> onChanged;

  @override
  State<ReadingSettingsSheet> createState() => _ReadingSettingsSheetState();
}

class _ReadingSettingsSheetState extends State<ReadingSettingsSheet> {
  late ReadingPreferences value;
  @override
  void initState() { super.initState(); value = widget.preferences; }
  void apply(ReadingPreferences next) {
    setState(() => value = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Настройки чтения', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4,
          children: [
            for (final entry in <(ReadingPalette, String)>[
              (ReadingPalette.light, 'Свет'),
              (ReadingPalette.sepia, 'Сепия'),
              (ReadingPalette.dark, 'Тёмная'),
              (ReadingPalette.oled, 'OLED'),
            ])
              ChoiceChip(
                label: Text(entry.$2),
                selected: value.palette == entry.$1,
                onSelected: (_) => apply(value.copyWith(palette: entry.$1)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: value.horizontalPadding, vertical: 14),
          decoration: BoxDecoration(
            color: value.background,
            border: Border.all(color: value.foreground.withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('Образец текста: однажды история ожила на страницах книги.',
            style: TextStyle(color: value.foreground, fontSize: value.fontSize,
              height: value.lineHeight)),
        ),
        const SizedBox(height: 12),
        Text('Размер текста: ${value.fontSize.toStringAsFixed(0)}'),
        Slider(value: value.fontSize, min: 12, max: 32, divisions: 20,
          onChanged: (next) => apply(value.copyWith(fontSize: next))),
        Text('Интервал: ${value.lineHeight.toStringAsFixed(2)}'),
        Slider(value: value.lineHeight, min: 1.2, max: 2.2, divisions: 20,
          onChanged: (next) => apply(value.copyWith(lineHeight: next))),
        Text('Поля: ${value.horizontalPadding.toStringAsFixed(0)}'),
        Slider(value: value.horizontalPadding, min: 12, max: 48, divisions: 18,
          onChanged: (next) => apply(value.copyWith(horizontalPadding: next))),
      ]),
    ),
  );
}
