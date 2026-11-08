# Governance — Platform Guardian

Decisions about who owns what, who approves what, and how changes propagate.

---

## Repo A Governance (Plugin Repository)

**Owner:** Dev Team Lead (or designated maintainer)

**Change process:**
- All changes via pull request
- Owner must approve every PR
- At least 1 additional reviewer required (technical peer review)
- No direct commits to main

**What requires a PR:**
- Any change to workflow phase definitions (`workflows/phases.yaml`)
- Any change to CLAUDE.md template (`templates/CLAUDE.md.template`)
- Any change to MCP tool behavior (`plugin/src/tools/`)
- Any change to gate conditions

**Why at least 1 reviewer:** The plugin enforces rules for all developers across all platforms.
A broken gate condition or a wrong tool behavior affects every developer simultaneously.
Two sets of eyes before any change to main is a minimum safety bar.

---

## Repo B Governance (Org Knowledge Repository)

**Owner:** Varies by domain (see `org-knowledge-template/README.md` domain ownership table)

**Change process:**
- All changes via pull request
- Domain owner must approve any PR touching their domain
- At least 1 reviewer required
- No direct commits to main

**Versioning:** Semantic versioning tagged on every merge to main.

### Version Format

```
v{major}.{minor}.{patch}
```

| Bump type | When to use | Examples |
|-----------|------------|---------|
| **Major** | Breaking change — an existing standard is replaced or removed | Changing the approved state management library, replacing the design token system, removing a platform from supported list |
| **Minor** | New standard added, or an existing one significantly updated | Adding a new domain, adding new required components to design system, adding a new approved library |
| **Patch** | Clarification, typo fix, non-breaking addition | Fixing a typo in a spec, adding an example, clarifying acceptance criteria wording |

### Change Impact on Existing Projects

When Repo B changes, the plugin detects the version mismatch at session start (Phase 0 environment
check) and triggers a tiered developer response based on the bump type.

| Version bump | Plugin behavior on session start | Developer required action | Deadline |
|---|---|---|---|
| **Major** | BLOCKS all feature development | Full Phase 2 re-audit for affected domains. PM acknowledgement required. | 14 days |
| **Minor** | WARNS — shows domain-level diff of what changed | Acknowledge specific changed domains. Targeted re-check (not full re-audit). | 7 days |
| **Patch** | NOTIFIES once (non-blocking) | Read and mark as seen. No re-audit. | None |

**What "domain-level diff" means:** The plugin shows which top-level folders in Repo B changed
between the project's last-synced version and current. For example:

```
⚠️  Org Knowledge updated: v1.3.0 → v1.4.0 (minor)

Changed domains:
  - architecture/approved-libraries.md  (2 new libraries added)
  - design-system/tokens/colors.json    (4 token values updated)

Action required: Acknowledge these changes before continuing development.
This will trigger a targeted re-check of architecture and design system compliance.
```

The developer reads the diff, acknowledges, and the plugin records the acknowledgement in
`.platform-guardian/phase-state.json` with version and timestamp.

---

## Alert Mechanism

The change detection fires at every session start as part of Phase 0, not as a background service.
This keeps the architecture simple — no webhooks, no polling service, no push infrastructure.

Flow:
1. Developer starts a Claude Code session
2. Plugin checks Repo B (git fetch, compare tags)
3. If version mismatch → interrupt with alert before any work begins
4. Developer acknowledges (or schedules re-audit for major changes)
5. Acknowledgement stored in project state
6. Session continues

For **major** version bumps, work is blocked until Phase 2 re-audit is complete for affected domains.
For **minor** version bumps, work continues but the acknowledgement deadline is tracked and shown
as a reminder at each session start until resolved.

---

## Escalation Path

If a developer is blocked by a governance gate and the approver is unavailable:

1. Create a tracking issue tagged `platform-guardian-block`
2. Tag both the domain owner and the Tech Lead
3. Do not bypass — document the block and timeline
4. For production incidents only: use `guardian emergency-bypass` (see `docs/workflow.md`)

---

## Open Decisions

None remaining from initial planning. All governance questions resolved:
- ✅ Repo A: Owner + 1 reviewer required
- ✅ Repo B: Domain owner approval required
- ✅ Repo B changes: Plugin detects at session start, tiered response by version bump type
- ✅ Versioning: Semantic versioning on Repo B, domain-level diffing for targeted re-checks
- ✅ Escalation: Track as blocking issue, no silent bypasses
