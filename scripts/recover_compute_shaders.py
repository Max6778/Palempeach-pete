#!/usr/bin/env python3
"""Recover Unity .compute sources from AssetRipper's serialized DXBC assets."""
from __future__ import annotations
import argparse, collections, hashlib, itertools, re, subprocess, tempfile
from pathlib import Path

KSTART = re.compile(r"^    - serializedVersion: 3\s*$", re.M)
VSTART = re.compile(r"^      - serializedVersion: 2\s*$", re.M)
CODE = re.compile(r"^        code: ([0-9a-fA-F]+)\s*$", re.M)
NAME = re.compile(r"^      name: (.+?)\s*$", re.M)
VIDX = re.compile(r"^      - (.*?): (\d+)\s*$", re.M)
IDENT = re.compile(r"^[A-Za-z_]\w*$")

def sections(text, marker):
    hits = list(marker.finditer(text))
    return [text[h.start():hits[i+1].start() if i+1 < len(hits) else len(text)] for i,h in enumerate(hits)]

def parse_indices(section):
    m = re.search(r"^      variantIndices:\s*$", section, re.M)
    if not m: return {0:frozenset()}
    tail = section[m.end():]
    end = re.search(r"^      (?:globalKeywords|localKeywords|dynamicKeywords):", tail, re.M)
    if end: tail = tail[:end.start()]
    values = {int(i):frozenset(k.split()) for k,i in VIDX.findall(tail)}
    return values or {0:frozenset()}

def parse_kernels(text, path):
    renderers = [int(x) for x in re.findall(r"^    targetRenderer: (\d+)\s*$", text, re.M)]
    if not renderers or any(x != 2 for x in renderers):
        raise ValueError(f"{path.name}: expected Direct3D 11 programs, got renderer ids {renderers}")
    out = []
    for section in sections(text, KSTART):
        m = NAME.search(section)
        if not m: continue
        name = m.group(1)
        if not IDENT.fullmatch(name): raise ValueError(f"{path.name}: invalid kernel {name!r}")
        programs = []
        for variant in sections(section, VSTART):
            c = CODE.search(variant)
            if c:
                data = bytes.fromhex(c.group(1))
                if not data.startswith(b"DXBC"): raise ValueError(f"{path.name}/{name}: non-DXBC program")
                programs.append(data)
        if not programs: raise ValueError(f"{path.name}/{name}: no compiled program")
        indices = parse_indices(section)
        if max(indices, default=0) >= len(programs): raise ValueError(f"{path.name}/{name}: variant map overflow")
        unique = {}
        for i,data in enumerate(programs):
            digest = hashlib.sha256(data).hexdigest()
            unique.setdefault(digest,{"code":data,"indices":[]})["indices"].append(indices.get(i,frozenset()))
        out.append({"name":name,"variants":list(unique.values())})
    if not out: raise ValueError(f"{path.name}: no kernels found")
    return out

def partitions(items):
    groups=[]
    def walk(i):
        if i == len(items):
            yield tuple(tuple(g) for g in groups); return
        for g in groups:
            g.append(items[i]); yield from walk(i+1); g.pop()
        groups.append([items[i]]); yield from walk(i+1); groups.pop()
    yield from walk(0)

def keyword_groups(kernels):
    combos={c for k in kernels for v in k['variants'] for c in v['indices']}
    words=tuple(sorted(set().union(*combos) if combos else set()))
    if not words: return []
    if len(words)>10: return [(w,) for w in words]
    best=None
    for candidate in partitions(words):
        expanded={frozenset(x for x in choice if x is not None)
                  for choice in itertools.product(*[(None,*g) for g in candidate])}
        if expanded==combos and (best is None or len(candidate)<len(best)): best=candidate
    return list(best) if best else [(w,) for w in words]

def condition(combo, groups):
    terms=[]
    for group in groups:
        active=combo.intersection(group)
        terms += [f"defined({next(iter(active))})"] if active else [f"!defined({w})" for w in group]
    return " && ".join(terms) if terms else "1"

def decompile(tool, data, cache):
    digest=hashlib.sha256(data).hexdigest()
    if digest in cache: return cache[digest]
    with tempfile.NamedTemporaryFile(suffix='.dxbc') as src:
        src.write(data); src.flush()
        p=subprocess.run([str(tool),src.name,'--emit','hlsl'],capture_output=True,text=True)
    output=p.stdout
    if p.returncode or '// not decompiled:' in output:
        raise RuntimeError(f"DXBC decompilation failed {digest[:12]}: {(p.stderr or output)[:900]}")
    output=re.sub(r"(?m)^// ===== shader #\d+ =====\s*$",'',output).strip()
    if not re.search(r"(?m)^void\s+main\s*\(",output):
        raise RuntimeError(f"no compute entry point in decompiled program {digest[:12]}")
    cache[digest]=output
    return output

def make_source(kernels, groups, tool, cache):
    lines=["// Recovered from the game's Direct3D 11 compute programs."]
    lines += [f"#pragma multi_compile _ {' '.join(g)}" for g in groups]
    lines.append('')
    for i,k in enumerate(kernels):
        name,define=k['name'],f'FT_ANDROID_KERNEL_{i}'
        lines.append(f'#pragma kernel {name} {define}')
        variants=[]
        for v in k['variants']:
            body=decompile(tool,v['code'],cache)
            body,n=re.subn(r"(?m)^void\s+main\s*\(",f"void {name}(",body,count=1)
            if n!=1: raise RuntimeError(f"{name}: couldn't rename entry point")
            variants.append((v['indices'],body))
        lines.append(f'#if defined({define})')
        bybody=collections.defaultdict(set)
        for combos,body in variants: bybody[body].update(combos)
        if len(bybody)==1 or not groups:
            lines.append(variants[0][1])
        else:
            fallback=variants[0][1]; branches=[]
            for body,combos in bybody.items():
                if frozenset() in combos: fallback=body
                else:
                    conds=[condition(c,groups) for c in sorted(combos,key=lambda x:sorted(x))]
                    branches.append((' || '.join(f'({c})' for c in conds),body))
            for j,(cond,body) in enumerate(branches):
                lines.append(('#if ' if j==0 else '#elif ')+cond); lines.append(body)
            if branches: lines += ['#else',fallback,'#endif']
            else: lines.append(fallback)
        lines += ['#endif','']
    return '\n'.join(lines).rstrip()+'\n'

def compute_meta(old_meta):
    m=re.search(r"^guid: ([0-9a-f]{32})\s*$",old_meta.read_text(),re.M)
    if not m: raise ValueError(f"no GUID in {old_meta}")
    return (f"fileFormatVersion: 2\nguid: {m.group(1)}\nComputeShaderImporter:\n"
            "  externalObjects: {}\n  preprocessorOverride: 0\n  userData: \n"
            "  assetBundleName: \n  assetBundleVariant: \n")

def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('asset_dir',type=Path); p.add_argument('d3dasm',type=Path)
    a=p.parse_args()
    if not a.d3dasm.is_file(): p.error(f"d3dasm executable not found: {a.d3dasm}")
    files=sorted(a.asset_dir.glob('*.asset'))
    if not files: raise SystemExit(f"no serialized compute shader assets in {a.asset_dir}")
    cache={}; replacements=[]; manifest=[]; total=0
    for asset in files:
        kernels=parse_kernels(asset.read_text(),asset)
        src=make_source(kernels,keyword_groups(kernels),a.d3dasm,cache)
        oldmeta=Path(str(asset)+'.meta'); newasset=asset.with_suffix('.compute'); newmeta=Path(str(newasset)+'.meta')
        replacements.append((asset,oldmeta,newasset,newmeta,src,compute_meta(oldmeta)))
        manifest.append(f"Assets/ComputeShader/{newasset.name}|"+','.join(k['name'] for k in kernels))
        total+=len(kernels); print(f"recovered {asset.name}: {len(kernels)} kernels")
    # Keep the export untouched unless all programs were decompiled first.
    for old,oldmeta,new,newmeta,src,meta in replacements:
        new.write_text(src); newmeta.write_text(meta); old.unlink(); oldmeta.unlink(missing_ok=True)
    (a.asset_dir/'android-compute-kernels.txt').write_text('\n'.join(manifest)+'\n')
    print(f"converted {len(replacements)} assets, {total} kernels, {len(cache)} unique DXBC programs")

if __name__=='__main__': main()
