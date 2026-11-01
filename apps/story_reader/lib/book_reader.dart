import 'package:flutter/material.dart';
import 'book_import.dart';

class BookReaderPage extends StatelessWidget {
  const BookReaderPage({super.key, required this.book});
  final ImportedBook book;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(book.title)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (book.cover != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Image.memory(
                      book.cover!,
                      height: 280,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(Icons.menu_book),
                    ),
                  ),
                Text(book.title, style: Theme.of(context).textTheme.headlineMedium),
                if (book.author.isNotEmpty) Text(book.author),
                const SizedBox(height: 24),
                for (var i = 0; i < book.chapters.length; i++) ...[
                  Text('Глава ${i + 1}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SelectableText(book.chapters[i],
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
                  const SizedBox(height: 28),
                ],
                const Text('Режим чтения • преобразование книги в RPG появится позже'),
              ],
            ),
          ),
        ),
      );
}
