#!/usr/bin/env python3
"""Render every manifest program through GL and SDL_GPU and classify the difference.

Usage: sweep.py <oogpu-render> <manifest.tsv> <image dir> <default texture png> [<uniform value>]
<uniform value> (default 0.5) is given to every uniform with no explicit value.
Use 1 as well: int and bool uniforms truncate 0.5 to 0.
Prints one line per distinct program: MATCH, DIFF, GL_REJECTS (no OpenGL
reference) or ERROR, with the difference statistics.
"""
import concurrent.futures as cf, os, re, subprocess, sys

RENDER, MANIFEST, OUTDIR, TEXTURE = sys.argv[1:5]
UNIFORM = sys.argv[5] if len(sys.argv) > 5 else "0.5"
os.makedirs(OUTDIR, exist_ok=True)

seen, jobs = set(), []
for line in open(MANIFEST):
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 4 or (parts[1], parts[2]) in seen:
        continue
    seen.add((parts[1], parts[2]))
    jobs.append(parts)


def run(job):
    label, vs, fs, prefix = job
    out = os.path.join(OUTDIR, re.sub(r"[^\w.-]", "_", label)[:150])
    cmd = [RENDER, "-l", "0.15", "-U", UNIFORM, "-T", TEXTURE]
    if prefix != "-":
        cmd += ["-p", prefix]
    cmd += [vs, fs, out]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return label, "TIMEOUT", ""
    m = re.search(r"mean ([\d.]+)  max (\d+)  differing ([\d.]+)%", r.stdout)
    if m is None:
        err = r.stderr.strip().splitlines()
        kind = "GL_REJECTS" if any("GL compile failed" in e or "GL link failed" in e for e in err) else "ERROR"
        return label, kind, " | ".join(err[-3:])
    mean, mx, diff = float(m.group(1)), int(m.group(2)), float(m.group(3))
    kind = "MATCH" if diff < 0.5 and mean < 0.5 else "DIFF"
    return label, kind, f"mean {mean} max {mx} differing {diff}%"


with cf.ThreadPoolExecutor(6) as ex:
    for label, kind, detail in ex.map(run, jobs):
        print(f"{kind}\t{label}\t{detail}", flush=True)
