#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Please set DATABASE_URL to a Postgres database (with pgvector)."
  exit 1
fi

export EMBEDDINGS_PROVIDER=${EMBEDDINGS_PROVIDER:-mock}
export EMBEDDINGS_DIM=${EMBEDDINGS_DIM:-256}
export MARKX_PROJECT=${MARKX_PROJECT:-demo_project}

echo "==> init"
bundle exec exe/mark_x init

echo "==> ingest demo/docs (including CSV row-mode)"
bundle exec exe/mark_x ingest --folder demo/docs --csv-row-mode

echo "==> search (hybrid)"
bundle exec exe/mark_x search --query "what is markx?" --mode hybrid --alpha 0.6
bundle exec exe/mark_x search --query "Alice Engineer" --mode hybrid --alpha 0.6

echo "==> reconstruct"
bundle exec exe/mark_x reconstruct demo/docs/company_overview.md --out /tmp/markx_demo_reconstruct.txt

echo "==> extract"
bundle exec exe/mark_x extract --query "list the main features" --out /tmp/markx_demo_extract.json

echo "Done. Outputs: /tmp/markx_demo_reconstruct.txt, /tmp/markx_demo_extract.json"
