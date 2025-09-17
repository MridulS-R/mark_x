# Quick Tutorial

1. Set `DATABASE_URL` to your Postgres.
2. Run `bundle exec exe/mark_x init`.
3. Ingest: `bundle exec exe/mark_x ingest --folder demo/docs`.
4. Search: `bundle exec exe/mark_x search --query "main features" --mode hybrid --alpha 0.5`.
5. Chat: `bundle exec exe/mark_x chat` and ask: "what is markx?".
