"""User-requested, repository-scoped cleanup. Default is a read-only plan."""
import argparse
import collections
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = 'shonentez-afk/AI-Story-RPG'
BRANCH = 'feature/p0-bookwide-gameplay-readiness-20261107'
ARTIFACTS = {'AI-Story-RPG-Android-debug', 'AI-Story-RPG-Windows-portable',
             'AI-Story-RPG-BookWorld-demo', 'AI-Story-RPG-Grimm-Frog-Prince-FB2'}
PINNED = {42415776969, 42415777040, 42409183805, 42409183795, 42142194592}
TAG = re.compile(r'^test-build-[0-9]+$')
DELETE = re.compile(r'^/(?:actions/(?:runs|artifacts)/[0-9]+|releases/[0-9]+|git/refs/tags/test-build-[0-9]+)$')


def newest(rows):
    return sorted(rows, key=lambda r: (r.get('created_at') or '', r['id']), reverse=True)


def plan(runs, artifacts, releases, branches, own_id):
    """Keep current evidence before selecting any irreversible deletion."""
    runs = newest(runs)
    by_run = {r['id']: r for r in runs}
    safe_releases = [r for r in releases if TAG.fullmatch(r['tag_name'])
        and not r.get('draft') and not r.get('immutable')
        and r.get('prerelease') and r.get('author', {}).get('login') == 'github-actions[bot]'
        and {'AI-Story-RPG-Android-debug.apk', 'AI-Story-RPG-Windows-portable.zip', 'SHA256SUMS.txt'}
            <= {a['name'] for a in r.get('assets', []) if a.get('state') == 'uploaded' and a.get('size', 0) > 0}]
    safe_releases.sort(key=lambda r: int(r['tag_name'].rsplit('-', 1)[1]), reverse=True)
    kept_releases = safe_releases[:3]
    release_delete = safe_releases[3:]
    release_pins = set()
    for release in releases:
        if release not in release_delete:
            release_pins.update(int(i) for i in re.findall(r'/actions/runs/(\d+)', release.get('body') or ''))
    hard_keep = PINNED | release_pins | {own_id}
    keep = hard_keep | {r['id'] for r in runs[:15]}
    keep.update(r['id'] for r in runs if r['status'] != 'completed')
    latest, greens = collections.Counter(), collections.Counter()
    for r in runs:
        key = (r.get('head_branch'), r.get('workflow_id', r.get('name')))
        if key[0] in branches:
            latest[key] += 1
            if latest[key] <= 2:
                keep.add(r['id'])
            if r.get('conclusion') == 'success':
                greens[key] += 1
                if greens[key] <= 2:
                    keep.add(r['id'])
    # Keep the latest green external-author evidence even if its branch closed.
    for r in [r for r in runs if r.get('name') == 'External RPG author tests'
              and r.get('conclusion') == 'success'][:2]:
        keep.add(r['id'])
    kept_artifacts = set()
    counts = collections.Counter()
    for a in newest(artifacts):
        rid = a.get('workflow_run', {}).get('id')
        run = by_run.get(rid)
        if a['name'] not in ARTIFACTS or rid in hard_keep or run is None or run['status'] != 'completed':
            kept_artifacts.add(a['id'])
            if rid:
                keep.add(rid)
        if a['name'] in ARTIFACTS and not a.get('expired') and run and run.get('conclusion') == 'success':
            key = (a['name'], run.get('head_branch'))
            counts[key] += 1
            if run.get('head_branch') in branches and counts[key] <= 2:
                kept_artifacts.add(a['id'])
                keep.add(rid)
    run_delete = [r for r in reversed(runs) if r['id'] not in keep and r['status'] == 'completed']
    gone_runs = {r['id'] for r in run_delete}
    artifact_delete = [a for a in artifacts if a['id'] not in kept_artifacts
        and a['name'] in ARTIFACTS and a.get('workflow_run', {}).get('id') not in gone_runs]
    return {'runs': run_delete, 'artifacts': artifact_delete, 'releases': release_delete,
            'kept_run_ids': sorted(keep), 'kept_artifact_ids': sorted(kept_artifacts),
            'kept_test_releases': [r['tag_name'] for r in kept_releases],
            'implicit_artifacts': [a for a in artifacts if a.get('workflow_run', {}).get('id') in gone_runs]}


class Api:
    def __init__(self):
        if os.environ.get('GITHUB_REPOSITORY') != REPO:
            raise RuntimeError('This operation is authorized for one repository only')
        self.base = 'https://api.github.com/repos/' + REPO
        self.headers = {'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                        'Accept': 'application/vnd.github+json',
                        'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'AI-Story-RPG-maintenance'}

    def call(self, path, method='GET', missing=False):
        if method == 'DELETE' and not DELETE.fullmatch(path):
            raise RuntimeError('Delete endpoint not allowed')
        for attempt in range(4):
            try:
                request = urllib.request.Request(self.base + path, headers=self.headers, method=method)
                with urllib.request.urlopen(request, timeout=40) as response:
                    raw = response.read()
                    return json.loads(raw) if raw else None
            except urllib.error.HTTPError as err:
                if missing and err.code == 404:
                    return None
                # Never repeatedly retry a permission error.
                throttled = err.code == 429 or (err.code == 403 and err.headers.get('Retry-After'))
                if attempt < 3 and (throttled or err.code in (502, 503, 504)):
                    time.sleep(min(120, max(5, int(err.headers.get('Retry-After', '15')))))
                    continue
                raise RuntimeError(f'GitHub {method} {path}: HTTP {err.code}') from None
        raise RuntimeError('Unreachable')

    def pages(self, path, key=None):
        rows = []
        for page in range(1, 61):
            result = self.call(path + ('&' if '?' in path else '?') + f'per_page=100&page={page}')
            batch = result[key] if key else result
            rows.extend(batch)
            if len(batch) < 100:
                return rows
        raise RuntimeError('Pagination exceeded safety bound; no incomplete plan may be applied')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    api = Api()
    own_id = int(os.environ['GITHUB_RUN_ID'])
    meta = api.call('')
    pulls = api.pages('/pulls?state=open')
    branches = {meta['default_branch'], BRANCH}
    branches.update(p['head']['ref'] for p in pulls if p['head']['repo'] and p['head']['repo']['full_name'] == REPO)
    runs = api.pages('/actions/runs', 'workflow_runs')
    artifacts = api.pages('/actions/artifacts', 'artifacts')
    releases = api.pages('/releases')
    selected = plan(runs, artifacts, releases, branches, own_id)
    if len(selected['runs']) > 1600 or len(selected['releases']) > 300:
        raise RuntimeError('Unexpected deletion volume; nothing was deleted')
    report = {'repository': REPO, 'apply': args.apply, 'protected_branches': sorted(branches),
              'before': {'runs': len(runs), 'artifacts': len(artifacts), 'releases': len(releases)},
              'kept_test_releases': selected['kept_test_releases'], 'kept_run_ids': selected['kept_run_ids'],
              'plan': {k: [x['id'] for x in selected[k]] for k in ('runs', 'artifacts', 'releases')},
              'deleted': {'runs': [], 'artifacts': [], 'releases': [], 'tags': []}, 'skipped': [], 'errors': []}
    out = Path('artifacts/maintenance'); out.mkdir(parents=True, exist_ok=True)
    def save():
        (out / 'cleanup-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    save()
    print('PRUNE_PLAN ' + json.dumps({k: len(v) for k, v in report['plan'].items()}), flush=True)
    if not args.apply:
        return
    try:
        for r in selected['releases']:
            # Never remove a release whose assets or immutability changed.
            current = api.call(f"/releases/{r['id']}", missing=True)
            if not current:
                continue
            if current['tag_name'] != r['tag_name'] or current.get('immutable') or current.get('updated_at') != r.get('updated_at'):
                report['skipped'].append(f"changed release {r['id']}"); continue
            ref_path = '/git/refs/tags/' + r['tag_name']
            ref = api.call('/git/ref/tags/' + r['tag_name'], missing=True)
            # Tag must point to code still reachable from a protected branch.
            reachable = False
            if ref:
                for branch in (meta['default_branch'], BRANCH):
                    cmp = api.call('/compare/' + urllib.parse.quote(r['tag_name'], safe='') + '...'
                                   + urllib.parse.quote(branch, safe=''))
                    if cmp.get('status') in ('ahead', 'identical'):
                        reachable = True; break
            api.call(f"/releases/{r['id']}", 'DELETE', missing=True)
            report['deleted']['releases'].append(r['id'])
            if ref and reachable:
                current_ref = api.call('/git/ref/tags/' + r['tag_name'], missing=True)
                if current_ref and current_ref['object'] == ref['object']:
                    api.call(ref_path, 'DELETE', missing=True)
                    report['deleted']['tags'].append(r['tag_name'])
            else:
                report['skipped'].append('preserved unique/missing tag ' + r['tag_name'])
            save()
        for a in selected['artifacts']:
            api.call(f"/actions/artifacts/{a['id']}", 'DELETE', missing=True)
            report['deleted']['artifacts'].append(a['id']); save()
        for r in selected['runs']:
            latest = api.call(f"/actions/runs/{r['id']}", missing=True)
            if latest is None or latest['status'] != 'completed' or latest.get('run_attempt') != r.get('run_attempt'):
                report['skipped'].append(f"changed or missing run {r['id']}"); continue
            api.call(f"/actions/runs/{r['id']}", 'DELETE', missing=True)
            report['deleted']['runs'].append(r['id']); save()
            if len(report['deleted']['runs']) % 50 == 0:
                print('RUNS_REMOVED', len(report['deleted']['runs']), flush=True)
            time.sleep(0.25)
    except Exception as err:
        report['errors'].append(str(err)); save()
        raise
    finally:
        implicit = [a for a in selected['implicit_artifacts']
                    if a['workflow_run']['id'] in set(report['deleted']['runs'])]
        gone_artifacts = [a for a in artifacts if a['id'] in set(report['deleted']['artifacts'])] + implicit
        report['removed_artifact_count'] = len(gone_artifacts)
        report['removed_artifact_bytes'] = sum(a.get('size_in_bytes', 0) for a in gone_artifacts)
        report['removed_release_asset_bytes'] = sum(sum(a.get('size', 0) for a in r.get('assets', []))
            for r in selected['releases'] if r['id'] in report['deleted']['releases'])
        save()
        summary = {k: len(v) for k, v in report['deleted'].items()}
        summary.update({k: report[k] for k in ('removed_artifact_count', 'removed_artifact_bytes',
                                             'removed_release_asset_bytes', 'kept_test_releases', 'errors')})
        print('PRUNE_RESULT ' + json.dumps(summary), flush=True)
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as dest:
            dest.write('## User-requested repository cleanup\n```json\n' + json.dumps(summary, indent=2) + '\n```\n')


if __name__ == '__main__':
    main()
