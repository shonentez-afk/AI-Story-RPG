import 'package:flutter/foundation.dart';

import 'book_import.dart';
import 'book_source_index.dart';
import 'book_source_analysis.dart';
import 'source_evidence_graph.dart';
import 'story_evidence_review_session.dart';
import 'source_narrative_chronology.dart';
import 'source_relation_review.dart';

/// Entry points live OUTSIDE widget State methods. Flutter's native compute
/// sends only the explicit message and this top-level function to the worker.
/// An Isolate.run closure declared inside a State method can inadvertently
/// capture the complete State/BuildContext/RenderObject graph, causing
/// "Invalid argument(s): Illegal argument in isolate message".
///
/// Keep every message/result a plain Dart model. Never pass a Widget,
/// BuildContext, method tear-off bound to State, file picker, DB handle or
/// platform plugin through this boundary.

ImportedBook _parseImportedBook((String, Uint8List) request) =>
    BookImporter.parse(request.$1, request.$2);

Future<ImportedBook> parseImportedBookInWorker(
        String filename, Uint8List bytes) =>
    compute(_parseImportedBook, (filename, bytes),
        debugLabel: 'story-book-import');

BookSourceIndex _indexImportedBook(ImportedBook book) =>
    BookSourceIndexer.index(book);

Future<BookSourceIndex> indexImportedBookInWorker(ImportedBook book) =>
    compute(_indexImportedBook, book, debugLabel: 'story-book-index');

SourceAnalysisSession _decodeSourceAnalysis(
        (BookSourceIndex, String) request) =>
    SourceAnalysisSession.decode(request.$1, request.$2);

Future<SourceAnalysisSession> decodeSourceAnalysisInWorker(
        BookSourceIndex index, String raw) =>
    compute(_decodeSourceAnalysis, (index, raw),
        debugLabel: 'story-mentions-decode');

String _encodeSourceAnalysis(SourceAnalysisSession session) =>
    session.encode();

Future<String> encodeSourceAnalysisInWorker(SourceAnalysisSession session) =>
    compute(_encodeSourceAnalysis, session,
        debugLabel: 'story-mentions-encode');

SourceAnalysisSession _processSourceBatch(
        (BookSourceIndex, SourceAnalysisSession, int) request) =>
    request.$2.processBatch(request.$1, limit: request.$3);

Future<SourceAnalysisSession> processSourceBatchInWorker(
        BookSourceIndex index, SourceAnalysisSession current,
        {int limit = 24}) =>
    compute(_processSourceBatch, (index, current, limit),
        debugLabel: 'story-mentions-batch');

StoryEvidenceReviewSession _decodeNarrativeEvidence(
        (BookSourceIndex, String) request) =>
    StoryEvidenceReviewSession.decode(request.$1, request.$2);

Future<StoryEvidenceReviewSession> decodeNarrativeEvidenceInWorker(
        BookSourceIndex index, String raw) =>
    compute(_decodeNarrativeEvidence, (index, raw),
        debugLabel: 'story-evidence-decode');

String _encodeNarrativeEvidence(StoryEvidenceReviewSession session) =>
    session.encode();

Future<String> encodeNarrativeEvidenceInWorker(
        StoryEvidenceReviewSession session) =>
    compute(_encodeNarrativeEvidence, session,
        debugLabel: 'story-evidence-encode');

StoryEvidenceReviewSession _scanNarrativeEvidence(
        (BookSourceIndex, StoryEvidenceReviewSession, int) request) =>
    request.$2.scanNext(request.$1, limit: request.$3);

Future<StoryEvidenceReviewSession> scanNarrativeEvidenceInWorker(
        BookSourceIndex index, StoryEvidenceReviewSession session,
        {int limit = 24}) =>
    compute(_scanNarrativeEvidence, (index, session, limit),
        debugLabel: 'story-evidence-scan');

SourceRelationReviewSession _createRelationReview(
        (BookSourceIndex, SourceEvidenceGraph) request) =>
    SourceRelationReviewSession.create(request.$1, request.$2);

Future<SourceRelationReviewSession> createRelationReviewInWorker(
        BookSourceIndex index, SourceEvidenceGraph graph) =>
    compute(_createRelationReview, (index, graph),
        debugLabel: 'story-relations-create');

SourceRelationReviewSession _decodeRelationReview(
        (BookSourceIndex, SourceEvidenceGraph, String) request) =>
    SourceRelationReviewSession.decode(
        request.$1, request.$2, request.$3);

Future<SourceRelationReviewSession> decodeRelationReviewInWorker(
        BookSourceIndex index, SourceEvidenceGraph graph, String raw) =>
    compute(_decodeRelationReview, (index, graph, raw),
        debugLabel: 'story-relations-decode');

String _encodeRelationReview(SourceRelationReviewSession session) =>
    session.encode();

Future<String> encodeRelationReviewInWorker(
        SourceRelationReviewSession session) =>
    compute(_encodeRelationReview, session,
        debugLabel: 'story-relations-encode');

SourceNarrativeChronology _buildSourceChronology(
        (BookSourceIndex, SourceEvidenceGraph) request) =>
    SourceNarrativeChronology.build(request.$1, request.$2);

Future<SourceNarrativeChronology> buildSourceChronologyInWorker(
        BookSourceIndex index, SourceEvidenceGraph graph) =>
    compute(_buildSourceChronology, (index, graph),
        debugLabel: 'story-chronology');

SourceRelationReviewSession _decideRelation(
        (BookSourceIndex, SourceEvidenceGraph, SourceRelationReviewSession,
            String, IdentityDecision) request) =>
    request.$3.decide(request.$1, request.$2, request.$4, request.$5);

Future<SourceRelationReviewSession> decideRelationInWorker(
        BookSourceIndex index, SourceEvidenceGraph graph,
        SourceRelationReviewSession session,
        String relationId, IdentityDecision choice) =>
    compute(_decideRelation, (index, graph, session, relationId, choice),
        debugLabel: 'story-relations-decision');
