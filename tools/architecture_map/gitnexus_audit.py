#!/usr/bin/env python3
"""Emit factual GitNexus audit details without publishing private index databases."""
import argparse
import json
import pathlib
import re
import subprocess

PINNED_SHA = "9e5c11eb4dc8c5fd70cd588baca4d3c12e565dbc"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--worktree", type=pathlib.Path, required=True)
    ap.add_argument("--output", type=pathlib.Path, required=True)
    args = ap.parse_args()
    head = subprocess.check_output(["git", "-C", str(args.worktree), "rev-parse", "HEAD"], text=True).strip()
    if head != PINNED_SHA:
        raise SystemExit(f"Source commit differs: {head}")
    metadata = args.worktree / ".gitnexus" / "gitnexus.json"
    info = json.loads(metadata.read_text(encoding="utf-8")) if metadata.exists() else {}
    fields = ("version","gitSha","commitSha","lastIndexedCommit","stats","languages","incompleteReasons")
    report = dict(tool="GitNexus CLI", provenance="AST and graph analysis performed by actual GitNexus CLI",
                  sourceCommit=PINNED_SHA, status="index_created" if metadata.exists() else "metadata_missing",
                  metadata={x: info.get(x) for x in fields if x in info},
                  observedIndex=metadata.exists())
    for name in ("status", "nodes", "calls"):
        p = pathlib.Path("/tmp") / ("gitnexus-" + name + ".txt")
        report[name+"Excerpt"] = p.read_text(encoding="utf-8",errors="replace")[-4500:] if p.exists() else ""
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

if __name__ == "__main__":
    main()
