/// Independent command-line client. No Flutter or second engine.
import 'dart:convert';
import 'dart:io';
import 'package:ai_story_rpg_cli/rpg_cli_client.dart';

const usage = '''
AI Story RPG — offline API client, JSON responses.
  prepare     --book FILE.fb2|FILE.txt [--chapter N]
  prepare-literal-canon-v5 --book FILE.fb2|FILE.txt
  compile-literal-canon-v5 --book FILE --approved-digest SHA256
                           --user-confirmed true --output PRIVATE.bworld
  compile-reviewed-causal-v5 --book FILE --base-world LITERAL.bworld
                             --review PRIVATE.json --approved-digest SHA256
                             --user-confirmed true --output PRIVATE.bworld
  install     --store PRIVATE_DIR --world FILE.bworld
  worlds      --store PRIVATE_DIR
  campaigns   --store PRIVATE_DIR [--world-hash SHA256]
  start       --store PRIVATE_DIR --world-hash SHA256 [--parent ID]
  view        --store PRIVATE_DIR --campaign ID
  choose      --store PRIVATE_DIR --campaign ID --choice CHOICE_ID
              --action UNIQUE_ACTION_ID --revision CURRENT_REVISION
  export-save --store PRIVATE_DIR --campaign ID --output FILE.bwsave
  import-save --store PRIVATE_DIR --world-hash SHA256 --input FILE.bwsave

No cloud calls. Source scanning does not approve canon or make an RPG.
Never publish your private books, worlds, checkpoints or saves.
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || (args.length == 1 && args.single == '--help')) {
    stdout.write(usage);
    if (args.isEmpty) exitCode = 64;
    return;
  }
  try {
    stdout.writeln(jsonEncode(await const RpgCliClient().execute(args)));
  } on FormatException {
    stderr.writeln(jsonEncode({'status': 'error',
      'code': 'invalid_input'}));
    exitCode = 2;
  } on FileSystemException {
    stderr.writeln(jsonEncode({'status': 'error',
      'code': 'filesystem_error'}));
    exitCode = 2;
  } on StateError {
    stderr.writeln(jsonEncode({'status': 'error',
      'code': 'invalid_state'}));
    exitCode = 2;
  }
}
