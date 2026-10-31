import 'dart:io';
import 'package:ink_dart/ink_dart.dart';

void ensure(bool value, String label) {
  if (!value) throw StateError('FAILED: $label');
}

void advance(Story story) {
  while (story.canContinue) {
    story.continueStory();
  }
}

void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Pass path to compiled ink JSON');
  }
  final source = File(args.single).readAsStringSync();
  final story = Story.fromJson(source);
  advance(story);
  ensure(story.currentChoices.isNotEmpty, 'choices exist');
  final initialChoices = story.currentChoices.length;
  final save = story.state.toJson();
  story.chooseChoiceIndex(0);
  advance(story);
  story.state.loadJson(save);
  advance(story);
  ensure(story.currentChoices.length == initialChoices, 'save/restore choices');
  print('PASS ink_dart: compiled story playback + save/restore');
}
