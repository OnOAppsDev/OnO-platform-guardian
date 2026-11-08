# Archive — July 2026 plan (MCP server / 7-phase gate)

Superseded on 2026-11-08. The original design — an MCP server that gated 7 development phases, audited code against an Org Knowledge Repository ("Repo B"), and generated per-repo CLAUDE.md — was overtaken by the org plugins themselves (see `docs/ecosystem-status-2026-11.md`):

- Phase gating now lives in `ono-mobile-dev-plugin` (8-stage approval chain) and the QA plugins (ledger / fingerprinted approvals).
- Platform standards live in `ono-mobile-dev-plugin/standards/`.
- Repo knowledge and CLAUDE.md generation belong to `ono-plugin-project-inspector`.

Guardian was redefined as the single entry-point router plugin — see `docs/vision.md`. Kept here for decision history only; nothing in this folder is current.
