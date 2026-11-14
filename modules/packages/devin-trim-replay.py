#!/usr/bin/env python3
"""Stop Devin's ACP transcript from OOM-ing its single renderer process.

Devin renders every ACP session in one renderer process. Unbounded replay is
what killed it with SIGTRAP (exit 133) on 2026-11-05: opening a long-lived
session replays it from the cloud in one burst (1738 `replay_apply` chunks,
250 MiB -> the 2.5 GiB V8 cap in ~4 s). Almost all of that payload is
`oldText`/`newText` diff bodies in `tool_call` updates. Upstream exposes 44
`devin.acp.*` settings and none bound replay or transcript size
(MAX_CACHED_SESSIONS is a file count, MAX_CACHE_BYTES bounds the disk cache).

The fix trims oversized strings as payloads enter the renderer: once in the
main process before the copy is shipped over the wire, and again in the renderer
that installs or ingests the transcript (the app ships three byte-identical
copies of that renderer bundle and any of them can serve the active shell).

The trim marker keeps the diff item (path, type, line counts, `_meta`) so the
timeline still renders; only the bodies that blow up the heap are dropped.
Unlike editing `acp-messages/*.db`, this survives: the app re-fetches sessions
from the cloud and overwrites the local cache on every launch.
"""

import base64
import hashlib
import json
import os
import sys

MAX_CHARS = 8192


TRIM_BODY = (
    "(function __devinTrimReplay(v){"
    'if(typeof v==="string")return v.length>MAXCHARS?'
    '"[omitted by devin-replay-trim: "+v.length+" chars]":v;'
    # Mutate in place: callers track requests by object identity
    # (`_replayEvents`, `_activeReplays`), so returning fresh copies would
    # silently detach replay accounting from every trimmed chunk.
    "if(Array.isArray(v)){for(let i=0;i<v.length;i++)v[i]=__devinTrimReplay(v[i]);return v}"
    "if(v&&typeof v==='object'){for(let k in v)v[k]=__devinTrimReplay(v[k]);return v}"
    "return v})"
)

# (label, anchor, replacement) — each anchor must occur exactly once.
PATCHES = {
    # --- the live main-process ACP service ------------------------------------
    # Verbatim behaviour of sessions.desktop.main.js, but `workbench.desktop.main.js`
    # is the copy Electron actually loads (it is the one that emits the
    # `replay_apply` ops we measured), and it is minified with different locals.
    "workbench.desktop.main.js": [
        # Every replay chunk is buffered here and tagged replay_apply via
        # `_replayEvents`, which this very array fills, so trimming the array
        # before the loop bounds both the payload and its replay bookkeeping.
        (
            "event-buffer dispatch",
            "dispatch:e=>{if(this._flushMessageCache(),this._store.isDisposed)return;",
            "dispatch:e=>{if(e=" + TRIM_BODY + "(e),"
            "this._flushMessageCache(),this._store.isDisposed)return;",
        ),
        # Single inbound ACP entry; covers the message cache and fs paths that
        # never reach the event buffer.
        (
            "handleClientRequest",
            "handleClientRequest(e,t,o){",
            "handleClientRequest(e,t,o){t=" + TRIM_BODY + "(t);",
        ),
    ],
    # Same file before the shell split, kept because the `native` layout still
    # loads this bundle on some builds.
    "sessions.desktop.main.js": [
        (
            "event-buffer dispatch (native shell)",
            "dispatch:e=>{if(this._flushMessageCache(),this._store.isDisposed)return;",
            "dispatch:e=>{if(e=" + TRIM_BODY + "(e),"
            "this._flushMessageCache(),this._store.isDisposed)return;",
        ),
        (
            "handleClientRequest (native shell)",
            "handleClientRequest(e,t,n){",
            "handleClientRequest(e,t,n){t=" + TRIM_BODY + "(t);",
        ),
        (
            "restoreSessionMessagesFromCache",
            "let A=[...s.payload.messages],k=EC(o,u);",
            "let A=" + TRIM_BODY + "(s.payload.messages),k=EC(o,u);",
        ),
    ],
    # --- renderer: three byte-identical copies, any of which can be the shell --
    "windsurf-chat-client/index.js": [
        (
            "acp event ingest",
            "let g=el_(e,s),_=(r=g).events??(r.events=[]);",
            "let g=el_(e,s),_=(r=g).events??(r.events=[]);l=" + TRIM_BODY + "(l);",
        ),
        (
            "renderer hydrate",
            "let a=[...n.payload.messages],l=el_(e,r);",
            "let a=" + TRIM_BODY + "(n.payload.messages),l=el_(e,r);",
        ),
    ],
    "node_modules/@exa/chat-client/index.js": [
        (
            "acp event ingest (react shell)",
            "let g=el_(e,s),_=(r=g).events??(r.events=[]);",
            "let g=el_(e,s),_=(r=g).events??(r.events=[]);l=" + TRIM_BODY + "(l);",
        ),
        (
            "hydrate (react shell)",
            "let a=[...n.payload.messages],l=el_(e,r);",
            "let a=" + TRIM_BODY + "(n.payload.messages),l=el_(e,r);",
        ),
    ],
}

def patch_file(path, patches):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        src = fh.read()

    # Verify every anchor before mutating anything, so a partial patch is
    # impossible and the build fails loudly when upstream moves a funnel.
    for label, anchor, _ in patches:
        hits = src.count(anchor)
        if hits != 1:
            sys.stderr.write(
                "devin-trim-replay: anchor for %s matched %d times in %s (expected 1)\n"
                "  anchor: %s\n"
                "  Upstream changed this funnel; re-derive the patch from the new bundle.\n"
                % (label, hits, path, anchor)
            )
            return False

    for label, anchor, replacement in patches:
        src = src.replace(anchor, replacement.replace("MAXCHARS", str(MAX_CHARS)))
        print("devin-trim-replay: %s: patched %s" % (path.rsplit("/", 1)[-1], label))

    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(src)
    return True


def reseal_checksums(root) -> bool:
    """Rewrite product.json's integrity hashes for the files we patched.

    The app verifies `product.json.checksums` at startup and shows
    "Your <app> installation appears to be corrupt. Please reinstall." plus a
    reconnect loop when the base64 SHA-256 of any listed file changes. Our
    build-time patch rewrites three of the twelve listed files, so the digests
    must be recomputed or the window never opens.
    """
    import base64
    import hashlib
    import json

    product = "%s/product.json" % root
    with open(product, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    sealed = data.get("checksums") or {}
    if not sealed:
        return True

    changed = 0
    for rel, old in sealed.items():
        target = "%s/out/%s" % (root, rel)
        if not os.path.exists(target):
            sys.stderr.write(
                "devin-trim-replay: product.json lists %s but it is missing\n" % rel
            )
            return False
        with open(target, "rb") as fh:
            digest = base64.b64encode(hashlib.sha256(fh.read()).digest()).decode()
        new = digest.rstrip("=")
        if new != old.rstrip("="):
            sealed[rel] = new
            changed += 1

    if changed:
        with open(product, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    print("devin-trim-replay: resealed %d product.json checksum(s)" % changed)
    return True


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write(
            "usage: devin-trim-replay.py <resources/app dir>\n"
            "  patches the main-process ACP service and both renderer bundles\n"
        )
        return 2

    root = sys.argv[1].rstrip("/")
    substeps = {
        "out/vs/workbench/workbench.desktop.main.js": PATCHES["workbench.desktop.main.js"],
        "out/vs/sessions/sessions.desktop.main.js": PATCHES["sessions.desktop.main.js"],
        "out/vs/workbench/windsurf-chat-client/index.js": PATCHES["windsurf-chat-client/index.js"],
        "node_modules/@exa/chat-client/index.js": PATCHES["node_modules/@exa/chat-client/index.js"],
    }

    for rel, patches in substeps.items():
        if not patch_file("%s/%s" % (root, rel), patches):
            return 1

    # Must happen after every patch, or the app refuses to open a window.
    if not reseal_checksums(root):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
