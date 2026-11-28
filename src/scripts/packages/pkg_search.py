#!/usr/bin/env python3
"""Search packages and print them as JSON, ordered by priority:
   1) CachyOS repos  2) original Arch repos  3) AUR
Usage: pkg_search.py <query> [limit_per_group]
"""
import json, re, subprocess, sys, urllib.parse, urllib.request

GROUPS = ["cachyos", "official", "aur"]

def group_of(repo):
    if repo == "aur":
        return "aur"
    return "cachyos" if "cachyos" in repo.lower() else "official"

def relevance(name, q):
    n, q = name.lower(), q.lower()
    if n == q: return 0
    if n.startswith(q): return 1
    if q in n: return 2
    return 3

def pacman_search(q):
    try:
        out = subprocess.run(["pacman", "-Ss", "--", q], capture_output=True,
                             text=True, timeout=15).stdout
    except Exception:
        return []
    res, head = [], re.compile(r"^(\S+?)/(\S+)\s+(\S+)(.*)$")
    lines = out.splitlines()
    i = 0
    while i < len(lines):
        m = head.match(lines[i])
        if m:
            desc = lines[i + 1].strip() if i + 1 < len(lines) else ""
            res.append({"repo": m[1], "name": m[2], "version": m[3],
                        "desc": desc, "installed": "[installed" in m[4],
                        "group": group_of(m[1])})
            i += 2
        else:
            i += 1
    return res

def aur_search(q, native):
    url = "https://aur.archlinux.org/rpc/v5/search/%s?by=name-desc" % urllib.parse.quote(q)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "taurus-pkg"})
        data = json.load(urllib.request.urlopen(req, timeout=8))
    except Exception:
        return [], True
    res = []
    for r in data.get("results", []):
        if r["Name"] in native:
            continue  # already in the repos, which take priority
        res.append({"repo": "aur", "name": r["Name"], "version": r.get("Version", ""),
                    "desc": r.get("Description") or "", "installed": False,
                    "group": "aur", "votes": r.get("NumVotes", 0),
                    "popularity": r.get("Popularity", 0),
                    "outOfDate": bool(r.get("OutOfDate"))})
    return res, False

def installed_set():
    try:
        out = subprocess.run(["pacman", "-Qq"], capture_output=True, text=True, timeout=10).stdout
        return set(out.split())
    except Exception:
        return set()

def main():
    q = sys.argv[1].strip() if len(sys.argv) > 1 else ""
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 25
    if len(q) < 2:
        print(json.dumps({"results": [], "aurFailed": False})); return
    seen, native = set(), []
    for p in pacman_search(q):  # pacman.conf order: the first one is the one that would be installed
        if p["name"] not in seen:
            seen.add(p["name"]); native.append(p)
    names = {p["name"] for p in native}
    aur, failed = aur_search(q, names)
    inst = installed_set()
    for p in aur:
        p["installed"] = p["name"] in inst
    out = []
    for g in GROUPS:
        items = [p for p in native + aur if p["group"] == g]
        items.sort(key=lambda p: (relevance(p["name"], q), -p.get("popularity", 0), p["name"]))
        out += items[:limit]
    print(json.dumps({"results": out, "aurFailed": failed}))

main()
