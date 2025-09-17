#!/usr/bin/env bash
set -euo pipefail

src=${1:-demo/docs/people_semicolon.csv}
dst=${2:-demo/docs/people_semicolon.csv.gz}

if [[ ! -f "$src" ]]; then
  echo "Source file not found: $src" >&2
  exit 1
fi

gzip -c "$src" > "$dst"
echo "Wrote $dst"

