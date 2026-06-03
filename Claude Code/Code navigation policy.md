## Code navigation policy

For TypeScript and Python:
- Prefer the LSP tool for symbol lookup, definitions, references, implementations, hover/type info, call hierarchy, workspace/file symbols, and diagnostics.
- Do not use Grep as the first choice for code understanding in .ts, .tsx, .py files.
- Use Grep only as a fallback when LSP is unavailable or when doing broad text-only searches such as config strings, comments, TODOs, or non-symbol literals.