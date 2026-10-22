"""
Downloads the OXPs listed in test-oxps.txt into a cache directory and
verifies their checksums.

Usage: fetch_oxps.py <cache directory>

Prints the number of OXPs available. A download that fails (the host is down,
say) is skipped with a warning; a file whose SHA-256 does not match is an
error, since that means the list or the download is wrong.

In GitHub Actions, a skipped download is also reported as a warning on the
run, and when every OXP is available the step's output test-oxps-complete is
set to true, so that the workflow only caches a complete set.
"""

import hashlib
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.path.join(HERE, "test-oxps.txt")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def entries():
    with open(LIST, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                checksum, identifier, url = line.split()
                yield checksum, identifier, url


def warn(message):
    print(message)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::warning title=Test OXPs::{message.removeprefix('[?] ')}")


def fetch(cache):
    os.makedirs(cache, exist_ok=True)
    available = 0
    errors = 0
    for checksum, identifier, url in entries():
        path = os.path.join(cache, identifier + ".oxz")
        if os.path.isfile(path) and sha256(path) == checksum:
            available += 1
            continue
        partial = path + ".part"
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "Oolite-tests/1.0"})
            with urllib.request.urlopen(request, timeout=120) as response, open(partial, "wb") as out:
                out.write(response.read())
        except OSError as e:
            warn(f"[?] Could not download {identifier} ({e}); testing without it.")
            if os.path.exists(partial):
                os.remove(partial)
            continue
        actual = sha256(partial)
        if actual != checksum:
            print(f"[!] {identifier}: checksum {actual} does not match test-oxps.txt ({checksum}).")
            os.remove(partial)
            errors += 1
            continue
        os.replace(partial, path)
        print(f"[*] Downloaded {identifier}")
        available += 1
    return available, errors


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    available, errors = fetch(sys.argv[1])
    total = sum(1 for _ in entries())
    print(f"[*] {available} of {total} test OXP(s) available in {sys.argv[1]}")
    if available == total and os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write("test-oxps-complete=true\n")
    sys.exit(1 if errors else 0)
