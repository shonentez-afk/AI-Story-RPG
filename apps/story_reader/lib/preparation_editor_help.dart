import 'package:flutter/material.dart';

/// Human-facing guidance for the optional advanced book-to-RPG editors.
/// Hidden instructions never gate features or mutate a preparation checkpoint.
class PreparationEditorHelp extends StatelessWidget {
  const PreparationEditorHelp({
    super.key,
    required this.purpose,
    required this.steps,
    required this.result,
    required this.next,
  });

  final String purpose;
  final List<String> steps;
  final String result;
  final String next;

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          title: const Text('Что здесь делать?'),
          subtitle: Text(purpose),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (final (index, step) in steps.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${index + 1}. $step'),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Результат: $result'),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Дальше: $next'),
            ),
          ],
        ),
      );
}
