/// Run a token-protected loopback API for non-Dart RPG clients.
/// No public bind address, cloud transport or duplicate game mechanics.
import 'dart:convert';
import 'dart:io';

import 'package:ai_story_rpg_cli/rpg_loopback_server.dart';

Future<void> main(List<String> args) async {
  if (args.length == 1 && args.single == '--help') {
    stdout.writeln('Usage: dart run bin/rpg_server.dart '
        '--store PRIVATE_DIR [--port 0..65535]');
    stdout.writeln('Only 127.0.0.1; x-rpg-token authorization required.');
    return;
  }
  String? privateDirectory;
  var port = 0;
  final seen = <String>{};
  if (args.length.isOdd) {
    stderr.writeln('Invalid arguments');
    exitCode = 64;
    return;
  }
  for (var i = 0; i < args.length; i += 2) {
    final key = args[i];
    if (!seen.add(key)) {
      exitCode = 64;
      return;
    }
    if (key == '--store') {
      privateDirectory = args[i + 1];
    } else if (key == '--port') {
      final value = int.tryParse(args[i + 1]);
      if (value == null || value < 0 || value > 65535) {
        exitCode = 64;
        return;
      }
      port = value;
    } else {
      exitCode = 64;
      return;
    }
  }
  if (privateDirectory == null || privateDirectory.isEmpty) {
    stderr.writeln('Private --store directory required');
    exitCode = 64;
    return;
  }
  final RpgLoopbackServer host;
  try {
    host = await RpgLoopbackServer.bind(
        privateStoreDirectory: privateDirectory, port: port,
        token: Platform.environment['AI_RPG_HOST_TOKEN']);
  } on Exception {
    stderr.writeln(jsonEncode({
      'status': 'error', 'code': 'host_start_failed',
    }));
    exitCode = 1;
    return;
  }
  // The token is handed to the launching user's local console only.
  stdout.writeln(jsonEncode({
    'status': 'listening',
    'endpoint': host.endpoint.toString(),
    'header': 'x-rpg-token',
    'token': host.token,
    'protocol': 'ai_story_rpg_client_v1',
  }));
  await stdout.flush();
  try {
    await stdin.drain<void>();
  } finally {
    await host.close();
  }
}
