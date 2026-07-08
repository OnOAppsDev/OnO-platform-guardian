# Platform Guardian

Multi-platform development governance system for Claude Code. Enforces consistent, gated workflows across all platform teams through a shared organizational knowledge repository.

## The Problem

Managing a product across 7+ platforms (Android Mobile, iOS Mobile, Apple TV, Android TV, Tizen, WebOS, Vidaa) with multiple developers creates:
- No single reliable source of truth
- Inconsistency between platforms with no clear root cause
- Developers making undocumented architecture deviations
- New developers unable to understand what "correct" looks like
- Claude producing inconsistent code across different project sessions

## The Solution

Two repositories working together:

| Repo | Purpose | Maintained by |
|------|---------|--------------|
| **This repo (Repo A)** | Claude Code MCP plugin that enforces workflow | Dev team lead |
| **Org Knowledge (Repo B)** | Source of truth for all standards | PM + Architects + Design Lead |

The plugin sits between the developer and Claude, enforcing sequential workflow phases that cannot be skipped. Every Claude action is validated against the rules in Repo B before execution.

## Workflow Phases (enforced, sequential)

| Phase | Name | Gate |
|-------|------|------|
| 0 | Environment Setup | Plugin connected, Repo B accessible |
| 1 | Project Registration | Platform type registered in Repo B |
| 2 | Initial Audit | Phase 1 complete |
| 3 | Architecture Analysis | Audit acknowledged by developer + PM |
| 4 | Rules Definition | Architecture documented + PM/Tech Lead approval |
| 5 | Development Mode | CLAUDE.md approved |
| 6 | Release Preparation | Feature QA complete, no blockers |

See `docs/process-overview.html` for an interactive visualization of the full system.

## Repository Structure

```
org-platform-guardian/        ← This repo (Repo A)
├── plugin/                   ← MCP server (Node.js/TypeScript)
│   └── src/
│       ├── workflow/         ← Phase enforcement and gate conditions
│       ├── knowledge/        ← Org Knowledge Repo connector and cache
│       ├── analysis/         ← Audit and gap analysis engine
│       └── tools/            ← MCP tool definitions
├── workflows/                ← Phase and gate definitions (YAML)
├── templates/                ← CLAUDE.md and project-config templates
├── org-knowledge-template/   ← Starter structure for Repo B
└── docs/
    ├── process-overview.html ← Interactive system overview
    ├── plugin-spec.md        ← Plugin technical specification
    ├── domains.md            ← Knowledge domain definitions
    └── workflow.md           ← Workflow phase specification
```

## Knowledge Domains (what must exist in Repo B)

1. **Design System** — Tokens, components, themes, platform adaptations
2. **Product Specifications** — Feature definitions, flows, acceptance criteria
3. **Architecture Decisions** — ADRs, patterns, approved libraries, forbidden patterns
4. **Development Guidelines** — Coding standards, naming, structure
5. **AI Work Rules** — Claude allowed/forbidden ops, human gate requirements
6. **Platform Constraints** — Per-platform capability matrix and limitations
7. **QA & Testing Standards** — Coverage requirements, test types, sign-off criteria
8. **Release & CI/CD** — Build process, deployment, cross-platform coordination
9. **Security & Privacy** ⚠️ — Auth, data storage, compliance
10. **Performance Budgets** ⚠️ — Memory limits and load targets per platform
11. **Localization & i18n** ⚠️ — Language coverage, RTL support, markets
12. **Monitoring & Analytics** ⚠️ — Event taxonomy, error tracking standards

Items marked ⚠️ are critical additions not commonly documented — especially performance budgets for TV platforms with hardware constraints.

## Developer Installation

```bash
# 1. Clone this repo
git clone <repo-a-url> org-platform-guardian

# 2. Install MCP server
cd org-platform-guardian/plugin
npm install

# 3. Add to Claude Code settings (~/.claude/settings.json)
{
  "mcpServers": {
    "platform-guardian": {
      "command": "node",
      "args": ["<path-to-plugin>/dist/server.js"],
      "env": {
        "ORG_KNOWLEDGE_REPO": "<repo-b-url-or-local-path>"
      }
    }
  }
}
```

## Development Status

- [x] System architecture defined
- [x] Workflow phases specified
- [x] Knowledge domains defined
- [x] Interactive documentation (process-overview.html)
- [x] CLAUDE.md and project-config templates
- [x] Org Knowledge template structure (org-knowledge-template/)
- [ ] MCP server implementation
- [ ] Workflow enforcement engine
- [ ] Code audit engine
- [ ] Gap report generator
- [ ] Architecture analyzer
- [ ] Org Knowledge Repository (Repo B) — to be created separately

## Next Steps

1. Create and populate Org Knowledge Repository (Repo B) in Bitbucket
2. Implement MCP server (starting with workflow engine)
3. Run initial audit on first platform (recommendation: start with iOS Mobile as baseline)
4. Iterate plugin based on first platform audit findings
5. Roll out to remaining platforms

## Open Questions (must resolve before launch)

- Who has write access to Repo B? What is the review/approval process for changes?
- How do projects handle Repo B version upgrades when standards change?
- Is there an emergency override mechanism for production incidents?
- What is the escalation path when a developer is blocked and PM is unavailable?
