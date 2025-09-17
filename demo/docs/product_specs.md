# Product Specifications

- Ingest formats: `.txt`, `.md`, `.markdown`, `.html` (PDF/DOCX optional)
- Chunk size: configurable (default ~1000 words) with overlap
- Embeddings: OpenAI, Local HTTP, Ollama, or Mock for offline demo
- Search: vector similarity, keyword (FTS), or hybrid with tunable weight
- Re-ranking: heuristic, LLM, or cross-encoder via HTTP
- Exports: txt, csv, json; reconstruct to normalized text
