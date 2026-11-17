/// Pure model contracts for an externally reviewed or cloud-generated
/// list of source-cited event proposals. These objects NEVER establish canon,
/// actor knowledge, literary truth or gameplay permissions.
abstract interface class BookEventProposal {
  String get id;
  int get chapterIndex;
  int get blockIndex;
  int get startUtf16;
  String get label;
  String get quote;
  String get chunkId;
}

abstract interface class BookEventOutline {
  String get sourceFingerprint;
  int get totalChapters;
  int get chaptersWithEventProposals;
  bool get analysisComplete;
  List<BookEventProposal> get events;
}
