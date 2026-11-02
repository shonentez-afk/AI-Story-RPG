import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Shared visibility contract for both the book and RPG reader.
/// Story choices and book navigation remain in the page body in all modes.
enum ReaderChromeMode { normal, reading, fullscreen }

extension ReaderChromeModeUi on ReaderChromeMode {
  bool get showTopBar => this == ReaderChromeMode.normal;
  bool get showGameBar => this != ReaderChromeMode.fullscreen;
  ReaderChromeMode get toggled =>
      this == ReaderChromeMode.normal ? ReaderChromeMode.reading : ReaderChromeMode.normal;
}

class ReaderChromeButton extends StatelessWidget {
  const ReaderChromeButton({
    super.key,
    required this.mode,
    required this.background,
    required this.foreground,
    required this.onChange,
  });

  final ReaderChromeMode mode;
  final Color background;
  final Color foreground;
  final ValueChanged<ReaderChromeMode> onChange;

  void _showModes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_agenda_outlined),
              title: const Text('Обычный режим'),
              onTap: () {
                Navigator.pop(sheetContext);
                onChange(ReaderChromeMode.normal);
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_open),
              title: const Text('Режим чтения'),
              onTap: () {
                Navigator.pop(sheetContext);
                onChange(ReaderChromeMode.reading);
              },
            ),
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: const Text('Полный экран'),
              onTap: () {
                Navigator.pop(sheetContext);
                onChange(ReaderChromeMode.fullscreen);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: mode == ReaderChromeMode.normal
        ? 'Скрыть управление чтением'
        : 'Показать управление чтением',
    hint: 'Нажатие переключает управление. Долгое нажатие или '
        'контекстное действие открывает все три режима.',
    onLongPress: () => _showModes(context),
    customSemanticsActions: {
      const CustomSemanticsAction(label: 'Выбрать режим экрана'):
          () => _showModes(context),
    },
    child: Tooltip(
    message: mode == ReaderChromeMode.normal
        ? 'Скрыть управление' : 'Показать управление',
    triggerMode: TooltipTriggerMode.manual,
    child: GestureDetector(
      onLongPress: () => _showModes(context),
      onSecondaryTap: () => _showModes(context),
      child: FloatingActionButton(
        heroTag: null,
        backgroundColor: background,
        foregroundColor: foreground,
        onPressed: () => onChange(mode.toggled),
        child: Icon(mode == ReaderChromeMode.normal
            ? Icons.visibility_off : Icons.visibility),
      ),
    ),
  ),
  );
}
