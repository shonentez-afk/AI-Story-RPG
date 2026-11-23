#!/usr/bin/env python3
"""Convert verified GitNexus CLI Cypher results to portable, evidence-labeled JSON.

GitNexus uses Tree-sitter (Dart/Python); no lexical call relation is promoted to
AST evidence. Caller *declaration* location is not a call-site proof.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re

SOURCE_SHA = "9e5c11eb4dc8c5fd70cd588baca4d3c12e565dbc"
REPO = "shonentez-afk/AI-Story-RPG"
EXPECTED = ("caller", "caller_file", "caller_line", "callee", "callee_file",
            "callee_line", "confidence")


def parse_cli(raw: str) -> tuple[list[dict[str, str]], int]:
    candidates = list(re.finditer(r'\{\s*"markdown"\s*:', raw))
    if not candidates:
        raise ValueError("No GitNexus markdown output; graph export is not evidence")
    blob, _ = json.JSONDecoder().raw_decode(raw[candidates[-1].start():])
    md = blob.get("markdown", "")
    lines = [line.strip() for line in md.splitlines() if line.strip().startswith("|")]
    if len(lines) < 2:
        raise ValueError("Malformed GitNexus table")
    def parts(line: str) -> list[str]:
        return [val.strip() for val in line.strip().strip("|").split("|")]
    keys = parts(lines[0])
    if not set(EXPECTED).issubset(keys):
        raise ValueError(f"Unexpected GitNexus columns: {keys}")
    result = []
    for row in lines[2:]:
        values = parts(row)
        if len(values) != len(keys):
            continue
        result.append(dict(zip(keys, values)))
    return result, int(blob["row_count"])


def normalize(data: list[dict[str, str]], row_count: int) -> dict:
    nodes: dict[str, dict] = {}
    edges: list[dict] = []
    seen: set[tuple] = set()
    ignored = 0
    def anchor(name: str, path: str, line: str) -> str | None:
        if not name or not path or not re.fullmatch(r"[0-9]+", line):
            return None
        p = pathlib.PurePosixPath(path)
        if p.is_absolute() or ".." in p.parts or not path.endswith((".dart", ".py")):
            return None
        return "gitnexus:" + path + ":" + line + ":" + name
    for item in data:
        a = anchor(item["caller"], item["caller_file"], item["caller_line"])
        b = anchor(item["callee"], item["callee_file"], item["callee_line"])
        try:
            score = float(item["confidence"])
        except ValueError:
            ignored += 1
            continue
        if a is None or b is None or not (0.7 <= score <= 1):
            ignored += 1
            continue
        for nid, role in ((a, "caller"), (b, "callee")):
            p, l, n = (item[role + "_file"], int(item[role + "_line"]), item[role])
            if nid not in nodes:
                nodes[nid] = dict(id=nid, name=n, label=n, type="symbol",
                                  path=p, line=l, confidence="gitnexus_tree_sitter_ast",
                                  description=("GitNexus AST definition in " + p),
                                  url=f"https://github.com/{REPO}/blob/{SOURCE_SHA}/{p}#L{l}")
        evidence=(a,b)
        if evidence in seen:
            continue
        seen.add(evidence)
        src=nodes[a]
        edges.append(dict(source=a, target=b, kind="gitnexus_call",
                          confidence="gitnexus_resolved", score=score,
                          path=src["path"], line=src["line"],
                          url=src["url"], evidenceKind="caller_definition",
                          explanation="GitNexus Tree-sitter/resolution CALLS (score {:.2f}); the link anchors the caller declaration, not the call-site line. No runtime execution is proved.".format(score)))
    return dict(schema="ai_story_gitnexus_calls_v1",sourceCommit=SOURCE_SHA,
                repository=REPO, generator="GitNexus 1.6.12 via CodeRelation CALLS",
                selection="confidence >= 0.7; complete CLI response where available",
                statistics=dict(rowsReported=row_count, rowsParsed=len(data),
                                edges=len(edges), nodes=len(nodes), ignored=ignored,
                                mayBeTruncated=(row_count!=len(data))),
                nodes=list(nodes.values()), edges=edges)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", type=pathlib.Path, required=True)
    ap.add_argument("--output", type=pathlib.Path, required=True)
    args = ap.parse_args()
    data, count=parse_cli(args.input.read_text(encoding="utf-8",errors="replace"))
    result=normalize(data,count)
    if result["statistics"]["mayBeTruncated"]:
        raise SystemExit("GitNexus CLI output was truncated; no full graph should be published")
    if result["statistics"]["edges"] < 100:
        raise SystemExit("Unexpectedly small verified GitNexus call graph")
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
    print(json.dumps(result["statistics"]))


if __name__ == "__main__":
    main()
