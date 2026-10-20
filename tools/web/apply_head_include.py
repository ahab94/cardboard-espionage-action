#!/usr/bin/env python3
"""Copies tools/web/no_webgl2.html into the Web export preset (html/head_include).
export_presets.cfg values are double-quoted, so the snippet must not contain
double quotes or newlines."""
import os, re
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
src = open(os.path.join(root, "tools/web/no_webgl2.html")).read()
snippet = src[src.index("-->") + 3:].strip()
assert '"' not in snippet and "\n" not in snippet, "snippet must be one line without double quotes"
p = os.path.join(root, "export_presets.cfg")
s = open(p).read()
line = 'html/head_include="' + snippet + '"'
if "html/head_include=" in s:
    s = re.sub(r'^html/head_include=.*$', lambda m: line, s, flags=re.M)
else:
    s = s.replace("[preset.3.options]\n", "[preset.3.options]\n\n" + line + "\n", 1)
open(p, "w").write(s)
print("html/head_include updated (%d chars)" % len(snippet))
