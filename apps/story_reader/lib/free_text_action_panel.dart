import 'dart:math';
import 'package:flutter/material.dart';
import 'free_text_action_gate.dart';
import 'free_text_world_gateway_port.dart';
import 'ai_connection.dart';
import 'zai_gameplay_choice_advisor.dart';
import 'world_library_gateway.dart';
import 'world_ui_presenter.dart';
import 'package:story_core/story_core.dart' show FreeformActionDraft;

/// Optional, collapsed in WorldPlayPage. No automatic action execution.
/// Uses precisely the same gateway and SQLite campaign as classic buttons.
class FreeTextActionPanel extends StatefulWidget {
  const FreeTextActionPanel({
    super.key, required this.campaignId, required this.gateway,
    this.onCommitted, this.onBusyChanged, this.aiAdvisor,
    this.dynamicAvailable = false,
  });
  final String campaignId;
  final WorldLibraryGateway gateway;
  final ValueChanged<WorldChoiceResult>? onCommitted;
  final ValueChanged<bool>? onBusyChanged;
  final ZaiGameplayChoiceAdvisor? aiAdvisor;
  final bool dynamicAvailable;

  @override
  State<FreeTextActionPanel> createState() => _FreeTextActionPanelState();
}

class _FreeTextActionPanelState extends State<FreeTextActionPanel> {
  final _input = TextEditingController();
  FreeTextPreview? _preview;
  FreeTextProposal? _selected;
  FreeformActionDraft? _dynamicDraft;
  FreeformActionPreview? _dynamicPreview;
  WorldGameView? _draftSource;
  String? _error;
  String? _notice;
  bool _busy = false;
  ZaiGameplayCancellation? _aiCancellation;

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
    _aiCancellation?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _reset() {
    _aiCancellation?.cancel();
    _preview = null;
    _selected = null;
    _dynamicDraft = null;
    _dynamicPreview = null;
    _draftSource = null;
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

  Future<void> _askAi() async {
    if (_busy) return;
    final playerText = _input.text;
    if (playerText.trim().isEmpty) {
      setState(() => _error = 'Сначала опишите действие.');
      return;
    }
    FreeTextCampaignHead head;
    try {
      head = FreeTextWorldGatewayPort.headFromView(
          await widget.gateway.load(widget.campaignId));
    } catch (_) {
      if (mounted) setState(() => _error =
          'Не удалось проверить текущую сцену. Обновите игру.');
      return;
    }
    if (!mounted || _busy || head.isTerminal || head.choices.every(
        (choice) => !choice.enabled)) return;
    final campaignId = widget.campaignId;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('Передать действие в Z.ai?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Будут отправлены только ваша фраза и '
                  'подписи доступных сейчас действий. Текст книги, '
                  'скрытые знания персонажей, журнал, сохранения и '
                  'ключ API в тексте запроса не передаются.'),
              const SizedBox(height: 8),
              const Text('Точно отправляемая фраза:'),
              SelectableText(playerText),
              const SizedBox(height: 8),
              const Text('При тайм-ауте или перегрузке возможно '
                  'до двух автоматических повторов этого же запроса. '
                  'ИИ только предложит действие; для выполнения '
                  'потребуется отдельное подтверждение.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('free-text-ai-consent'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Отправить эту фразу'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || _busy ||
        widget.campaignId != campaignId || _input.text != playerText) return;
    final token = ZaiGameplayCancellation();
    setState(() {
      _reset();
      _busy = true;
      _aiCancellation = token;
      _notice = 'Проверяем разрешённый ход через Z.ai…';
    });
    try {
      final advisor = widget.aiAdvisor ?? ZaiGameplayChoiceAdvisor();
      final preview = await advisor.suggest(
        head: head,
        playerText: playerText,
        consentForThisAction: true,
        cancellation: token,
        onProgress: (attempt, total, status) {
          if (mounted && !token.isCancelled) {
            setState(() => _notice =
                'ИИ: ' + status + ' (' +
                attempt.toString() + '/' + total.toString() + ')');
          }
        },
      );
      if (!mounted || token.isCancelled || _input.text != playerText ||
          widget.campaignId != campaignId) return;
      final fresh = FreeTextWorldGatewayPort.headFromView(
          await widget.gateway.load(campaignId));
      if (!mounted || token.isCancelled) return;
      if (fresh.fingerprint != head.fingerprint) {
        setState(() {
          _error = 'Сцена изменилась во время запроса. '
              'Получите новое предложение.';
          _notice = null;
        });
        return;
      }
      setState(() {
        _preview = preview;
        _selected = null;
        _error = preview.error;
        _notice = preview.canChoose
            ? 'ИИ предложил разрешённый ход. Выберите вариант и '
              'подтвердите — ничего ещё не сохранено.'
            : null;
      });
    } on AiSetupException catch (error) {
      if (mounted && !token.isCancelled) setState(() {
        _error = error.message;
        _notice = null;
      });
    } catch (_) {
      if (mounted && !token.isCancelled) setState(() {
        _error = 'Не удалось проверить предложение ИИ. '
            'Выберите доступное действие вручную.';
        _notice = null;
      });
    } finally {
      if (mounted) setState(() {
        _busy = false;
        if (identical(_aiCancellation, token)) _aiCancellation = null;
      });
    }
  }

  /// A true new event. The model gets exactly the CURRENT displayed text,
  /// player request and limited fictional resource slots, with separate
  /// network consent. It cannot call the game's commit or edit book canon.
  Future<void> _askDynamic() async {
    if (_busy || !widget.dynamicAvailable ||
        widget.gateway is! WorldDynamicActionGateway) return;
    final text = _input.text.trim();
    if (text.isEmpty || text != _input.text) {
      setState(() => _error = 'Опишите свободное действие без пустых строк.');
      return;
    }
    final campaignId = widget.campaignId;
    late WorldGameView before;
    try {
      before = await widget.gateway.load(campaignId);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось открыть игру.');
      return;
    }
    if (!mounted || before.isTerminal || !before.freeformAvailable ||
        !before.sourceLiteralCanon) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('Создать новое игровое действие с Z.ai?'),
        content: const Text(
            'В модель отправятся ваша фраза, начало ТЕКУЩЕГО '
            'фрагмента книги (до 550 символов), до 5 последних '
            'уже выполненных вымышленных ИИ-ходов, игровые '
            'ресурсы gm_* и сведения о присутствующих проверенных NPC: '
            'их имена, доверие, число игровых воспоминаний и текущие '
            'вымышленные цели. НЕ отправляются вся книга, будущие '
            'главы, NPC-секреты, файлы сохранений или API-ключ. '
            'Предложение не изменит настоящий сюжет книги. '
            'Результат будет показан для отдельного подтверждения. '
            'При перегрузке возможны два повторных запроса.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('free-text-dynamic-consent'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Передать текущий фрагмент'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || _busy ||
        _input.text != text || widget.campaignId != campaignId) return;
    final cancel = ZaiGameplayCancellation();
    setState(() {
      _reset();
      _busy = true;
      _aiCancellation = cancel;
      _notice = 'ИИ создаёт новое неканоническое действие…';
    });
    try {
      final advisor = widget.aiAdvisor ?? ZaiGameplayChoiceAdvisor();
      final draft = await advisor.suggestDynamic(
        view: before, playerText: text,
        consentForThisAction: true,
        cancellation: cancel,
        onProgress: (attempt, total, status) {
          if (mounted && !cancel.isCancelled) {
            setState(() => _notice = status +
                ' (' + attempt.toString() + '/' + total.toString() + ')');
          }
        },
      );
      if (!mounted || cancel.isCancelled ||
          _input.text != text || widget.campaignId != campaignId) return;
      // This performs ONLY a speculative preview on a replayed world.
      final preview = await (widget.gateway as WorldDynamicActionGateway)
          .previewDynamic(campaignId, draft,
              expectedRevision: before.revision);
      if (!mounted || cancel.isCancelled ||
          _input.text != text || widget.campaignId != campaignId) return;
      if (preview.stateHash != before.stateHash) {
        throw const FormatException('Сцена изменилась во время ИИ.');
      }
      setState(() {
        _dynamicDraft = draft;
        _dynamicPreview = preview;
        _draftSource = before;
        _notice = 'Новое игровое событие ещё НЕ записано. '
            'Проверьте последствия ниже и подтвердите.';
        _error = null;
      });
    } on AiSetupException catch (error) {
      if (mounted && !cancel.isCancelled) {
        setState(() { _error = error.message; _notice = null; });
      }
    } on FormatException catch (error) {
      if (mounted && !cancel.isCancelled) {
        setState(() { _error = error.message; _notice = null; });
      }
    } catch (_) {
      if (mounted && !cancel.isCancelled) {
        setState(() {
          _error = 'ИИ не смог предложить проверяемое действие. '
              'Игра не изменена.';
          _notice = null;
        });
      }
    } finally {
      if (mounted) setState(() {
        _busy = false;
        if (identical(_aiCancellation, cancel)) _aiCancellation = null;
      });
    }
  }

  Future<void> _commitDynamic() async {
    final draft = _dynamicDraft, preview = _dynamicPreview;
    if (_busy || draft == null || preview == null ||
        widget.gateway is! WorldDynamicActionGateway) return;
    setState(() { _busy = true; _error = null; });
    widget.onBusyChanged?.call(true);
    try {
      final result = await (widget.gateway as WorldDynamicActionGateway)
          .commitDynamic(widget.campaignId,
              actionId: _actionId(),
              draft: draft,
              expectedRevision: preview.expectedRevision,
              approvalDigest: preview.approvalDigest,
              userConfirmed: true);
      if (!mounted) return;
      setState(() {
        _reset();
        _notice = result.applied
            ? 'Новое свободное действие записано в журнал и состояние игры.'
            : 'Свободное действие отклонено. Проверьте состояние.';
      });
      if (result.applied) {
        _input.clear();
        widget.onCommitted?.call(result);
      }
    } on FormatException catch (error) {
      if (mounted) setState(() {
        _reset();
        _error = error.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _reset();
        _error = 'Результат записи неизвестен. Проверьте журнал '
            'перед повторным подтверждением.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted) widget.onBusyChanged?.call(false);
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
          Text(widget.dynamicAvailable
              ? 'В книжном CANON доступен также новый ход ИИ: '
                  'отдельная вымышленная вставка с реальными '
                  'игровыми последствиями и записью в журнал. '
                  'Оригинальный текст книги остаётся неизменным.'
              : 'Опишите действие. Офлайн и ИИ подбирают только '
                  'разрешённые ходы, не создавая новых событий. '
                  'Отправка в Z.ai и сам ход требуют отдельных подтверждений.'),
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
          OutlinedButton.icon(
            key: const Key('free-text-ai-propose'),
            onPressed: _busy ? null : _askAi,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Подобрать с помощью ИИ'),
          ),
          if (widget.dynamicAvailable &&
              widget.gateway is WorldDynamicActionGateway)
            OutlinedButton.icon(
              key: const Key('free-text-ai-dynamic'),
              onPressed: _busy ? null : _askDynamic,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Создать НОВОЕ действие ИИ'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_busy && _aiCancellation != null)
            TextButton.icon(
              key: const Key('free-text-stop-ai'),
              onPressed: () {
                _aiCancellation?.cancel();
                setState(() => _notice =
                    'Остановлены новые попытки ИИ. Уже отправленный запрос '
                    'нельзя отозвать; игровой ход не совершён.');
              },
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Остановить запрос к ИИ'),
            ),
          if (_error != null)
            Text(_error!, key: const Key('free-text-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_notice != null) Text(_notice!),
          if (_dynamicDraft != null && _dynamicPreview != null) ...[
            const SizedBox(height: 10),
            const Text('Проверенное предложение. НЕ канон книги:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_dynamicDraft!.narration,
                key: const Key('free-text-dynamic-narration')),
            const SizedBox(height: 6),
            const Text('Движок проверил предложение, но это ещё '
                'не сохранённое событие. Последствия и режим после '
                'записи будут показаны из нового состояния игры.'),
            const SizedBox(height: 6),
            if (_draftSource != null)
              Column(
                key: const Key('free-text-dynamic-impact'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in WorldUiPresenter.dynamicImpact(
                    _dynamicDraft!, _draftSource!,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(line),
                    ),
                ],
              ),
            FilledButton.icon(
              key: const Key('free-text-dynamic-confirm'),
              onPressed: _busy ? null : _commitDynamic,
              icon: const Icon(Icons.check_circle),
              label: const Text('Подтвердить НОВЫЙ ход и сохранить'),
            ),
            TextButton(
              key: const Key('free-text-dynamic-cancel'),
              onPressed: _busy ? null : () => setState(_reset),
              child: const Text('Отклонить предложение'),
            ),
          ],
          if (preview?.canChoose == true) ...[
            const SizedBox(height: 8),
            const Text('Варианты (ничего ещё не выполнено):'),
            for (final offer in preview!.offers)
              // ListTile must paint onto its own Material surface when the
              // reader page uses an opaque reading-themed ColoredBox.
              Material(
                color: Colors.transparent,
                child: ListTile(
                  key: Key('free-text-choice-' + offer.choiceId),
                  title: Text(offer.label),
                  trailing: Icon(_selected?.choiceId == offer.choiceId
                      ? Icons.check_circle : Icons.radio_button_unchecked),
                  onTap: _busy ? null :
                      () => setState(() => _selected = offer),
                ),
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
