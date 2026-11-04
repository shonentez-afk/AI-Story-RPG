import 'dart:math';
import 'package:flutter/material.dart';
import 'free_text_action_gate.dart';
import 'free_text_world_gateway_port.dart';
import 'world_library_gateway.dart';

/// Optional, collapsed in WorldPlayPage. No automatic action execution.
/// Uses precisely the same gateway and SQLite campaign as classic buttons.
class FreeTextActionPanel extends StatefulWidget {
  const FreeTextActionPanel({
    super.key, required this.campaignId, required this.gateway,
    this.onCommitted, this.onBusyChanged,
  });
  final String campaignId;
  final WorldLibraryGateway gateway;
  final ValueChanged<WorldChoiceResult>? onCommitted;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<FreeTextActionPanel> createState() => _FreeTextActionPanelState();
}

class _FreeTextActionPanelState extends State<FreeTextActionPanel> {
  final _input = TextEditingController();
  FreeTextPreview? _preview;
  FreeTextProposal? _selected;
  String? _error;
  String? _notice;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant FreeTextActionPanel old) {
    super.didUpdateWidget(old);
    if (old.campaignId != widget.campaignId ||
        !identical(old.gateway, widget.gateway)) {
      _reset();
      _input.clear();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _reset() {
    _preview = null;
    _selected = null;
    _error = null;
    _notice = null;
  }

  Future<void> _propose() async {
    if (_busy) return;
    setState(() { _busy = true; _reset(); });
    try {
      final preview = await FreeTextWorldGatewayPort(widget.gateway)
          .preview(widget.campaignId, _input.text);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _error = preview.error;
        _notice = preview.canChoose
            ? 'Выберите вариант. Ход не выполняется до подтверждения.'
            : null;
      });
    } catch (_) {
      if (mounted) setState(() {
        _reset();
        _error = 'Не удалось прочитать кампанию. Обновите игру.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _actionId() {
    final epoch = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final secure = Random.secure().nextInt(1 << 31).toRadixString(36);
    return 'free_' + epoch + '_' + secure;
  }

  Future<void> _confirm() async {
    final selected = _selected;
    if (selected == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    widget.onBusyChanged?.call(true);
    try {
      final result = await FreeTextWorldGatewayPort(widget.gateway).confirm(
        proposal: selected, actionId: _actionId(), userConfirmed: true);
      if (!mounted) return;
      setState(() {
        _preview = null;
        _selected = null;
        _notice = result.applied
            ? 'Ход сохранён в текущей кампании.'
            : 'Ход отклонён. Обновите кампанию перед повтором.';
      });
      if (result.applied) {
        _input.clear();
        try {
          widget.onCommitted?.call(result);
        } catch (_) {
          if (mounted) setState(() => _notice =
              'Ход сохранён, но экран не обновился. Откройте игру заново.');
        }
      }
    } on FormatException catch (error) {
      if (mounted) setState(() {
        _preview = null;
        _selected = null;
        _error = error.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _preview = null;
        _selected = null;
        _error = 'Исход записи неизвестен. Сначала проверьте журнал '
            'и текущий ход; не выполняйте повтор вслепую.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted) widget.onBusyChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Офлайн-подбор из уже разрешённых действий. '
              'ИИ не создаёт события и не получает доступ к будущему сюжету.'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('free-text-input'), controller: _input,
            maxLength: FreeTextActionGate.maxTextRunes,
            minLines: 1, maxLines: 3,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(_reset),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Что хотите сделать?',
              hintText: 'Например: открыть дверь',
            ),
          ),
          OutlinedButton.icon(
            key: const Key('free-text-propose'),
            onPressed: _busy ? null : _propose,
            icon: const Icon(Icons.search),
            label: const Text('Найти доступные действия'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, key: const Key('free-text-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_notice != null) Text(_notice!),
          if (preview?.canChoose == true) ...[
            const SizedBox(height: 8),
            const Text('Варианты (ничего ещё не выполнено):'),
            for (final offer in preview!.offers)
              ListTile(
                key: Key('free-text-choice-' + offer.choiceId),
                title: Text(offer.label),
                trailing: Icon(_selected?.choiceId == offer.choiceId
                    ? Icons.check_circle : Icons.radio_button_unchecked),
                onTap: _busy ? null :
                    () => setState(() => _selected = offer),
              ),
            FilledButton.icon(
              key: const Key('free-text-confirm'),
              onPressed: _busy || _selected == null ? null : _confirm,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Подтвердить и сохранить ход'),
            ),
            TextButton(
              key: const Key('free-text-cancel'),
              onPressed: _busy ? null : () => setState(_reset),
              child: const Text('Отмена'),
            ),
          ],
        ],
      ),
    );
  }
}
