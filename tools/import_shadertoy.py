#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Convert a Shadertoy JSON export into a shader-cube face directory.

usage: import_shadertoy.py EXPORT.json OUT_DIR [--resolution W [H]] [--crop]

Writes common.glsl, bufa..bufd.glsl, vola.glsl, image.glsl and channels.cfg.
"""
import json
import os
import sys

PASS_FILE = {"buffer": None, "volume": None, "image": "image", "common": "common"}


def pass_name(rp):
    t = rp.get("type")
    if t == "image":
        return "image"
    if t == "common":
        return "common"
    letter = rp.get("name", "")[-1:].lower()
    if t == "buffer" and letter in "abcd":
        return "buf" + letter
    if t == "volume" and letter == "a":
        return "vol" + letter
    return None


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    src, out = args[0], args[1]
    extra = args[2:]

    data = json.load(open(src, encoding="utf-8"))
    if isinstance(data, list):
        data = data[0]
    data = data.get("Shader", data)
    info = data.get("info", {})

    # output id -> pass name (bufa, vola, ...)
    ids = {}
    for rp in data["renderpass"]:
        n = pass_name(rp)
        for o in rp.get("outputs", []):
            if n and n not in ("image", "common"):
                ids[o["id"]] = n

    os.makedirs(out, exist_ok=True)
    cfg = [
        "# imported from %s: \"%s\" by %s" % (os.path.basename(src), info.get("name", "?").strip(),
                                            info.get("username", "?")),
        "# https://www.shadertoy.com/view/%s" % info.get("id", "?"),
    ]
    i = 0
    while i < len(extra):
        if extra[i] == "--resolution":
            w = extra[i + 1]
            h = extra[i + 2] if i + 2 < len(extra) and not extra[i + 2].startswith("--") else w
            cfg.append("resolution %s %s" % (w, h))
            i += 3 if h is not w else 2
        elif extra[i] == "--crop":
            cfg.append("crop")
            i += 1
        else:
            sys.exit("unknown option " + extra[i])

    for rp in data["renderpass"]:
        n = pass_name(rp)
        if not n:
            print("warning: unsupported pass %r (%s) skipped" % (rp.get("name"), rp.get("type")))
            continue
        with open(os.path.join(out, n + ".glsl"), "w", encoding="utf-8") as f:
            f.write(rp["code"])
        for inp in rp.get("inputs", []):
            t = inp.get("type") or inp.get("ctype")
            s = inp.get("sampler", {})
            if t in ("buffer", "volume"):
                source = ids.get(inp["id"])
                if not source:
                    print("warning: %s ch%d refers to unknown output %s" % (n, inp["channel"], inp["id"]))
                    continue
            elif t == "keyboard":
                source = "keyboard"
            else:
                print("warning: %s ch%d input type %r not supported, using noise" % (n, inp["channel"], t))
                source = "noise"
            cfg.append("%-5s %d %-8s %s %s" % (n, inp["channel"], source,
                                               s.get("filter", "linear"), s.get("wrap", "clamp")))
    with open(os.path.join(out, "channels.cfg"), "w", encoding="utf-8") as f:
        f.write("\n".join(cfg) + "\n")
    print("%s -> %s  (%s)" % (src, out, info.get("name", "?").strip()))


if __name__ == "__main__":
    main()
