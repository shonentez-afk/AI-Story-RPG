import 'package:story_core/story_core.dart';
import 'package:story_engine/story_engine.dart';

/// One public contract for a prepared offline world. UI never receives the
/// mutable story_engine instance, nor may it alter world state directly.
abstract class StoryRuntimeAdapter {
  WorldState get state;
  List<WorldEvent> get events;
  /// Current committed knowledge; source text alone never grants a fact.
  bool actorKnowsFact(String actorId, String factId);
  /// Immutable committed events which granted the fact to this actor.
  List<WorldEvent> factLearningEvents(String actorId, String factId);
  /// Exact missing fact IDs for a source-reviewed line (not proof of canon).
  List<String> missingKnowledgeForActor(
      String actorId, Iterable<String> requiredFactIds);
  bool get isTerminal;
  String get sceneId;
  /// The exact current scene's verified narrative text, without UI rendering.
  String get sceneText;
  List<RuntimeChoice> get choices;

  DecisionResult choose({
    required String actionId,
    required String choiceId,
    int? expectedRevision,
  });

  DecisionResult freeform({
    required String actionId,
    required FreeformActionDraft draft,
    int? expectedRevision,
  });

  /// Private social preview derived from current committed events and an
  /// exact-blueprint rulebook. Not a new world mutation or save format.
  NpcSocialSnapshot inspectNpcSocial(NpcSocialRulebook rulebook);

  Map<String, dynamic> checkpoint();
}

class RuntimeChoice {
  const RuntimeChoice({
    required this.id,
    required this.label,
    this.lockReason,
  });

  final String id;
  final String label;
  final String? lockReason;

  bool get enabled => lockReason == null;
}

/// M1.7.2: a temporary, deterministic in-memory coordinator. Navigation is
/// implemented by the already-selected story_engine (ADR-001). Authoritative
/// facts, items, rules, event IDs and hashes belong ONLY to story_core.
///
/// This bridge deliberately accepts prepared original-demo blueprints only.
/// There is no Python, LLM, SQLite, user-file execution or new save format.
class StoryEngineCoordinator implements StoryRuntimeAdapter {
  StoryEngineCoordinator._(
    this.blueprint,
    this._project,
    this._engine,
    this._world,
  ) {
    _ensureSynchronized();
  }

  final StoryBlueprint blueprint;
  final StoryProject _project;
  StoryEngine _engine;
  StoryWorld _world;

  static StoryEngineCoordinator start(StoryBlueprint blueprint,
      {NpcSocialRulebook? socialRulebook}) {
    final project = _buildProject(blueprint);
    final report = StoryValidator.validate(project);
    if (report.hasErrors) {
      throw FormatException('Invalid scenario: ${report.format()}');
    }
    final engine = StoryEngine(project: project)..start();
    return StoryEngineCoordinator._(
      blueprint, project, engine,
      StoryWorld(blueprint, socialRulebook: socialRulebook),
    );
  }

  @override
  WorldState get state => _world.state;

  @override
  List<WorldEvent> get events => _world.events;

  @override
  bool get isTerminal => _world.isTerminal;

  @override
  bool actorKnowsFact(String actorId, String factId) =>
      _world.actorKnowsFact(actorId, factId);

  @override
  List<WorldEvent> factLearningEvents(String actorId, String factId) =>
      _world.factLearningEvents(actorId, factId);

  @override
  List<String> missingKnowledgeForActor(
          String actorId, Iterable<String> requiredFactIds) =>
      _world.missingKnowledgeForActor(actorId, requiredFactIds);

  @override
  NpcSocialSnapshot inspectNpcSocial(NpcSocialRulebook rulebook) {
    _ensureSynchronized();
    return NpcSocialLedger.inspect(_world, rulebook);
  }

  @override
  String get sceneId => state.sceneId;

  @override
  String get sceneText => blueprint.scenes[sceneId]!.text;

  @override
  List<RuntimeChoice> get choices {
    _ensureSynchronized();
    return List.unmodifiable(
      blueprint.scenes[sceneId]!.choices.map((choice) => RuntimeChoice(
        id: choice.id,
        label: choice.label,
        lockReason: _world.choiceLockReason(choice.id),
      )),
    );
  }

  @override
  DecisionResult choose({
    required String actionId,
    required String choiceId,
    int? expectedRevision,
  }) {
    _ensureSynchronized();

    // 1. Validate conditions and ALL effects against a private copy. Denials
    //    and duplicate action IDs leave the active engine and core untouched.
    final tentativeWorld = _world.fork();
    final result = tentativeWorld.apply(
      actionId: actionId,
      choiceId: choiceId,
      expectedRevision: expectedRevision,
    );
    if (!result.applied) return result;

    // 2. Restore an independent story_engine copy from the current state.
    //    Even an exception in choose() cannot move the live navigation.
    final tentativeEngine = StoryEngine.restore(
      project: _project,
      snapshot: _engine.createSnapshot(),
    );
    final available = tentativeEngine.availableChoices
        .any((choice) => choice.id.value == choiceId);
    if (!available) {
      throw StateError('Runtime rejected a world-authorized choice');
    }
    tentativeEngine.choose(StoryChoiceId(choiceId));
    if (tentativeEngine.currentEvent?.id.value !=
        tentativeWorld.state.sceneId) {
      throw StateError('Runtime transition differs from world transition');
    }

    // 3. Check ALL invariants *before* publishing. Never call throwing
    //    validation after modifying either active reference.
    _verifyPair(tentativeEngine, tentativeWorld);
    _engine = tentativeEngine;
    _world = tentativeWorld;
    return result;
  }

  /// Free actions preserve the signed canonical scene/navigation. The
  /// story_engine instance cannot be advanced without a compiled choice.
  /// New replayable consequences instead belong to the same story_core.
  @override
  DecisionResult freeform({
    required String actionId,
    required FreeformActionDraft draft,
    int? expectedRevision,
  }) {
    _ensureSynchronized();
    final candidate = _world.fork();
    final result = candidate.applyFreeform(
      actionId: actionId, draft: draft, expectedRevision: expectedRevision);
    if (!result.applied) return result;
    // Validate the unchanged navigation runtime against the new core state
    // before swapping either reference.
    _verifyPair(_engine, candidate);
    _world = candidate;
    return result;
  }

  /// An intermediate, engine-neutral **in-memory** checkpoint. This is NOT
  /// the old .bwsave, and provides no durable SQLite/ACID guarantees.
  @override
  Map<String, dynamic> checkpoint() => {
    'format': 'ai_story_bridge_checkpoint_v1',
    'schema_version': 1,
    'book_id': blueprint.bookId,
    'blueprint_sha256': blueprint.blueprintHash,
    'revision': state.revision,
    'state_sha256': state.stateHash,
    'head_event_sha256': events.isEmpty ? null : events.last.hash,
    'events': events.map((event) => event.toJson()).toList(growable: false),
  };

  /// Rebuilds BOTH story_core and story_engine from verified accepted actions.
  /// The old opaque story_engine snapshot is never trusted as world state.
  static StoryEngineCoordinator restore(
    StoryBlueprint blueprint,
    Object? rawCheckpoint, {
    NpcSocialRulebook? socialRulebook,
  }) {
    if (rawCheckpoint is! Map<String, dynamic>) {
      throw const FormatException('Checkpoint must be a JSON object');
    }
    const keys = {
      'format', 'schema_version', 'book_id', 'blueprint_sha256',
      'revision', 'state_sha256', 'head_event_sha256', 'events',
    };
    if (rawCheckpoint.keys.toSet().length != keys.length ||
        !rawCheckpoint.keys.toSet().containsAll(keys) ||
        rawCheckpoint['format'] != 'ai_story_bridge_checkpoint_v1' ||
        rawCheckpoint['schema_version'] != 1 ||
        rawCheckpoint['book_id'] != blueprint.bookId ||
        rawCheckpoint['blueprint_sha256'] != blueprint.blueprintHash) {
      throw const FormatException('Incompatible or malformed checkpoint');
    }
    final revision = rawCheckpoint['revision'];
    final stateHash = rawCheckpoint['state_sha256'];
    final events = rawCheckpoint['events'];
    if (revision is! int || revision < 0 || revision > 2000 ||
        stateHash is! String || events is! List ||
        events.length != revision || events.length > 2000) {
      throw const FormatException('Invalid checkpoint event count');
    }
    final checked = StoryWorld.replay(
      blueprint,
      events,
      expectedSequence: revision,
      expectedStateHash: stateHash,
      socialRulebook: socialRulebook,
    );
    final expectedHead = checked.events.isEmpty
        ? null : checked.events.last.hash;
    if (rawCheckpoint['head_event_sha256'] != expectedHead) {
      throw const FormatException('Checkpoint event head mismatch');
    }

    // Verify that the selected runtime can navigate the *exact* same log.
    // Any failure throws before returning an instance to the caller.
    final coordinator =
        StoryEngineCoordinator.start(blueprint, socialRulebook: socialRulebook);
    for (final event in checked.events) {
      final result = event.freeform != null
          ? coordinator.freeform(
              actionId: event.actionId,
              draft: event.freeform!,
              expectedRevision: coordinator.state.revision,
            )
          : coordinator.choose(
              actionId: event.actionId,
              choiceId: event.choiceId,
              expectedRevision: coordinator.state.revision,
            );
      if (!result.applied || result.event!.hash != event.hash ||
          coordinator.sceneId != event.nextSceneId) {
        throw const FormatException('Scenario/world replay disagreement');
      }
    }
    if (coordinator.state.stateHash != checked.state.stateHash ||
        coordinator.state.revision != revision) {
      throw const FormatException('Replayed world state mismatch');
    }
    return coordinator;
  }

  void _ensureSynchronized() => _verifyPair(_engine, _world);

  void _verifyPair(StoryEngine engine, StoryWorld world) {
    if (engine.currentEvent?.id.value != world.state.sceneId) {
      throw StateError('Runtime and world disagree about current scene');
    }
    final runtimeIds = engine.availableChoices
        .map((choice) => choice.id.value).toSet();
    final worldIds = blueprint.scenes[world.state.sceneId]!.choices
        .map((choice) => choice.id).toSet();
    if (runtimeIds.length != worldIds.length ||
        !runtimeIds.containsAll(worldIds)) {
      throw StateError('Runtime and world disagree about choice catalog');
    }
  }

  static StoryProject _buildProject(StoryBlueprint blueprint) => StoryProject(
    id: StoryProjectId(blueprint.bookId),
    entryEventId: StoryEventId(blueprint.entrySceneId),
    events: [
      for (final scene in blueprint.scenes.values)
        StoryEvent(
          id: StoryEventId(scene.id),
          presentation: StoryEventPresentation(
            body: StoryText(scene.text),
          ),
          choices: [
            for (final choice in scene.choices)
              StoryChoice(
                id: StoryChoiceId(choice.id),
                presentation: StoryChoicePresentation(
                  text: StoryText(choice.label),
                ),
                transition: StoryEventTransition(
                  destinationEventId: StoryEventId(choice.nextSceneId),
                ),
              ),
          ],
          // Ending prose remains visible. The explicit Continue belongs to
          // story_engine; core refuses further choices in a terminal scene.
          continuationTransition: scene.terminal
              ? const StoryTerminalTransition() : null,
        ),
    ],
  );
}
