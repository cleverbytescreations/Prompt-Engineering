# CLAUDE.md

## Project Summary
Restricted ICA legal knowledge and collaboration platform.
Core goals:
- repository
- expert Q&A
- curated news
- AI-assisted search

Principles:
- AI is assistive, not authoritative
- moderation is core
- human validation is required for legal interpretation

## Tech Stack
Frontend: Next.js, React, TypeScript, MUI, Tailwind
Backend: FastAPI, SQLAlchemy, Redis, Celery
Data: PostgreSQL, Elasticsearch/OpenSearch, vector DB, object storage

## Skill Routing
Use `architecture-deep-dive` for architecture, workflows, scalability, RAG, storage, and search design.
Use `frontend-guidelines` for all work inside `frontend/`, including UI, forms, mocks, API contracts, and React patterns.
Use `backend-patterns` for FastAPI backend design, services, repositories, async processing, and integration patterns.

## Key Rules
- Work inside the correct module boundary
- Do not put business logic in UI
- Use React Query for frontend API access
- Use clean backend layering: API -> Service -> Repository
- Do not overload PostgreSQL with search
- Do not store all data in vector DB
- Prefer async/event-driven processing for heavy tasks
- `NEXT_PUBLIC_DEMO_MODE=true` enables MSW mocks

## Code navigation policy

For TypeScript and Python:
- Prefer the LSP tool for symbol lookup, definitions, references, implementations, hover/type info, call hierarchy, workspace/file symbols, and diagnostics.
- Do not use Grep as the first choice for code understanding in .ts, .tsx, .py files.
- Use Grep only as a fallback when LSP is unavailable or when doing broad text-only searches such as config strings, comments, TODOs, or non-symbol literals.