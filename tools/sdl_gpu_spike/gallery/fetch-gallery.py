#!/usr/bin/env python3
"""Download the OXZs the OXP shader gallery uses.

Usage: fetch-gallery.py <dir>
Fetches the expansion catalog, then each OXZ in OXZS (about 60 MB in all)
into <dir>, skipping any already there. Run the gallery with
game-snapshot.py <oolite> <out dir> --gallery <dir>.
"""
import json, os, subprocess, sys, tempfile, urllib.request

OXZS = [
    "oolite.oxp.Griff.Prototype_Boa", "oolite.oxp.Griff.Cobra_MKIII_Alt", "oolite.oxp.Griff.Moray",
    "oolite.oxp.Griff.Anaconda", "oolite.oxp.Griff.Boa_MkII", "oolite.oxp.Griff.Python", "oolite.oxp.Griff.Viper",
    "oolite.oxp.Griff.Constrictor", "oolite.oxp.Griff.Asp", "oolite.oxp.Griff.Gecko",
    "oolite.oxp.Griff_alloys_and_wreckage", "oolite.oxp.Griff.Griff_shipset_decals",
    "oolite.oxp.CaptSolo.Cobra_Mk3-XT", "oolite.oxp.captsolo.cougar_st1.5", "oolite.oxp.Stormrider.Stormbrewer",
]
CATALOG_URL = "https://addons.oolite.space/api/1.0/overview"


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "oolite-shader-gallery"})
    return urllib.request.urlopen(request, timeout=300).read()


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    # The catalog is an OpenStep property list, which plutil (macOS) converts.
    with tempfile.NamedTemporaryFile(suffix=".plist") as plist:
        plist.write(get(CATALOG_URL))
        plist.flush()
        converted = subprocess.run(["plutil", "-convert", "json", "-o", "-", plist.name], check=True, capture_output=True)
    catalog = {entry["identifier"]: entry for entry in json.loads(converted.stdout)}
    for identifier in OXZS:
        dest = os.path.join(out, identifier + ".oxz")
        if os.path.exists(dest):
            continue
        data = get(catalog[identifier]["download_url"])
        with open(dest, "wb") as f:
            f.write(data)
        print(identifier, len(data))


if __name__ == "__main__":
    main()
