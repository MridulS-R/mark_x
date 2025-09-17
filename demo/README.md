# MarkX Demo

This demo shows how to ingest a small folder of fake docs and run search/chat without any external model calls by using the mock embeddings provider.

Quick start

- Set up Postgres with pgvector and set `DATABASE_URL`.
- From repo root:
  - export EMBEDDINGS_PROVIDER=mock
  - export EMBEDDINGS_DIM=256
  - bundle exec exe/mark_x init
  - bundle exec exe/mark_x ingest --folder demo/docs --csv-row-mode
  - bundle exec exe/mark_x search --query "what is markx?" --mode hybrid --alpha 0.6
  - bundle exec exe/mark_x chat

Optional: use `.markx.yml`

- `cd demo` and copy `.markx.yml`:
  - cp .markx.yml.example .markx.yml
  - bundle exec exe/mark_x init
  - bundle exec exe/mark_x ingest  # uses configured csv_row_mode and filters

Files

- `demo/docs/` contains fake markdown, text, and HTML content.
- `demo/SEARCH_EXAMPLES.txt` includes queries to try.

CSV demo

- We include `demo/docs/people.csv`.
- Try ingesting with row mode and a filter:
  - bundle exec exe/mark_x ingest --folder demo/docs --csv-row-mode --csv-where team=Search
- Try a custom delimiter (if your file uses `;`):
  - bundle exec exe/mark_x ingest --folder demo/docs --csv-row-mode --csv-delimiter ";"
- Limit rows to sample:
  - bundle exec exe/mark_x ingest --folder demo/docs --csv-row-mode --csv-limit 2
- Config-driven (from demo/.markx.yml):
  - cd demo && cp .markx.yml.example .markx.yml
  - bundle exec exe/mark_x ingest --dry-run --json --out preview.json  # counts CSV rows when csv_row_mode is true
  - bundle exec exe/mark_x ingest

Compressed CSV (.csv.gz)

- Create a compressed CSV from the semicolon file:
  - chmod +x scripts/make_demo_gz.sh
  - scripts/make_demo_gz.sh demo/docs/people_semicolon.csv demo/docs/people_semicolon.csv.gz
- Ingest with row mode, delimiter `;`:
  - bundle exec exe/mark_x ingest --folder demo/docs --csv-row-mode --csv-delimiter ";"
