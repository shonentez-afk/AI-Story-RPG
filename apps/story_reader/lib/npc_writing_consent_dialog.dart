import 'package:flutter/material.dart';

import 'npc_campaign_writing_session.dart';

/// Viewing, expanding or cancelling never transmits data or saves permission.
class NpcWritingConsentDialog extends StatefulWidget {
  const NpcWritingConsentDialog({super.key, required this.request, required this.heroName});
  final NpcWritingRequest request;
  final String heroName;
  @override State<NpcWritingConsentDialog> createState() => _NpcWritingConsentDialogState();
}

class _NpcWritingConsentDialogState extends State<NpcWritingConsentDialog> {
  bool _checked = false;
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Передать показанные фрагменты в Z.ai?'),
    content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Герой: ${widget.heroName}. Новых разговоров: ${widget.request.candidateCount}. '
            'Запросов: ${widget.request.requestCount}, с повторами — не более '
            '${widget.request.maximumAttempts}. Готовые и ручные реплики '
            'не пересылаются. Применяются условия вашего аккаунта Z.ai.'),
        const Text('ИИ пишет черновик, но не меняет личности, игровые правила '
            'и согласия. Показанная роль не даёт герою знаний других NPC.'),
        if (widget.request.hasStoryContext) ...[
          const SizedBox(height: 8),
          const Text('Диалоги связаны с одобренным общим сюжетом.',
              key: Key('npc-writing-story-summary')),
          const Text('Будут показаны общая цель, конфликт, назначение актов и '
              'доступный для этой встречи мотив собеседника с его цитатами. '
              'Это авторский замысел, не канон и не секрет, уже известный героям. '
              'Зависимость от прежнего исхода не означает, что он состоялся. '
              'Мотивы с основанием в более позднем тексте не раскрываются.'),
          const Text('Смена сохранённого сюжета останавливает следующие запросы '
              'и запись запоздавшего ответа. Старые ручные реплики не удаляются.'),
        ],
        if (widget.request.inventoryContext != null) ...[
          const SizedBox(height: 8),
          const Text('Инвентарь проверен по путям выбранного варианта игры.',
              key: Key('npc-writing-inventory-summary')),
          const Text('Для каждой встречи показано, какие вещи у игрока есть '
              'всегда, только в части ветвей или отсутствуют. Это не текущий '
              'сейв и не знания собеседника. Проверены базовые пути до '
              'добавления NPC-ветвей; литературный смысл нужно проверить отдельно.'),
          const Text('При изменении героя, предметов или реплик новые запросы '
              'останавливаются. Отправленный ранее запрос отозвать нельзя; '
              'ответ старой редакции не должен перезаписывать новый черновик.'),
        ],
        ExpansionTile(key: const Key('npc-writing-exact-payload'),
          title: const Text('Точные данные для отправки'),
          children: [SelectableText(widget.request.shownText,
              key: const Key('npc-writing-shown-bytes'))]),
        CheckboxListTile(key: const Key('npc-writing-cloud-consent'), value: _checked,
          title: const Text('Разрешаю отправить показанные цитаты, роль, NPC, сюжет и сведения о предметах'),
          onChanged: (value) => setState(() => _checked = value == true)),
      ],
    ))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
      FilledButton(key: const Key('npc-writing-cloud-send'),
        onPressed: _checked ? () => Navigator.pop(context, true) : null,
        child: const Text('Подготовить черновики')),
    ],
  );
}
