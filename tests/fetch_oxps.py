"""
Downloads the OXPs listed in test-oxps.txt into a cache directory and
verifies their checksums.

Usage: fetch_oxps.py <cache directory> [--list FILE] [--lenient]

Prints the number of OXPs available. A download that fails (the host is down,
say) is skipped with a warning; a file whose SHA-256 does not match is an
error, since that means the list or the download is wrong (with --lenient,
for lists whose OXPs may be updated in place, it is a warning too).

In GitHub Actions, a skipped download is also reported as a warning on the
run, and when every OXP is available the step's output <list name>-complete
(test-oxps-complete for test-oxps.txt) is set to true, so that the workflow
only caches a complete set.
"""

import argparse
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


def entries(path=LIST):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                checksum, identifier, url = line.split()
                yield checksum, identifier, url


def warn(message):
    print(message)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::warning title=Test OXPs::{message.removeprefix('[?] ')}")


def fetch(cache, path=LIST, lenient=False):
    """Returns the number of OXPs available in cache, and the number of checksum errors."""
    os.makedirs(cache, exist_ok=True)
    available = 0
    errors = 0
    for checksum, identifier, url in entries(path):
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
            message = f"{identifier}: checksum {actual} does not match {os.path.basename(path)} ({checksum})."
            os.remove(partial)
            if lenient:
                warn(f"[?] {message} Testing without it.")
            else:
                print(f"[!] {message}")
                errors += 1
            continue
        os.replace(partial, path)
        print(f"[*] Downloaded {identifier}")
        available += 1
    return available, errors


def main():
    parser = argparse.ArgumentParser(description="Download and verify the OXPs in a list")
    parser.add_argument("cache", help="directory to download the OXPs into")
    parser.add_argument("--list", default=LIST, help="the list of OXPs (default: test-oxps.txt)")
    parser.add_argument("--lenient", action="store_true", help="skip an OXP whose checksum does not match, with a warning")
    args = parser.parse_args()
    available, errors = fetch(args.cache, args.list, args.lenient)
    total = sum(1 for _ in entries(args.list))
    print(f"[*] {available} of {total} OXP(s) from {os.path.basename(args.list)} available in {args.cache}")
    if available == total and os.environ.get("GITHUB_OUTPUT"):
        name = os.path.splitext(os.path.basename(args.list))[0]
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write(f"{name}-complete=true\n")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
