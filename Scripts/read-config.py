#!/usr/bin/env python3
"""Prints the settings from Config/OnePercent.xcconfig, with Config/Local.xcconfig on top.

    python3 Scripts/read-config.py ONEPERCENT_BUNDLE_ID     # one value ("" when it is not set)
    python3 Scripts/read-config.py                          # all of them, one NAME=value per line

Reads the files the way Xcode does, so the scripts and the Mac build see the same values as the
iPhone build: "//" starts a comment, `#include "file"` / `#include? "file"` (optional) pull in
another file, a later line wins, and $(NAME) / ${NAME} are expanded once everything is read.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(ROOT, "Config", "OnePercent.xcconfig")

INCLUDE = re.compile(r'#include(\?)?\s+"([^"]+)"')
SETTING = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)")
REFERENCE = re.compile(r"\$\(([A-Za-z_][A-Za-z0-9_]*)\)|\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


def read(path, raw, optional=False):
    if not os.path.exists(path):
        if optional:
            return
        sys.exit(f"read-config: missing {path}")
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.split("//", 1)[0].strip()
            if not line:
                continue
            include = INCLUDE.match(line)
            if include:
                read(os.path.join(os.path.dirname(path), include.group(2)), raw, optional=bool(include.group(1)))
                continue
            setting = SETTING.match(line)
            if setting:
                raw[setting.group(1)] = setting.group(2).strip()


def expand(name, raw, seen=()):
    if name in seen:
        sys.exit(f"read-config: {name} refers to itself")
    value = raw.get(name, os.environ.get(name, ""))
    return REFERENCE.sub(lambda m: expand(m.group(1) or m.group(2), raw, seen + (name,)), value)


def settings():
    raw = {}
    read(MAIN, raw)
    return {name: expand(name, raw) for name in raw}


if __name__ == "__main__":
    values = settings()
    if len(sys.argv) > 1:
        print(values.get(sys.argv[1], ""))
    else:
        for name in sorted(values):
            print(f"{name}={values[name]}")
