#!/usr/bin/env python3
"""Read-only, reproducible source inventory for the unified architecture map.

Python definitions are parsed with CPython AST. Dart definitions/calls use a
conservative lexical index (NOT a Dart AST and NOT GitNexus). Uncertain call
matches remain explicitly marked as candidates. Only local, resolvable import
targets are represented as proven code dependencies.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import pathlib
import re
import subprocess
from collections import Counter, defaultdict

CODE_SUFFIXES = {".dart": "dart", ".py": "python", ".js": "javascript",
                 ".jsx": "javascript", ".ts": "typescript", ".tsx": "typescript"}
SKIP_PARTS = {".git", ".dart_tool", "build", "node_modules", "__pycache__", ".gitnexus"}
DART_IMPORT = re.compile(r"^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]")
JS_IMPORT = re.compile(r"^\s*(?:import|export).*?['\"](\.?\.?/[^'\"]+)['\"]")
DART_TYPE = re.compile(
    r"^\s*(?:(?:abstract|final|base|sealed|interface)\s+)*(class|mixin|enum|extension)\s+([A-Za-z_]\w*)\b")
DART_FUNCTION = re.compile(
    r"^\s*(?:(?:static|external|abstract|factory)\s+)*"
    r"(?:Future(?:Or)?(?:<[^;(){}]+>)?|Stream<[^;(){}]+>|"
    r"Iterable<[^;(){}]+>|List<[^;(){}]+>|Map<[^;(){}]+>|"
    r"Set<[^;(){}]+>|[A-Za-z_]\w*(?:<[^;(){}]+>)?|void)\??\s+"
    r"([A-Za-z_]\w*)\s*\(")
DART_CALL = re.compile(r"\b([a-zA-Z_]\w*)\s*\(")
DART_NOT_CALLS = {"if", "for", "while", "switch", "catch", "assert",
                  "return", "throw", "new", "super", "this", "await", "show"}
SHA_RE = re.compile(r"^[a-f0-9]{40}$")
REPO = "shonentez-afk/AI-Story-RPG"


def evidence(sha: str, path: str, line: int = 1) -> str:
    return f"https://github.com/{REPO}/blob/{sha}/{path}#L{line}"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tracked_paths(root: pathlib.Path) -> list[str]:
    try:
        data = subprocess.check_output(["git", "-C", str(root),
                                        "ls-files", "-z"], stderr=subprocess.DEVNULL)
        paths = [x.decode("utf-8") for x in data.split(b"\0") if x]
    except (OSError, subprocess.CalledProcessError):
        paths = [p.relative_to(root).as_posix() for p in root.rglob("*")
                 if p.is_file() and not SKIP_PARTS.intersection(p.parts)]
    return sorted(p for p in paths if not SKIP_PARTS.intersection(pathlib.PurePosixPath(p).parts))


def resolve_import(path: str, target: str, known: set[str]) -> str | None:
    """Resolve only concrete repo-local files; do not invent dependencies."""
    source = pathlib.PurePosixPath(path)
    if target.startswith("package:"):
        rest = target[len("package:"):]
        pkg, sep, inner = rest.partition("/")
        if not sep:
            return None
        candidates = (f"packages/{pkg}/lib/{inner}", f"apps/{pkg}/lib/{inner}")
    elif target.startswith("."):
        candidate = (source.parent / target)
        # pathlib does not normalize '..' in PurePosixPath
        bits = []
        for item in candidate.parts:
            if item == "..":
                if bits:
                    bits.pop()
            elif item != ".":
                bits.append(item)
        candidates = ("/".join(bits),)
    else:
        return None
    for candidate in candidates:
        if candidate in known:
            return candidate
        for ext in (".py", ".js", ".ts", ".tsx", "/__init__.py", "/index.ts", "/index.js"):
            if candidate + ext in known:
                return candidate + ext
    return None


def description_before(lines: list[str], line: int) -> str:
    items = []
    pos = line - 2
    while pos >= 0 and lines[pos].strip().startswith(("///", "##", "# ")):
        txt = re.sub(r"^\s*(?:///|##|#)\s?", "", lines[pos]).strip()
        items.append(txt)
        pos -= 1
    return " ".join(reversed(items))[:450]


def symbols_python(tree: ast.AST, path: str, sha: str) -> list[dict]:
    found = []
    def visit(body, owner=None):
        for obj in body:
            if isinstance(obj, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                kind = "class" if isinstance(obj, ast.ClassDef) else ("method" if owner else "function")
                key = f"symbol:{path}:{obj.lineno}:{obj.name}"
                signature = f"{owner + '.' if owner else ''}{obj.name}"
                found.append(dict(id=key, name=obj.name, label=signature,
                                  type=kind, path=path, line=obj.lineno,
                                  group=group_for(path), confidence="ast_definition",
                                  description=(ast.get_docstring(obj) or "")[:450],
                                  url=evidence(sha, path, obj.lineno)))
                if isinstance(obj, ast.ClassDef):
                    visit(obj.body, obj.name)
    visit(getattr(tree, "body", []))
    return found


def symbols_dart(lines: list[str], path: str, sha: str) -> list[dict]:
    found = []
    for i, text in enumerate(lines, 1):
        typ = DART_TYPE.match(text)
        fun = DART_FUNCTION.match(text) if not typ else None
        if not typ and not fun:
            continue
        kind = typ.group(1) if typ else "function_or_method"
        name = typ.group(2) if typ else fun.group(1)
        if name in DART_NOT_CALLS:
            continue
        found.append(dict(id=f"symbol:{path}:{i}:{name}", name=name, label=name,
                          type=kind, path=path, line=i, group=group_for(path),
                          confidence="lexical_definition",
                          signature=text.strip()[:240],
                          description=description_before(lines, i),
                          url=evidence(sha, path, i)))
    return found


def group_for(path: str) -> str:
    parts = path.split("/")
    if parts[0] in {"packages", "apps"} and len(parts) > 1:
        return "/".join(parts[:2])
    if parts[0] == "tools" and len(parts) > 1:
        return "/".join(parts[:2]) if parts[1] == "rpg_author" else "tools/other"
    return parts[0]


def build(root: pathlib.Path, base_sha: str) -> dict:
    if not SHA_RE.fullmatch(base_sha):
        raise ValueError("A full 40-char source commit SHA is mandatory")
    catalog = tracked_paths(root)
    code = [p for p in catalog if pathlib.PurePosixPath(p).suffix in CODE_SUFFIXES]
    known = set(code)
    node_list = []
    edge_list = []
    inventory = []
    import_refs = []
    texts = {}
    py_ast = {}
    for path in code:
        file_path = root / path
        if not file_path.is_file():
            continue
        raw = file_path.read_bytes()
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
        lines = content.splitlines()
        texts[path] = lines
        lang = CODE_SUFFIXES[pathlib.PurePosixPath(path).suffix]
        node_list.append(dict(id="file:"+path, name=pathlib.PurePosixPath(path).name,
                              label=path, type="file", path=path, line=1,
                              group=group_for(path), confidence="file_inventory",
                              url=evidence(base_sha, path)))
        inventory.append(dict(path=path, size=len(raw), sha256=sha256(raw),
                              lines=len(lines), language=lang))
        if lang == "python":
            try:
                tree = ast.parse(content, filename=path)
                py_ast[path] = tree
                node_list += symbols_python(tree, path, base_sha)
                for imp in ast.walk(tree):
                    if isinstance(imp, ast.Import):
                        for alias in imp.names:
                            target = alias.name.replace(".", "/")
                            for candidate in (target+".py", target+"/__init__.py"):
                                if candidate in known:
                                    import_refs.append((path, candidate, imp.lineno,
                                                        "ast_import", alias.name))
                                    break
                    elif isinstance(imp, ast.ImportFrom) and imp.module:
                        prefix = "." * imp.level + imp.module.replace(".", "/")
                        relative = prefix.replace("/", ".") if imp.level else prefix
                        if not imp.level:
                            for candidate in (prefix+".py", prefix+"/__init__.py"):
                                if candidate in known:
                                    import_refs.append((path, candidate, imp.lineno,
                                                        "ast_import", imp.module))
                                    break
                        else:
                            # Relative imports from adjacent Python files.
                            resolved = resolve_import(path, "."+relative.lstrip("."),
                                                      known)
                            if resolved:
                                import_refs.append((path, resolved, imp.lineno,
                                                    "ast_import", prefix))
            except SyntaxError:
                pass
        elif lang == "dart":
            node_list += symbols_dart(lines, path, base_sha)
            for i, line in enumerate(lines, 1):
                m = DART_IMPORT.match(line)
                if m:
                    resolved = resolve_import(path, m.group(1), known)
                    if resolved:
                        import_refs.append((path, resolved, i, "source_import", m.group(1)))
        else:
            for i, line in enumerate(lines, 1):
                m = JS_IMPORT.match(line)
                if m:
                    resolved = resolve_import(path, m.group(1), known)
                    if resolved:
                        import_refs.append((path, resolved, i, "source_import", m.group(1)))

    node_by_id = {node["id"]: node for node in node_list}
    by_file = defaultdict(list)
    for node in node_list:
        if node["id"].startswith("symbol:"):
            by_file[node["path"]].append(node)
            edge_list.append(dict(source="file:"+node["path"], target=node["id"],
                                  kind="contains", confidence="declaration",
                                  path=node["path"], line=node["line"],
                                  url=node["url"],
                                  explanation="Определение объявлено в исходном файле"))
    for source, target, line, confidence, token in import_refs:
        edge_list.append(dict(source="file:"+source, target="file:"+target,
                              kind="import", confidence=confidence, path=source,
                              line=line, url=evidence(base_sha, source, line),
                              explanation=f"Статический импорт или экспорт: {token}"))
    # Conservative same-file call candidates. A matching name in a call expression
    # does NOT establish the receiver type or runtime execution.
    for path, lines in texts.items():
        local = defaultdict(list)
        for node in by_file[path]:
            local[node["name"]].append(node)
        if path in py_ast:
            for obj in ast.walk(py_ast[path]):
                if not isinstance(obj, ast.Call):
                    continue
                fun = obj.func
                name = fun.id if isinstance(fun, ast.Name) else (
                    fun.attr if isinstance(fun, ast.Attribute) else None)
                if not name or len(local[name]) != 1:
                    continue
                target = local[name][0]
                line = obj.lineno
                owner = max((n for n in by_file[path] if n["line"] < line),
                            key=lambda n: n["line"], default=None)
                if not owner or owner["id"] == target["id"]:
                    continue
                edge_list.append(dict(source=owner["id"], target=target["id"],
                                      kind="call_candidate", confidence="ast_call_candidate",
                                      path=path, line=line,
                                      url=evidence(base_sha, path, line),
                                      explanation="AST фиксирует вызов по имени; динамическое разрешение не доказано"))
        elif path.endswith(".dart"):
            for line, txt in enumerate(lines, 1):
                if txt.lstrip().startswith(("//", "/*", "*", "import ", "export ")):
                    continue
                owner = max((n for n in by_file[path] if n["line"] < line),
                            key=lambda n: n["line"], default=None)
                if owner is None:
                    continue
                for call in DART_CALL.finditer(txt):
                    name = call.group(1)
                    if name in DART_NOT_CALLS or len(local[name]) != 1:
                        continue
                    target = local[name][0]
                    if target["id"] == owner["id"] or target["line"] == line:
                        continue
                    edge_list.append(dict(source=owner["id"], target=target["id"],
                                          kind="call_candidate", confidence="lexical_call_candidate",
                                          path=path, line=line, url=evidence(base_sha, path, line),
                                          explanation="Лексическое совпадение имени вызова; тип получателя и исполнение не подтверждены"))
    # Deduplicate exact evidence, not aggregate differing source lines.
    seen = set()
    edges = []
    for edge in edge_list:
        key = (edge["source"], edge["target"], edge["kind"], edge["line"], edge["path"])
        if key not in seen and edge["source"] in node_by_id and edge["target"] in node_by_id:
            edges.append(edge)
            seen.add(key)
    files_overview = []
    for path in catalog:
        f = root / path
        if f.is_file():
            files_overview.append(dict(path=path, bytes=f.stat().st_size))
    return dict(schema="ai_story_unified_map_v1", sourceCommit=base_sha,
                repository=REPO, analyzer="python_ast_and_dart_lexical_fallback_not_gitnexus",
                claimPolicy={
                    "source_import": "Существующий импорт; не доказывает выполнение",
                    "ast_import": "Импорт прочитан Python AST; не доказывает выполнение",
                    "ast_definition": "Python AST подтвердил объявление",
                    "lexical_definition": "Лексическое объявление Dart, не полноценный AST",
                    "ast_call_candidate": "Вызов в Python AST; получатель/достижимость не установлены",
                    "lexical_call_candidate": "Предполагаемый вызов Dart; не доказана диспетчеризация",
                },
                statistics={"trackedFiles":len(files_overview), "analyzedCodeFiles":len(inventory),
                            "nodes":len(node_list), "edges":len(edges),
                            "relationKinds":dict(Counter(e["kind"] for e in edges))},
                fileCatalog=files_overview, codeInventory=inventory,
                nodes=node_list, edges=edges)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--base-sha", required=True)
    opts = parser.parse_args()
    graph = build(opts.root.resolve(), opts.base_sha)
    opts.out.parent.mkdir(parents=True, exist_ok=True)
    opts.out.write_text(json.dumps(graph, ensure_ascii=False, indent=1,
                                  sort_keys=True)+"\n", encoding="utf-8")
    print(json.dumps(graph["statistics"], ensure_ascii=False))


if __name__ == "__main__":
    main()
