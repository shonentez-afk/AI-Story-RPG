import 'package:flutter/material.dart';

import 'npc_continuity_audit.dart';

/// Read-only preparation report. Does not create real actors or disclose
/// any NPC knowledge/secret/motivation text to the playable world.
class NpcContinuityPanel extends StatefulWidget {
  const NpcContinuityPanel({
    super.key,
    required this.audit,
    required this.onSelectProfile,
    this.scenarioWarning,
    this.enabled = true,
  });

  final NpcContinuityAudit audit;
  final ValueChanged<String> onSelectProfile;
  final String? scenarioWarning;
  final bool enabled;

  @override
  State<NpcContinuityPanel> createState() => _NpcContinuityPanelState();
}

class _NpcContinuityPanelState extends State<NpcContinuityPanel> {
  static const pageSize = 8;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final audit = widget.audit;
    final pages = audit.actors.isEmpty
        ? 1 : (audit.actors.length + pageSize - 1) ~/ pageSize;
    final page = _page.clamp(0, pages - 1).toInt();

    return ExpansionTile(
      key: const Key('npc-continuity-panel'),
      title: const Text('Проверка NPC и связей со сценарием'),
      subtitle: Text('${audit.actors.length} черновиков · '
          '${audit.relations.length} связей · '
          '${audit.findings.length} замечаний'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Предварительный просмотр без публикации. '
                  'Данные NPC, тайны, мотивации и знания не доступны '
                  'игровому персонажу, пока не появятся отдельные '
                  'правила раскрытия и подтверждённый игровой Actor ID.'),
              const SizedBox(height: 6),
              Text(audit.scenarioLinked
                  ? 'Черновик сцен найден. Соответствие глав проверяется '
                      'только как подсказка, не как доказательство появления NPC.'
                  : 'Многосценный сценарий ещё не найден или недоступен. '
                      'Проверка появления NPC в сценах не проводилась.'),
              if (widget.scenarioWarning != null)
                Text(widget.scenarioWarning!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              if (audit.actors.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Сначала создайте авторскую карточку NPC.'),
                ),
              if (audit.findings.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Возможные конфликты и незавершённые данные',
                    style: Theme.of(context).textTheme.titleSmall),
                const Text('Это запросы на ручную проверку, '
                    'не доказанные противоречия книги.'),
                for (final finding in audit.findings.take(12))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ${finding.message}', softWrap: true),
                        TextButton(
                          key: Key('npc-audit-pick-${finding.kind.name}-${finding.dossierId}'),
                          onPressed: widget.enabled
                              ? () => widget.onSelectProfile(finding.dossierId)
                              : null,
                          child: const Text('Открыть карточку'),
                        ),
                      ],
                    ),
                  ),
                if (audit.findings.length > 12)
                  Text('Ещё замечаний: ${audit.findings.length - 12}. '
                      'Проверьте список персонажей ниже.'),
              ],
              const Divider(height: 18),
              for (final actor in audit.actors
                  .skip(page * pageSize).take(pageSize))
                Card(
                  key: Key('npc-audit-actor-${actor.dossierId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(actor.displayName,
                            style: Theme.of(context).textTheme.titleSmall),
                        Text('Временный ID: ${actor.stagingId}',
                            softWrap: true),
                        Text('Первое подтверждённое упоминание: '
                            'глава ${actor.firstSourceChapter + 1} · '
                            'цитат: ${actor.mentionCount}'),
                        Text(audit.scenarioLinked
                            ? 'Потенциальных сцен не ранее первой цитаты: '
                                '${actor.possibleSceneIds.length}'
                            : 'Соответствие сценам не проверено'),
                        Text('Заметок: ${actor.noteGates.length} · '
                            'из них со ссылкой на источник: '
                            '${actor.noteGates.where((n) => !n.isAuthorial).length}'),
                        const Text('Секреты и знания не раскрываются '
                            'автоматически ни при какой главе.'),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            key: Key('npc-audit-open-${actor.dossierId}'),
                            onPressed: widget.enabled
                                ? () => widget.onSelectProfile(actor.dossierId)
                                : null,
                            child: const Text('Открыть для редактирования'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (pages > 1)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      key: const Key('npc-audit-prev'),
                      onPressed: page == 0 ? null :
                          () => setState(() => _page--),
                      child: const Text('Назад'),
                    ),
                    Text('Страница ${page + 1} из $pages'),
                    OutlinedButton(
                      key: const Key('npc-audit-next'),
                      onPressed: page + 1 >= pages ? null :
                          () => setState(() => _page++),
                      child: const Text('Дальше'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
