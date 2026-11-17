"""Execute the exact owner-approved maintenance scope, never a schedule."""
import json
import os
from pathlib import Path
import sys

from prune import Api, main as prune_main

ORPHAN_TAGS = {
    'test-build-258': '7532667f8497b001a65ee01c108d1e6811b2b158',
    'test-build-260': '180e32995e71e609fe303cad6db927f0420ed239',
}


def eligible(tag, sha, ref, release, comparison):
    return (tag in ORPHAN_TAGS and sha == ORPHAN_TAGS[tag]
            and release is None and isinstance(ref, dict)
            and ref.get('ref') == 'refs/tags/' + tag
            and ref.get('object', {}).get('type') == 'commit'
            and ref['object'].get('sha') == sha
            and comparison.get('status') in ('ahead', 'identical')
            and comparison.get('merge_base_commit', {}).get('sha') == sha)


def prune_orphan_tags():
    api = Api()
    report = {'scope': 'verified_historical_test_tags', 'deleted_tags': [],
              'preserved_tags': [], 'errors': []}
    out = Path('artifacts/maintenance'); out.mkdir(parents=True, exist_ok=True)
    def save():
        (out / 'cleanup-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    try:
        for tag, sha in ORPHAN_TAGS.items():
            ref = api.call('/git/ref/tags/' + tag, missing=True)
            if ref is None:
                report['preserved_tags'].append({'tag': tag, 'reason': 'already absent'})
                continue
            release = api.call('/releases/tags/' + tag, missing=True)
            comparison = api.call('/compare/' + tag + '...main?per_page=1&page=2')
            if not eligible(tag, sha, ref, release, comparison):
                report['preserved_tags'].append({'tag': tag, 'reason': 'changed, released, or unique history'})
                continue
            # Compare exact identity again immediately before deletion.
            again = api.call('/git/ref/tags/' + tag, missing=True)
            if again != ref or api.call('/releases/tags/' + tag, missing=True) is not None:
                report['preserved_tags'].append({'tag': tag, 'reason': 'changed during verification'})
                continue
            api.call('/git/refs/tags/' + tag, 'DELETE', missing=True)
            if api.call('/git/ref/tags/' + tag, missing=True) is not None:
                raise RuntimeError('Deleted tag unexpectedly still exists: ' + tag)
            report['deleted_tags'].append({'tag': tag, 'commit_preserved_in_main': sha})
            save()
    except Exception as err:
        report['errors'].append(str(err))
        raise
    finally:
        save()
        print('PRUNE_TAG_RESULT ' + json.dumps(report), flush=True)
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as stream:
            stream.write('## Historical orphan test tags\n```json\n' + json.dumps(report, indent=2) + '\n```\n')


def main():
    request = json.loads(Path('tools/maintenance/cleanup-request.json').read_text(encoding='utf-8'))
    if request.get('repository') != 'shonentez-afk/AI-Story-RPG':
        raise RuntimeError('Wrong approved repository')
    scope = request.get('scope', 'obsolete_repository_storage')
    if scope == 'obsolete_repository_storage':
        sys.argv = ['prune.py', '--apply']
        prune_main()
    elif scope == 'verified_historical_test_tags' and request.get('expected_tags') == ORPHAN_TAGS:
        prune_orphan_tags()
    else:
        raise RuntimeError('Unknown or changed cleanup authorization scope')


if __name__ == '__main__':
    main()
