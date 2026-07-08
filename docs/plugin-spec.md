# Plugin Technical Specification

## Overview

Platform Guardian is a Claude Code MCP (Model Context Protocol) server.
It intercepts developer interactions with Claude and enforces organizational workflow gates
before allowing any action to proceed.

## Technology Choice

- **Runtime**: Node.js with TypeScript
- **Protocol**: MCP (Model Context Protocol) — the standard Claude Code plugin protocol
- **Storage**: Git (Repo B read access) + local file cache + per-project YAML/JSON state
- **Authentication**: Org git credentials (same as developer's existing git access)

## MCP Tool Definitions

The plugin exposes the following MCP tools that Claude uses automatically:

### `guardian_check_phase`
Check if the current project has completed a required phase before proceeding.

```typescript
{
  name: "guardian_check_phase",
  description: "Check if a workflow phase is complete. Call this before starting any significant work.",
  input_schema: {
    required_phase: "string",  // "p0" | "p1" | "p2" | "p3" | "p4" | "p5" | "p6"
    action_description: "string"  // What the developer wants to do
  }
}
// Returns: { allowed: boolean, message: string, next_steps?: string[] }
```

### `guardian_check_spec`
Check if a feature has a product specification in the Org Knowledge Repository.

```typescript
{
  name: "guardian_check_spec",
  description: "Before implementing any feature, verify it has a spec in the org knowledge repo.",
  input_schema: {
    feature_name: "string",
    platform: "string"
  }
}
// Returns: { found: boolean, spec_path?: string, message: string }
```

### `guardian_check_design`
Check if UI design assets exist for a component.

```typescript
{
  name: "guardian_check_design",
  description: "Before building any UI component, verify design assets exist.",
  input_schema: {
    component_name: "string"
  }
}
// Returns: { found: boolean, asset_path?: string, message: string }
```

### `guardian_check_dependency`
Check if a library is on the approved dependency list.

```typescript
{
  name: "guardian_check_dependency",
  description: "Before adding any dependency, verify it is approved.",
  input_schema: {
    library_name: "string",
    version?: "string"
  }
}
// Returns: { approved: boolean, approved_version?: string, alternative?: string, message: string }
```

### `guardian_check_platform_capability`
Check if a feature or capability is supported on the current platform.

```typescript
{
  name: "guardian_check_platform_capability",
  description: "Before implementing platform-specific functionality, verify it is supported.",
  input_schema: {
    capability: "string",
    platform: "string"
  }
}
// Returns: { supported: boolean, support_level: "full" | "partial" | "none", notes?: string }
```

### `guardian_run_audit`
Run the Phase 2 audit — compare codebase against org specs.

```typescript
{
  name: "guardian_run_audit",
  description: "Run comprehensive audit of codebase against organizational specifications.",
  input_schema: {
    scope?: string[]  // Specific domains to audit, or all if omitted
  }
}
// Returns: { critical: Finding[], warnings: Finding[], informational: Finding[], report_path: string }
```

### `guardian_get_rules`
Get the CLAUDE.md rules for the current project.

```typescript
{
  name: "guardian_get_rules",
  description: "Get the current project rules from CLAUDE.md.",
  input_schema: {}
}
// Returns: { rules: string, version: string, approved_by: string, approved_date: string }
```

### `guardian_complete_phase`
Mark a phase as complete (requires human acknowledgement for Phase 4).

```typescript
{
  name: "guardian_complete_phase",
  description: "Mark a workflow phase as complete and record completion.",
  input_schema: {
    phase: "string",
    acknowledged_by?: "string",  // Required for phases 2 and 4
    notes?: "string"
  }
}
```

---

## Architecture

```
plugin/src/
├── server.ts              # MCP server setup and tool registration
│
├── workflow/
│   ├── engine.ts          # Phase state management and gate checking
│   └── gates.ts           # Gate condition definitions per phase
│
├── knowledge/
│   ├── connector.ts       # Git-based access to Repo B
│   ├── cache.ts           # Local cache management (TTL-based)
│   └── parser.ts          # Parse org knowledge files into structured data
│
├── analysis/
│   ├── auditor.ts         # Phase 2 audit engine
│   ├── architecture.ts    # Phase 3 architecture analysis
│   └── reporter.ts        # Generate audit-report.md
│
├── tools/
│   ├── check-phase.ts     # guardian_check_phase implementation
│   ├── check-spec.ts      # guardian_check_spec implementation
│   ├── check-design.ts    # guardian_check_design implementation
│   ├── check-dependency.ts
│   ├── check-capability.ts
│   ├── run-audit.ts
│   ├── get-rules.ts
│   └── complete-phase.ts
│
└── utils/
    ├── logger.ts          # Audit trail logging
    └── config.ts          # Configuration loading
```

---

## Installation

### For Developers

1. Clone Repo A (this repo)
2. Run `npm install && npm run build` in `plugin/`
3. Add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "platform-guardian": {
      "command": "node",
      "args": ["/path/to/org-platform-guardian/plugin/dist/server.js"],
      "env": {
        "ORG_KNOWLEDGE_REPO": "git@bitbucket.org:yourorg/org-knowledge.git",
        "ORG_KNOWLEDGE_CACHE_PATH": "~/.platform-guardian/cache",
        "ORG_KNOWLEDGE_CACHE_TTL": "3600"
      }
    }
  }
}
```

### Per-Project Setup

```bash
# In any project directory
guardian init
# → Prompts for platform type
# → Reads from Org Knowledge Repo
# → Creates .platform-guardian/project-config.yaml
# → Begins Phase 0 validation
```

---

## State Storage

Phase state is stored in `.platform-guardian/phase-state.json`:

```json
{
  "project": "iOS Mobile",
  "platform": "ios-mobile",
  "org_knowledge_version": "v2.3.1",
  "phases": {
    "p0": { "status": "complete", "completed": "2024-03-15T10:00:00Z" },
    "p1": { "status": "complete", "completed": "2024-03-15T10:05:00Z" },
    "p2": {
      "status": "complete",
      "completed": "2024-03-16T14:00:00Z",
      "acknowledged_by": "tom@company.com",
      "acknowledged_date": "2024-03-16T16:00:00Z"
    },
    "p3": { "status": "complete", "completed": "2024-03-17T11:00:00Z" },
    "p4": {
      "status": "complete",
      "approved_by": "tech-lead@company.com",
      "approval_date": "2024-03-18T09:00:00Z"
    },
    "p5": { "status": "active", "activated": "2024-03-18T10:00:00Z" },
    "p6": { "status": "pending" }
  },
  "emergency_bypasses": []
}
```

---

## Security Considerations

- Repo B access uses the developer's existing git credentials — no new credentials needed
- Phase state files should be committed to the project repo (so the team tracks progress)
- CLAUDE.md should be committed and version-controlled
- No sensitive data should be stored in `.platform-guardian/` files
- Emergency bypass events are always logged and never silently discarded

---

## Implementation Priority

Phase 1 of plugin implementation (MVP — minimum viable enforcement):

1. `guardian_check_phase` — gate enforcement (highest priority)
2. `guardian_check_spec` — feature spec validation (highest priority)
3. `guardian_check_dependency` — dependency approval (high priority)
4. `guardian_check_platform_capability` — platform constraint enforcement (high priority)
5. `guardian_run_audit` — Phase 2 full audit (required for onboarding)
6. `guardian_get_rules` — CLAUDE.md access (medium priority)
7. `guardian_check_design` — design asset validation (medium priority)
8. `guardian_complete_phase` — phase state management (required for all)
