#!/usr/bin/env python3
"""Replace AssetRipper's exported package stubs with Unity's installed packages."""

from __future__ import annotations

import re
import sys
from pathlib import Path


PACKAGE_DLLS = {
    "Unity.RenderPipeline.Universal.ShaderLibrary.dll",
    "Unity.RenderPipelines.Core.Runtime.dll",
    "Unity.RenderPipelines.Core.ShaderLibrary.dll",
    "Unity.RenderPipelines.ShaderGraph.ShaderGraphLibrary.dll",
    "Unity.RenderPipelines.Universal.Runtime.dll",
    "Unity.RenderPipelines.Universal.Shaders.dll",
    "Unity.TextMeshPro.dll",
    "UnityEngine.UI.dll",
}
PACKAGE_PREFIXES = (
    "com.unity.render-pipelines.core",
    "com.unity.render-pipelines.universal",
    "com.unity.textmeshpro",
    "com.unity.ugui",
)
GUID_RE = re.compile(r"^guid:\s*([0-9a-fA-F]{32})\s*$", re.MULTILINE)
NAMESPACE_RE = re.compile(r"\bnamespace\s+([\w.]+)")
TYPE_RE = re.compile(r"\b(?:class|struct|interface|enum)\s+(\w+)")
SHADER_RE = re.compile(r"\bShader\s+\"([^\"]+)\"")
GUID_REF_RE = re.compile(r"guid:\s*([0-9a-fA-F]{32})")
TEXT_ASSET_SUFFIXES = {".asset", ".prefab", ".unity", ".mat", ".renderTexture", ".shadervariants"}


def read_guid(meta: Path) -> str | None:
    try:
        match = GUID_RE.search(meta.read_text(errors="ignore"))
        return match.group(1).lower() if match else None
    except OSError:
        return None


def script_identity(source: Path) -> set[tuple[str, str]]:
    try:
        text = source.read_text(errors="ignore")
    except OSError:
        return set()
    namespace = NAMESPACE_RE.search(text)
    ns = namespace.group(1) if namespace else ""
    return {(ns, match.group(1)) for match in TYPE_RE.finditer(text)}


def package_roots(package_cache: Path, builtin_packages: Path) -> list[Path]:
    roots: list[Path] = []
    for base in (package_cache, builtin_packages):
        if not base.is_dir():
            continue
        for child in base.iterdir():
            if child.is_dir() and any(child.name.startswith(prefix) for prefix in PACKAGE_PREFIXES):
                roots.append(child)
    return roots


def source_guid_index(roots: list[Path]) -> dict[tuple[str, str], str]:
    index: dict[tuple[str, str], str] = {}
    for root in roots:
        for meta in root.rglob("*.cs.meta"):
            guid = read_guid(meta)
            source = meta.with_suffix("")
            if not guid or not source.is_file():
                continue
            for identity in script_identity(source):
                index.setdefault(identity, guid)
    return index


def build_script_guid_map(project: Path, target_index: dict[tuple[str, str], str]) -> dict[str, str]:
    recovered = project / "RecoveredSourceArchive"
    mapping: dict[str, str] = {}
    if not recovered.is_dir():
        return mapping
    for meta in recovered.rglob("*.cs.meta"):
        old_guid = read_guid(meta)
        source = meta.with_suffix("")
        if not old_guid or not source.is_file():
            continue
        targets = {target_index[identity] for identity in script_identity(source) if identity in target_index}
        if len(targets) == 1:
            new_guid = next(iter(targets))
            if old_guid != new_guid:
                mapping[old_guid] = new_guid
    return mapping


def shader_guid_index(roots: list[Path]) -> dict[str, str]:
    index: dict[str, str] = {}
    for root in roots:
        for shader in root.rglob("*.shader"):
            try:
                match = SHADER_RE.search(shader.read_text(errors="ignore"))
            except OSError:
                continue
            guid = read_guid(shader.with_suffix(shader.suffix + ".meta"))
            if match and guid:
                index.setdefault(match.group(1), guid)
    return index


def build_shader_guid_map(project: Path, target_index: dict[str, str]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for shader in (project / "Assets").rglob("*.shader"):
        try:
            match = SHADER_RE.search(shader.read_text(errors="ignore"))
        except OSError:
            continue
        old_guid = read_guid(shader.with_suffix(shader.suffix + ".meta"))
        if match and old_guid and match.group(1) in target_index:
            new_guid = target_index[match.group(1)]
            if old_guid != new_guid:
                mapping[old_guid] = new_guid
    return mapping


def replace_references(project: Path, mapping: dict[str, str]) -> int:
    if not mapping:
        return 0
    changed = 0
    for path in (project / "Assets").rglob("*"):
        if not path.is_file() or path.suffix not in TEXT_ASSET_SUFFIXES:
            continue
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        updated = GUID_REF_RE.sub(lambda m: f"guid: {mapping.get(m.group(1).lower(), m.group(1))}", text)
        if updated != text:
            path.write_text(updated)
            changed += 1
    return changed


def prepare(project: Path) -> None:
    plugins = project / "Assets" / "Plugins"
    removed: list[str] = []
    if plugins.is_dir():
        for dll_name in sorted(PACKAGE_DLLS):
            dll = plugins / dll_name
            if dll.exists():
                dll.unlink()
                meta = dll.with_suffix(dll.suffix + ".meta")
                if meta.exists():
                    meta.unlink()
                removed.append(dll_name.removesuffix(".dll"))
    print(f"prepared; removed DLLs: {removed}")


def remap(project: Path, package_cache: Path, builtin_packages: Path) -> None:
    roots = package_roots(package_cache, builtin_packages)
    target_scripts = source_guid_index(roots)
    script_mapping = build_script_guid_map(project, target_scripts)
    target_shaders = shader_guid_index(roots)
    shader_mapping = build_shader_guid_map(project, target_shaders)
    changed = replace_references(project, script_mapping | shader_mapping)
    print(
        "package roots found: "
        f"{[root.name.split('@', 1)[0] for root in roots]} | "
        f"script classes: {len(target_scripts)} | shaders: {len(target_shaders)}"
    )
    print(f"dummy shaders replaced by package shaders: {len(shader_mapping)}")
    print(f"script refs remapped: {len(script_mapping)} | shader refs remapped: {len(shader_mapping)}")
    print(f"serialized assets updated: {changed}")


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in {"prepare", "remap"}:
        print("usage: ci_package_remap.py prepare PROJECT | remap PROJECT PACKAGE_CACHE BUILTIN_PACKAGES", file=sys.stderr)
        return 2
    mode = argv[1]
    project = Path(argv[2]).resolve()
    if not project.is_dir():
        print(f"project directory not found: {project}", file=sys.stderr)
        return 2
    if mode == "prepare":
        prepare(project)
    else:
        if len(argv) != 5:
            print("remap requires PACKAGE_CACHE and BUILTIN_PACKAGES", file=sys.stderr)
            return 2
        remap(project, Path(argv[3]), Path(argv[4]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
