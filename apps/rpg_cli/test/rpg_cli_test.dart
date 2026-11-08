import 'dart:convert';
import 'dart:io';
import 'package:ai_story_rpg_cli/rpg_cli_client.dart';
import 'package:test/test.dart';

void main() {
  const cli = RpgCliClient();

  test('second client reopens SQLite and imports identical signed replay',
      () async {
    final fixture = File(
        '../../artifacts/bookworld/book_private_rich_items_python.bworld');
    expect(fixture.existsSync(), isTrue);
    final privateDir = await Directory.systemTemp.createTemp('cli_rpg_');
    try {
      final db = privateDir.path + '/db';
      final installed = await cli.execute([
        'install', '--store', db, '--world', fixture.path]);
      final hash = installed['world_hash'] as String;
      expect(hash.length, 64);
      final started = await cli.execute([
        'start', '--store', db, '--world-hash', hash]);
      final id = started['campaign_id'] as String;
      expect(started['revision'], 0);
      expect(started['inventory'], isNot(contains('map')));
      final denied = await cli.execute([
        'choose', '--store', db, '--campaign', id,
        '--choice', 'help', '--action', 'cli_denied', '--revision', '0']);
      expect(denied['applied'], false);
      expect(denied['revision'], 0);
      final first = await cli.execute([
        'choose', '--store', db, '--campaign', id,
        '--choice', 'wait', '--action', 'cli_wait', '--revision', '0']);
      expect(first['applied'], true);
      expect(first['revision'], 1);
      final second = await cli.execute([
        'choose', '--store', db, '--campaign', id,
        '--choice', 'give_map', '--action', 'cli_map', '--revision', '1']);
      expect(second['applied'], true);
      expect(second['revision'], 2);
      expect(second['journal'], hasLength(2));
      final reopened = await cli.execute([
        'view', '--store', db, '--campaign', id]);
      expect(reopened['revision'], 2);
      expect(reopened['scene_id'], second['scene_id']);
      expect(reopened['journal'], second['journal']);
      expect(reopened['inventory'], second['inventory']);
      final worlds = await cli.execute(['worlds', '--store', db]);
      expect(worlds['worlds'], hasLength(1));
      final games = await cli.execute([
        'campaigns', '--store', db, '--world-hash', hash]);
      expect(games['campaigns'], hasLength(1));

      final save = privateDir.path + '/portable.bwsave';
      await cli.execute([
        'export-save', '--store', db, '--campaign', id, '--output', save]);
      await expectLater(cli.execute([
        'export-save', '--store', db, '--campaign', id, '--output', save]),
        throwsA(isA<FileSystemException>()));
      final restored = await cli.execute([
        'import-save', '--store', db, '--world-hash', hash, '--input', save]);
      expect(restored['revision'], 2);
      expect(restored['journal'], second['journal']);
      expect(restored['inventory'], second['inventory']);
      expect(restored['npc_encountered'], second['npc_encountered']);
      await expectLater(cli.execute([
        'import-save', '--store', db, '--world-hash', 'f' * 64,
        '--input', save]), throwsFormatException);
      await expectLater(cli.execute([
        'choose', '--store', db, '--campaign', id,
        '--choice', 'give_map', '--action', 'bad', '--revision', 'NaN']),
        throwsFormatException);
    } finally {
      await privateDir.delete(recursive: true);
    }
  });

  test('CLI source scopes a separate tale without claiming playable canon',
      () async {
    final dir = await Directory.systemTemp.createTemp('cli_book_');
    try {
      final file = File(dir.path + '/tales.fb2');
      await file.writeAsBytes(utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
        '<description><title-info><book-title>Сказки</book-title>'
        '</title-info></description><body>'
        '<section><p>Алиса вошла в дом.</p></section>'
        '<section><p>Борис нашёл ключ.</p></section>'
        '</body></FictionBook>'));
      final all = await cli.execute(['prepare', '--book', file.path]);
      final one = await cli.execute(
          ['prepare', '--book', file.path, '--chapter', '1']);
      expect(one['indexed_chapters'], 1);
      expect(one['is_playable_rpg'], false);
      expect(one['is_literary_canon'], false);
      expect(one['requires_cloud'], false);
      expect(all['source_fingerprint'], isNot(one['source_fingerprint']));
      await expectLater(cli.execute(
          ['prepare', '--book', file.path, '--chapter', '0']),
          throwsFormatException);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
