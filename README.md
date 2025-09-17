# mark_x

Semantic search + RAG CLI for local projects, backed by PostgreSQL + pgvector.

Commands:

- `mark_x init` — initialize per-project DB schema.
- `mark_x ingest` — ingest from a folder or a database source.
  - Folder: `--folder PATH`
  - Supported file formats: .txt, .md, .markdown, .html, .csv, .csv.gz (PDF/DOCX optional if gems installed)
  - CSV options: `--csv-row-mode` (ingest each row as a separate document), `--csv-delimiter ","`, `--csv-headers true|false|auto`, `--csv-where key=value [key=value ...]`, `--csv-limit N`
  - Database (read-only): `--db-url URL [--db-table T --db-id-column ID --db-text-column TEXT --db-where SQL | --db-query SQL] [--db-format text|markdown|html] [--db-alias NAME]`
  - Config sources: add `sources:` to `.markx.yml` and run `mark_x ingest`.
  - Pick named sources: `--source NAME1,NAME2` (comma-separated); filter by type: `--source-type folder|db`
  - Dry-run preview: `--dry-run` to print counts without writing; add `--json` for machine-readable output.
  - Save preview to file: add `--out preview.json` (works with or without `--json`).
  - Or define `sources:` in `.markx.yml` and run `mark_x ingest`
- `mark_x sync --folder PATH` — re-index only changed files.
- `mark_x prune --folder PATH` — remove entries for deleted files.
- `mark_x search --query "..." [--download out.{txt,csv,json}]` — search.
  - Modes: `--mode keyword|vector|hybrid` (or legacy `--hybrid`).
  - Options: `--alpha` hybrid weight for vector (0..1), `--rank rank|rank_cd` for FTS ranking.
  - Re-ranking: `--re-rank` with `--reranker heuristic|llm|crossencoder` and optional `--reranker-endpoint`.
- `mark_x reconstruct FILE --out FILE.txt` — rebuild normalized file text.
- `mark_x extract --query "..." --out results.json` — structured export (basic stub).
- `mark_x chat` — interactive chat with RAG (LLM-backed). `--stream` streams tokens.
 - `mark_x watch --folder PATH` — polling watcher that runs sync+prune.

Quick start:

1. Set `DATABASE_URL` for your PostgreSQL and ensure `CREATE EXTENSION vector;` is allowed.
2. `cp .markx.example.yml .markx.yml` and adjust settings (project/schema name etc.).
3. `bundle exec mark_x init`
4. `bundle exec mark_x ingest --folder ./docs`
5. `bundle exec mark_x search --query "what is in the docs?"`

Embeddings providers: `openai`, `local` (HTTP), `ollama`. Configure via `.markx.yml` or env (`EMBEDDINGS_PROVIDER`, `EMBEDDINGS_MODEL`, provider-specific env like `OPENAI_API_KEY`).

LLM providers for chat/re-ranking: `openai`, `local`, `ollama`. Configure with `llm_provider`, `llm_model` or env `LLM_PROVIDER`, `LLM_MODEL` (plus provider creds, e.g., `OPENAI_API_KEY`). Streaming supported for OpenAI and Ollama.

Notes:

- Chunking is word-based with configurable size and overlap.
- Keyword search uses Postgres full-text with `ts_rank`/`ts_rank_cd`.
- Hybrid search blends vector similarity and FTS rank with configurable weight.
- Re-ranking available via heuristic, LLM, or cross-encoder HTTP endpoint.
- PDF/DOCX extraction requires `pdf-reader` / `docx` gems.
- This repo includes DB migrations for pgvector with IVFFLAT index.
