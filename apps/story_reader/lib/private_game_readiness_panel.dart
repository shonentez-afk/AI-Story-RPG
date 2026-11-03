import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'private_game_readiness.dart';
import 'world_campaigns_page.dart';
import 'world_library_gateway.dart';

/// Separate three notions: indexed text, authored scenario, installed game.
/// Checking is opt-in on first visit to avoid accidental disk work during
/// ordinary book preparation; returning from the editor rechecks once.
class PrivateGameReadinessPanel extends StatefulWidget {
  const PrivateGameReadinessPanel({
    super.key,
    required this.index,
    required this.gateway,
    this.checkOnOpen = false,
  });

  final BookSourceIndex index;
  final WorldLibraryGateway gateway;
  final bool checkOnOpen;

  @override
  State<PrivateGameReadinessPanel> createState() =>
      _PrivateGameReadinessPanelState();
}

class _PrivateGameReadinessPanelState
    extends State<PrivateGameReadinessPanel> {
  Future<PrivateGameReadiness>? _pending;

  @override
  void initState() {
    super.initState();
    if (widget.checkOnOpen) _pending = _verify();
  }

  Future<PrivateGameReadiness> _verify() =>
      PrivateGameReadinessVerifier.assess(widget.index, widget.gateway);

  void _refresh() {
    final pending = _verify();
    setState(() { _pending = pending; });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Готовность книги к RPG',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('1. Текст: ${widget.index.indexedChapterCount} '
              'из ${widget.index.chapterCount} глав проиндексировано.'),
          const Text('2. Сценарий: подтвердите цитаты, сцены и '
              'авторскую альтернативу в редакторе.'),
          const SizedBox(height: 8),
          if (_pending == null)
            const Text('3. Игра: наличие установленного и проверенного '
                '.bworld ещё не проверялось.')
          else
            FutureBuilder<PrivateGameReadiness>(
              future: _pending,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Text('3. Игра: проверяем локальные пакеты…');
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Text('3. Игра: проверка не завершена. '
                      '${snapshot.error ?? "Повторите проверку."}');
                }
                final result = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('3. Игра: ${result.explanation}'),
                    if (result.canStartPrivateGame) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: const Key('prepare-open-verified-private-rpg'),
                        onPressed: () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute(builder: (_) =>
                                WorldCampaignsPage(
                                  world: result.world!,
                                  gateway: widget.gateway,
                                )),
                          );
                          if (mounted) _refresh();
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Открыть личную RPG'),
                      ),
                    ],
                  ],
                );
              },
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('prepare-recheck-game'),
            onPressed: _refresh,
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Проверить наличие игры'),
          ),
          const SizedBox(height: 6),
          const Text('100% текста не означает 100% сюжета. '
              'Ни одна проверка не отправляет книгу в сеть. '
              'Частная адаптация не даёт права на публикацию.'),
        ],
      ),
    ),
  );
}
