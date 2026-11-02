import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'private_game_readiness.dart';
import 'world_campaigns_page.dart';
import 'world_library_gateway.dart';

/// A truthful end-of-preparation gate: text indexing is not a playable game.
/// The "Open" action only appears for an independently verified, installed
/// private BookWorld with an exact source fingerprint.
class PrivateGameReadinessPanel extends StatefulWidget {
  const PrivateGameReadinessPanel({
    super.key,
    required this.index,
    required this.gateway,
  });

  final BookSourceIndex index;
  final WorldLibraryGateway gateway;

  @override
  State<PrivateGameReadinessPanel> createState() =>
      _PrivateGameReadinessPanelState();
}

class _PrivateGameReadinessPanelState
    extends State<PrivateGameReadinessPanel> {
  late Future<PrivateGameReadiness> _future;

  @override
  void initState() {
    super.initState();
    _future = PrivateGameReadinessVerifier.assess(
        widget.index, widget.gateway);
  }

  void _refresh() {
    setState(() {
      _future = PrivateGameReadinessVerifier.assess(
          widget.index, widget.gateway);
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<PrivateGameReadiness>(
        future: _future,
        builder: (context, snapshot) {
          final result = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Итог подготовки к игре',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Текст: ${widget.index.indexedChapterCount} '
                  'из ${widget.index.chapterCount} глав проиндексировано.'),
              const SizedBox(height: 4),
              if (snapshot.connectionState != ConnectionState.done)
                const Text('Проверяем сохранённые игровые пакеты…')
              else if (snapshot.hasError)
                Text('Проверка готовности не завершена: '
                    '${snapshot.error}')
              else ...[
                Text(result!.explanation),
                const SizedBox(height: 8),
                if (result.canStartPrivateGame)
                  FilledButton.icon(
                    key: const Key('prepare-open-verified-private-rpg'),
                    onPressed: () async {
                      await Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) =>
                              WorldCampaignsPage(
                                world: result.world!,
                                gateway: widget.gateway,
                              )));
                      if (mounted) _refresh();
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Открыть личную RPG'),
                  ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('prepare-recheck-game'),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Проверить наличие игры'),
              ),
              const SizedBox(height: 4),
              const Text('Охват текста и наличие игровой адаптации — '
                  'разные проверки. Личная RPG не даёт права '
                  'распространять оригинальную книгу.'),
            ],
          );
        },
      ),
    ),
  );
}
