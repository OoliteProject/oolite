#!/usr/bin/env python3
"""Pull Shaders/ and Config/*.plist entries out of every catalog OXZ using HTTP range requests.

Usage: fetch.py <corpus dir>
Downloads the expansion catalog into <corpus dir>/catalog.plist and the files
into <corpus dir>/oxz/<identifier>/. Only the needed byte ranges are fetched,
rather than the whole catalog (about 7.5 GB of OXZs).
"""
import json, os, re, struct, subprocess, sys, zlib, urllib.request, concurrent.futures as cf

CORPUS = os.path.abspath(sys.argv[1])
OUT = os.path.join(CORPUS, "oxz")
CATALOG_URL = "https://addons.oolite.space/api/1.0/overview"
WANT = re.compile(r"(^|/)(shaders/|config/(shipdata|shipdata-overrides|planetinfo|descriptions)?[^/]*\.plist$)", re.I)


def rng(url, start, end):
    req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}", "User-Agent": "oolite-shader-survey"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
        if r.status == 200:  # server ignored range
            return data[start:end + 1], data
        return data, None


def fetch(item):
    url, ident, size = item["download_url"], item["identifier"], int(item.get("file_size") or 0)
    dest = os.path.join(OUT, re.sub(r"[^\w.-]", "_", ident))
    if os.path.exists(os.path.join(dest, ".done")):
        return ident, "cached"
    try:
        tail_len = min(size, 65536 + 22) if size else 65558
        tail, whole = rng(url, max(0, size - tail_len), size - 1)
        if whole is not None:
            size = len(whole)
            tail = whole[-tail_len:]
        eocd = tail.rfind(b"PK\x05\x06")
        if eocd < 0:
            return ident, "no eocd"
        _, _, _, _, count, cd_size, cd_off, _ = struct.unpack("<IHHHHIIH", tail[eocd:eocd + 22])
        cd = whole[cd_off:cd_off + cd_size] if whole else rng(url, cd_off, cd_off + cd_size - 1)[0]
        p, n = 0, 0
        while p < len(cd) and cd[p:p + 4] == b"PK\x01\x02":
            (method, csize, nlen, xlen, clen, loff) = (
                struct.unpack("<H", cd[p + 10:p + 12])[0], struct.unpack("<I", cd[p + 20:p + 24])[0],
                *struct.unpack("<HHH", cd[p + 28:p + 34]), struct.unpack("<I", cd[p + 42:p + 46])[0])
            name = cd[p + 46:p + 46 + nlen].decode("utf-8", "replace")
            p += 46 + nlen + xlen + clen
            if name.endswith("/") or not WANT.search(name) or csize > 4_000_000:
                continue
            blob = whole[loff:loff + 30 + 1024 + csize] if whole else rng(url, loff, loff + 30 + 1024 + csize)[0]
            fnl, exl = struct.unpack("<HH", blob[26:30])
            raw = blob[30 + fnl + exl:30 + fnl + exl + csize]
            data = zlib.decompress(raw, -15) if method == 8 else raw
            path = os.path.join(dest, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").write(data)
            n += 1
        os.makedirs(dest, exist_ok=True)
        open(os.path.join(dest, ".done"), "w").write(url)
        return ident, f"{n} files"
    except Exception as e:  # noqa: BLE001
        return ident, f"error {e}"


if __name__ == "__main__":
    os.makedirs(CORPUS, exist_ok=True)
    plist = os.path.join(CORPUS, "catalog.plist")
    # The server refuses urllib's default user agent.
    req = urllib.request.Request(CATALOG_URL, headers={"User-Agent": "oolite-shader-survey"})
    with urllib.request.urlopen(req, timeout=60) as r:
        open(plist, "wb").write(r.read())
    # The catalog is an OpenStep property list.
    if sys.platform == "darwin":
        cat = json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", plist], check=True, capture_output=True).stdout)
    else:
        sys.exit("converting the OpenStep catalog needs plutil (macOS)")
    with cf.ThreadPoolExecutor(12) as ex:
        for ident, status in ex.map(fetch, cat):
            if not status.endswith(" 0 files") and status != "cached":
                print(ident, status, flush=True)
