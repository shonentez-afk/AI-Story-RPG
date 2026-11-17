import 'dart:typed_data';

enum BookBlockKind { paragraph, heading, image }

class BookBlock {
  const BookBlock({required this.kind, this.text = '', this.resourceId});
  final BookBlockKind kind;
  final String text;
  final String? resourceId;

  Map<String, Object?> toJson() => {
    'kind': kind.name, 'text': text, 'resourceId': resourceId,
  };

  factory BookBlock.fromJson(Map<String, dynamic> json) => BookBlock(
    kind: BookBlockKind.values.byName(json['kind'] as String),
    text: json['text'] as String? ?? '',
    resourceId: json['resourceId'] as String?,
  );
}

class BookChapter {
  const BookChapter({required this.id, required this.blocks});
  final String id;
  final List<BookBlock> blocks;

  Map<String, Object?> toJson() => {
    'id': id, 'blocks': blocks.map((b) => b.toJson()).toList(),
  };

  factory BookChapter.fromJson(Map<String, dynamic> json) => BookChapter(
    id: json['id'] as String,
    blocks: (json['blocks'] as List)
        .map((x) => BookBlock.fromJson(x as Map<String, dynamic>))
        .toList(),
  );
}

class BookImage {
  const BookImage({required this.id, required this.bytes, required this.mediaType});
  final String id;
  final Uint8List bytes;
  final String mediaType;
}

enum GameMediaRole { scene, character, location, map, item, document, clue, decoration }
enum SpoilerPolicy { safeAnytime, canonOnly, afterEvent, discovered }

/// A proposed mapping; validation and spoiler policy enforcement belongs to
/// the deterministic game layer, never to the book importer.
class SceneMediaBinding {
  const SceneMediaBinding({
    required this.sceneId,
    required this.imageId,
    required this.role,
    this.spoilerPolicy = SpoilerPolicy.discovered,
    this.requiredEventId,
    this.interactive = false,
  });

  final String sceneId;
  final String imageId;
  final GameMediaRole role;
  final SpoilerPolicy spoilerPolicy;
  final String? requiredEventId;
  final bool interactive;
}
