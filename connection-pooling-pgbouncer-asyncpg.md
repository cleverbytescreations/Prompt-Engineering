# Connection Pooling Design — PgBouncer + asyncpg + SQLAlchemy

> **Purpose:** Skill/knowledge input for AI tools (Claude, Codex, etc.) working in this
> repository. This documents a non-obvious, production-affecting rule about how the
> backend must configure its async database engine. Treat the **Rules** section as
> binding for any change to `backend/app/core/db.py` or anything that constructs a
> SQLAlchemy async engine.

---

## TL;DR (the rule)

This backend connects to PostgreSQL **through PgBouncer in `transaction` pooling mode**
(`docker-compose.yml` → `pgbouncer`, `POOL_MODE: transaction`). The app uses
`postgresql+asyncpg`. In this exact combination, **every** SQLAlchemy async engine
**must** be created with these three `connect_args`:

```python
connect_args = {
    "statement_cache_size": 0,                                    # asyncpg's own cache OFF
    "prepared_statement_cache_size": 0,                           # SQLAlchemy dialect cache OFF
    "prepared_statement_name_func": lambda: f"__asyncpg_{uuid4()}__",  # UNIQUE names — the actual fix
}
```

All three are **DBAPI connect arguments** → they go in `connect_args`, **never** as
top-level `create_async_engine(...)` keyword arguments.

---

## The bug this prevents

### Symptom (runtime error)

```
sqlalchemy.exc.ProgrammingError:
  (sqlalchemy.dialects.postgresql.asyncpg.ProgrammingError)
  <class 'asyncpg.exceptions.DuplicatePreparedStatementError'>:
  prepared statement "__asyncpg_stmt_6__" already exists

HINT:
NOTE: pgbouncer with pool_mode set to "transaction" or "statement" does not
support prepared statements properly. ... you can set statement_cache_size to 0
when creating the asyncpg connection object.
```

The error surfaces intermittently under concurrency (often first seen on a trivial
endpoint like `/health/live`), not deterministically on startup.

### Why it happens (root cause)

1. SQLAlchemy's asyncpg dialect issues `connection.prepare(sql, name=...)` for **every**
   statement — even `SELECT 1`.
2. The dialect's **default** statement-name function returns `None`
   (`AsyncAdapt_asyncpg_connection._default_name_func`).
3. With `name=None`, **asyncpg auto-generates a sequential name** per connection:
   `__asyncpg_stmt_1__`, `__asyncpg_stmt_2__`, … The counter **restarts at 1 for every
   new asyncpg connection.**
4. PgBouncer in `transaction` mode **multiplexes** many client/asyncpg connections onto a
   smaller set of shared PostgreSQL server backends. Two different asyncpg connections
   each generate `__asyncpg_stmt_6__` and both get routed to the **same** server backend
   → the second `PREPARE` collides → `DuplicatePreparedStatementError`.

### The critical misconception

> "Setting `statement_cache_size=0` fixes it."

**It does not.** `statement_cache_size=0` only disables asyncpg's *caching/reuse* of
prepared statements. The dialect **still prepares each statement with an auto-generated
sequential name** (step 2–3 above), so the collision still happens. This was verified
empirically against the live stack:

| `connect_args` | 750 ops through PgBouncer (txn mode) | `DuplicatePreparedStatementError` |
|---|---|---|
| `statement_cache_size=0` + `prepared_statement_cache_size=0` (no name func) | 750 | **56** |
| same **+ `prepared_statement_name_func`** (uuid) | 750 | **0** |

The **only** parameter that fixes the error is `prepared_statement_name_func`, which gives
every prepared statement a globally-unique name so names never collide across pooled
backends.

---

## Rules (binding for this repo)

1. **Any** `create_async_engine(...)` targeting `postgresql+asyncpg` MUST pass all three
   `connect_args` above. There is one shared helper for this —
   `app.core.db._asyncpg_pgbouncer_connect_args()`. Reuse it; do not hand-roll a subset.
2. `prepared_statement_cache_size` and `prepared_statement_name_func` are **DBAPI
   (connect) arguments**, consumed by the dialect's `AsyncAdapt_asyncpg_dbapi.connect()`
   via `kw.pop(...)`. They belong in `connect_args`. Passing `prepared_statement_cache_size`
   as a top-level `create_async_engine()` kwarg raises:
   `TypeError: Invalid argument(s) 'prepared_statement_cache_size' sent to create_engine()`.
   (`statement_cache_size` is a real `asyncpg.connect()` param and also lives in `connect_args`.)
3. The rule applies to **all** engines: the FastAPI web engine **and** the Celery-worker
   engine (`WorkerSessionLocal`). Both connect through PgBouncer in this deployment.
4. **SQLite is exempt.** The `connect_args` are gated on `"asyncpg" in DATABASE_URL`. The
   test suite runs on `sqlite+aiosqlite` and must not receive these args.
5. **Migrations bypass PgBouncer on purpose.** Alembic connects **directly to Postgres
   (`postgres:5432`)**, not PgBouncer, because transaction-mode pooling does not handle
   some DDL reliably (see `docker-compose.yml` → `backend-migrate`). Do not "simplify"
   migrations to route through PgBouncer.
6. Do **not** "fix" this by switching the deployment off PgBouncer or by enabling session
   pooling without an explicit architecture decision — PgBouncer transaction mode is the
   intended pooler topology here.

---

## Canonical implementation (`backend/app/core/db.py`)

```python
from uuid import uuid4

def _asyncpg_pgbouncer_connect_args() -> dict:
    """asyncpg connection args required for PgBouncer transaction-pooling mode.

    All three are consumed as DBAPI (connect) arguments by SQLAlchemy's asyncpg
    dialect — none are top-level create_async_engine() kwargs:
    - statement_cache_size=0 disables asyncpg's own prepared-statement cache;
    - prepared_statement_cache_size=0 disables SQLAlchemy's dialect-level cache;
    - prepared_statement_name_func gives every prepared statement a unique name so
      reused pooled connections never collide on names like __asyncpg_stmt_6__.
    """
    return {
        "statement_cache_size": 0,
        "prepared_statement_cache_size": 0,
        "prepared_statement_name_func": lambda: f"__asyncpg_{uuid4()}__",
    }

# Web engine
def _build_engine() -> AsyncEngine:
    connect_args: dict = {}
    if "asyncpg" in settings.DATABASE_URL:
        connect_args = _asyncpg_pgbouncer_connect_args()
    engine_kwargs: dict = {"pool_pre_ping": True, "connect_args": connect_args, "echo": settings.DEBUG}
    if settings.DATABASE_URL.endswith(":memory:"):
        engine_kwargs["poolclass"] = StaticPool
    elif "sqlite" not in settings.DATABASE_URL:
        engine_kwargs.update({"pool_size": 5, "max_overflow": 0})
    return create_async_engine(settings.DATABASE_URL, **engine_kwargs)

# Celery-worker engine (NullPool — new event loop per task; also goes through PgBouncer)
def _make_worker_session_factory() -> async_sessionmaker[AsyncSession]:
    if "sqlite" in settings.DATABASE_URL:
        return AsyncSessionLocal
    connect_args: dict = {}
    if "asyncpg" in settings.DATABASE_URL:
        connect_args = _asyncpg_pgbouncer_connect_args()
    _worker_engine = create_async_engine(
        settings.DATABASE_URL, poolclass=NullPool, connect_args=connect_args, echo=settings.DEBUG,
    )
    return async_sessionmaker(bind=_worker_engine, class_=AsyncSession,
                             expire_on_commit=False, autoflush=False, autocommit=False)
```

### Why no unbounded prepared-statement buildup
SQLAlchemy's docs warn that unique statement names + PgBouncer can leak prepared
statements on server backends. That is neutralized here because **both caches are 0**:
asyncpg deallocates each statement after use, and prepare+deallocate stay on the same
backend within a single transaction. So unique names do **not** accumulate.

---

## Deployment context (so the rule isn't "cargo-culted")

From `docker-compose.yml`:
- `postgres` — system of record, `5432`.
- `pgbouncer` — `edoburu/pgbouncer`, `POOL_MODE: transaction`, `DEFAULT_POOL_SIZE: 20`,
  exposed on host `5433` → container `5432`. **App and workers connect here.**
- `DATABASE_URL` for app/workers: `postgresql+asyncpg://ica:ica@pgbouncer:5432/ica`.
- `backend-migrate` (Alembic): `postgresql+asyncpg://ica:ica@postgres:5432/ica` (**direct**, bypasses PgBouncer).

---

## How to verify a change (regression test)

Test file: `backend/tests/integration/test_pgbouncer_prepared_statements.py`

- **Unit (always runs, SQLite suite):** asserts the helper disables both caches and that
  the name func yields unique names; asserts both engines wire it.
- **Integration (`PG_INTEGRATION=1`, live PgBouncer):** hammers the app's real
  `connect_args` and asserts **zero** `DuplicatePreparedStatementError`, **plus a negative
  control** using the default config that asserts the error *still reproduces* — so a green
  result can't be a false negative.

```bash
# default suite (no Postgres needed)
pytest tests/integration/test_pgbouncer_prepared_statements.py        # 2 passed, 1 skipped

# against the live docker-compose stack
PG_INTEGRATION=1 pytest tests/integration/test_pgbouncer_prepared_statements.py   # 3 passed
```

The integration test reads its DSN from `PGBOUNCER_TEST_URL` (default
`postgresql+asyncpg://ica:ica@localhost:5433/ica`) — a **separate** env var from
`DATABASE_URL` so the app engine stays on SQLite and conftest's autouse `db_schema`
fixture (which runs SQLite `PRAGMA`s) keeps working.

---

## Anti-patterns to reject in review / generation

- ❌ Creating a `postgresql+asyncpg` engine with only `statement_cache_size=0`
  ("the docs hint said so") — **does not fix the error.**
- ❌ Putting `prepared_statement_cache_size` (or `prepared_statement_name_func`) as a
  top-level `create_async_engine()` kwarg — raises `TypeError` at engine construction.
- ❌ Adding the asyncpg `connect_args` to the SQLite test engine.
- ❌ Routing Alembic migrations through PgBouncer.
- ❌ Building a second async engine somewhere that skips `_asyncpg_pgbouncer_connect_args()`.

---

## Reference / provenance

- SQLAlchemy asyncpg dialect, "Prepared Statement Name with PGBouncer"
  (`sqlalchemy/dialects/postgresql/asyncpg.py` docstring; `_default_name_func` returns `None`;
  `_prepare` always calls `connection.prepare(..., name=name_func())`).
- asyncpg auto-naming: https://github.com/MagicStack/asyncpg/issues/837
- SQLAlchemy issue: https://github.com/sqlalchemy/sqlalchemy/issues/6467
- Versions validated against: SQLAlchemy 2.0.30, asyncpg 0.29.0.
```
