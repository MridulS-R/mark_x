#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL not set. Example: postgres://postgres:password@localhost:5433/markx_test"
  exit 1
fi

export EMBEDDINGS_PROVIDER=mock
export EMBEDDINGS_MODEL=mock
export EMBEDDINGS_DIM=${EMBEDDINGS_DIM:-256}
export MARKX_PROJECT=${MARKX_PROJECT:-smoke}

echo "==> init"
bundle exec exe/mark_x init

echo "==> ingest samples"
bundle exec exe/mark_x ingest --folder samples/docs

echo "==> search (vector)"
bundle exec exe/mark_x search --query "hybrid search" --mode vector --download /tmp/markx_search.json

echo "==> search (hybrid)"
bundle exec exe/mark_x search --query "hybrid search" --mode hybrid --alpha 0.5

echo "==> reconstruct"
bundle exec exe/mark_x reconstruct samples/docs/intro.md --out /tmp/markx_rebuild.txt

echo "==> extract"
bundle exec exe/mark_x extract --query "features" --out /tmp/markx_extract.json

echo "OK"

