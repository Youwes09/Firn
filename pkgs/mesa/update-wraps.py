#!/usr/bin/env python3
# Lists the Rust crates a Mesa tree's meson wraps download, for wraps.json.
# Adapted from nixpkgs' pkgs/development/libraries/mesa/update-wraps.py,
# reading the crate's name from its URL: wraps are named <crate>-<major>-rs.
#
# Usage: update-wraps.py <mesa source tree>

import base64
import binascii
import configparser
import json
import pathlib
import sys
import urllib.parse


def to_sri(hash: str):
    raw = binascii.unhexlify(hash)
    return "sha256-" + base64.b64encode(raw).decode()


def main(tree: str):
    result = []
    for file in sorted((pathlib.Path(tree) / "subprojects").glob("*.wrap")):
        parser = configparser.ConfigParser()
        parser.read(file)
        if "wrap-file" not in parser.sections():
            continue

        url = parser.get("wrap-file", "source_url")
        if "crates.io" not in url:
            continue

        # .../crates/<name>/<version>/download
        path = urllib.parse.urlparse(url).path.split("/")
        name, version = path[path.index("crates") + 1 : path.index("download")]
        assert parser.get("wrap-file", "source_filename") == f"{name}-{version}.tar.gz"
        result.append(
            {
                "pname": name,
                "version": version,
                "hash": to_sri(parser.get("wrap-file", "source_hash")),
            }
        )

    here = pathlib.Path(__file__).parent
    with (here / "wraps.json").open("w") as fd:
        json.dump(result, fd, indent=4)
        fd.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
