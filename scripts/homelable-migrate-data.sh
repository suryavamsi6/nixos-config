#!/usr/bin/env bash
# Prepare an online SQLite copy for operator inspection; not the cutover.
set -euo pipefail
umask 077
instance=backend
dest=/var/lib/incus/homelable
if incus config device show "$instance" | grep -q '^data:'; then
  echo "A data device already exists; refusing migration" >&2
  exit 1
fi
if [ -e "$dest/homelab.db" ]; then
  echo "A database already exists at $dest; refusing to overwrite" >&2
  exit 1
fi
if ! incus list '^backend$' --format csv -c s | grep -qx RUNNING; then
  echo "backend must be running to retrieve its database" >&2
  exit 1
fi
work=$(mktemp -d /var/lib/homelable-migration.XXXXXXXX)
remote=/tmp/homelable-migrate-$(basename "$work").db
# The SQLite online backup API is consistent even while the app is running.
incus exec "$instance" -- python3 -c '
import sqlite3, sys
src=sqlite3.connect("file:/app/data/homelab.db?mode=ro", uri=True)
dst=sqlite3.connect(sys.argv[1])
with dst: src.backup(dst)
assert dst.execute("pragma integrity_check").fetchone()[0] == "ok"
dst.close(); src.close()
' "$remote"
incus file pull "$instance$remote" "$work/homelab.db"
test -s "$work/homelab.db"
echo "Consistent initial copy saved in $work/homelab.db"
echo "Do not attach it yet: writes after this copy require a quiesced final migration."
