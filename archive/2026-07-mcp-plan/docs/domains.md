# Knowledge Domains — Org Knowledge Repository

## What This Document Is

This defines exactly what must exist in the Org Knowledge Repository (Repo B) for Platform Guardian
to function correctly. Each domain is required. Without a domain, the plugin cannot audit or enforce
that area and will surface it as a gap.

Domains marked ⚠️ are critical additions not commonly thought of when planning this kind of system.
The consequences of skipping them are noted.

---

## Domain 1: Design System

**Location in Repo B:** `design-system/`

**Purpose:** Single source of truth for all visual and UI decisions. Claude must check this before
creating any component. If a component is not here, Claude is blocked from creating it.

**Required contents:**

```
design-system/
├── tokens/
│   ├── colors.json          # All color tokens with semantic names
│   ├── typography.json      # Font sizes, weights, line heights
│   ├── spacing.json         # Spacing scale
│   └── elevation.json       # Shadow and elevation definitions
├── components/
│   ├── button.md            # Component spec: variants, states, props
│   ├── card.md
│   ├── player-controls.md
│   └── ... (one file per component)
├── themes/
│   ├── light.json
│   ├── dark.json
│   └── tv-10-foot.json      # 10-foot UI theme for TV platforms
├── platform-adaptations/
│   ├── tv-typography.md     # Larger text for TV viewing distance
│   ├── mobile-touch.md      # Touch-specific component sizes
│   └── remote-focus.md      # Focus ring styles for D-pad navigation
└── accessibility/
    ├── contrast-requirements.md
    └── focus-order-rules.md
```

**What blocks without this:** Any UI implementation. Developer will be blocked until design assets exist.

---

## Domain 2: Product Specifications

**Location in Repo B:** `product-spec/`

**Purpose:** Feature definitions per platform. Claude cannot implement any feature that is not
defined here. This is the core enforcement gate in Phase 5.

**Required structure:**

```
product-spec/
├── _shared/                  # Features identical across all platforms
│   ├── authentication.md
│   └── playback-core.md
├── android-mobile/
│   ├── home-screen.md        # Feature spec with acceptance criteria
│   ├── player-screen.md
│   └── ...
├── ios-mobile/
├── apple-tv/
├── android-tv/
├── tizen/
├── webos/
└── vidaa/
```

**Each feature spec must contain:**
- Feature name and platform
- User story ("As a user, I want to...")
- Acceptance criteria (numbered, testable)
- Out of scope (explicit — prevents scope creep)
- Open questions (before PM sign-off: must be empty)

**What blocks without this:** Any feature development. No spec = no implementation.

---

## Domain 3: Architecture Decisions

**Location in Repo B:** `architecture/`

**Purpose:** Defines the technical boundaries. What technology is allowed, what patterns to use,
what is explicitly forbidden.

**Required contents:**

```
architecture/
├── adr/                         # Architecture Decision Records
│   ├── 001-state-management.md  # Why Redux, not MobX
│   ├── 002-navigation.md        # Chosen navigation solution
│   └── ...
├── approved-libraries.md        # FULL list of approved dependencies per platform
├── forbidden-patterns.md        # Code patterns Claude must never produce
├── tech-stack.md                # Current stack definition per platform
├── api-design.md                # API contract standards
└── error-handling.md            # Error strategy and patterns
```

**The approved-libraries.md is critical.** Without it, the plugin cannot enforce dependency control.
Format per entry:
```markdown
| Library | Version | Platform | Purpose | Approved by | Approved date |
|---------|---------|----------|---------|-------------|---------------|
| SWR | ^2.0 | all | Server state | Tech Lead | 2024-01-15 |
```

---

## Domain 4: Development Guidelines

**Location in Repo B:** `dev-guidelines/`

**Purpose:** Defines what "good code" means in this organization. Not style preferences — enforceable rules.

**Required contents:**

```
dev-guidelines/
├── naming-conventions.md    # Files, variables, components, events
├── folder-structure.md      # Directory structure per platform type
├── code-review-checklist.md # What reviewers must check
├── git-workflow.md          # Branch naming, commit messages, PR rules
├── testing-patterns.md      # How to write tests (not coverage — that's in QA)
└── error-messages.md        # User-facing error message standards
```

---

## Domain 5: AI Work Rules

**Location in Repo B:** `ai-rules/`

**Purpose:** Organization-specific rules for Claude. What Claude is allowed to do, what it must never do,
and where human review is always required.

**Required contents:**

```
ai-rules/
├── allowed-operations.md     # What Claude can do autonomously
├── forbidden-operations.md   # What Claude must NEVER do
├── human-gates.md            # Actions that always require human review
├── prompting-guidelines.md   # How developers should prompt Claude
└── verification-checklist.md # What developers must verify after Claude generates code
```

**Forbidden operations (examples to define):**
- Deleting files without explicit developer confirmation
- Modifying CLAUDE.md directly (must use plugin)
- Adding dependencies without checking approved list
- Making database schema changes without Tech Lead review
- Touching authentication or security-related code without security review
- Implementing a feature that conflicts with platform constraints

---

## Domain 6: Platform Constraints

**Location in Repo B:** `platforms/`

**Purpose:** Per-platform capability matrix and hardware constraints. Critical for preventing developers
from building features that won't work on target platforms. Especially important for TV platforms.

**Required structure per platform:**

```
platforms/{{platform}}/
├── constraints.md            # Hardware limits, OS limitations
├── capability-matrix.md      # What features are supported (links to master matrix)
├── navigation-patterns.md    # How navigation works (touch vs remote vs gamepad)
├── performance-limits.md     # Memory budget, CPU budget, startup time target
├── testing-requirements.md   # How to test on this platform (real device? emulator?)
└── known-issues.md           # Documented bugs/limitations in platform SDK
```

**TV Platform specific (Tizen, WebOS, Vidaa) — must define:**
- Maximum memory allocation
- Supported JavaScript engine and ES version
- CSS feature support (some CSS is not supported in older TV browsers)
- Supported video codecs and DRM systems
- Remote control key mapping

---

## Domain 7: QA & Testing Standards

**Location in Repo B:** `qa-process/`

**Required contents:**

```
qa-process/
├── standards.md              # Minimum coverage %, required test types
├── unit-testing.md           # Unit test patterns and requirements
├── integration-testing.md    # Integration test requirements
├── e2e-testing.md            # E2E test coverage and tooling
├── device-testing.md         # Which physical devices must be tested
├── qa-signoff-checklist.md   # What QA must verify before signing off
└── regression-suite.md       # Must-run regression tests per release
```

---

## Domain 8: Release & CI/CD

**Location in Repo B:** `release-process/`

**Required contents:**

```
release-process/
├── ci-pipeline.md            # How CI/CD is structured per platform
├── environments.md           # Dev, staging, production definitions
├── release-checklist.md      # Step-by-step release process
├── cross-platform-coordination.md  # How to coordinate simultaneous releases
├── rollback-procedure.md     # How to roll back a broken release
└── hotfix-process.md         # How to handle production incidents
```

---

## Domain 9: Security & Privacy ⚠️

**Location in Repo B:** `security/`

**Why this is critical:** This is the most commonly skipped domain and the most dangerous to ignore.
Without documented security standards, developers make inconsistent decisions about token storage,
API security, and data handling — across 7 platforms.

**Required contents:**

```
security/
├── auth-patterns.md          # How authentication tokens are stored and refreshed
├── data-storage-rules.md     # What can/cannot be stored locally, encrypted fields
├── api-security.md           # Required headers, certificate pinning, API key handling
├── sensitive-data.md         # PII handling, what to never log
├── compliance-requirements.md # GDPR, COPPA, regional requirements
└── security-review-checklist.md # Required before any auth/security code ships
```

---

## Domain 10: Performance Budgets ⚠️

**Location in Repo B:** `performance/`

**Why this is critical:** TV platforms (Tizen, WebOS, Vidaa) have strict hardware limitations.
An app that works perfectly on iOS will crash on a Tizen TV with 512MB RAM if performance budgets
are not defined and enforced from the start.

**Required contents:**

```
performance/
├── budgets.md                # Per-platform concrete numbers
├── measurement-approach.md   # How to measure (tooling, CI integration)
├── optimization-patterns.md  # Approved optimization techniques
└── memory-management.md      # TV-specific memory management requirements
```

**Example budget entry:**
```markdown
## Tizen (Samsung Smart TV)
- Maximum heap usage at runtime: 256MB
- App startup time (cold start): < 3 seconds
- Page transition time: < 500ms
- Maximum image cache size: 50MB
- Video player initialization: < 2 seconds
```

---

## Domain 11: Localization & i18n ⚠️

**Location in Repo B:** `localization/`

**Required contents:**

```
localization/
├── supported-languages.md    # All supported languages and their codes
├── rtl-requirements.md       # RTL layout rules (Hebrew, Arabic markets)
├── string-conventions.md     # How to name and organize translation keys
├── date-number-formats.md    # Regional formatting rules
├── missing-translation.md    # Fallback behavior for missing translations
└── content-restrictions.md   # Market-specific content rules
```

---

## Domain 12: Monitoring & Analytics ⚠️

**Location in Repo B:** `monitoring/`

**Why this is critical:** Without a shared event taxonomy, developers on different platforms use
different event names for the same user action. This makes cross-platform analytics impossible
and cross-platform debugging very difficult.

**Required contents:**

```
monitoring/
├── event-taxonomy.md         # MASTER LIST of all analytics events with exact names
├── event-properties.md       # Required properties per event type
├── logging-standards.md      # Log levels, what to log, what NEVER to log (PII)
├── error-tracking.md         # How errors are captured and categorized
├── dashboards.md             # Links to monitoring dashboards per platform
└── alerting-rules.md         # What triggers an alert and who is notified
```

**Event taxonomy example:**
```markdown
| Event Name | Trigger | Required Properties | Platform |
|------------|---------|---------------------|----------|
| content.play.start | User taps/selects play | content_id, content_type, platform, position_ms | all |
| content.play.pause | User pauses | content_id, position_ms | all |
| navigation.screen.view | Screen becomes visible | screen_name, previous_screen | all |
```

---

## Summary Checklist

Before Platform Guardian can function fully, every domain must have content in Repo B.
The plugin will report which domains are incomplete during Phase 2.

| Domain | Required | Who Owns It |
|--------|----------|-------------|
| Design System | Yes | Design Lead |
| Product Specifications | Yes | Product Manager |
| Architecture Decisions | Yes | Architect / Tech Lead |
| Development Guidelines | Yes | Tech Lead |
| AI Work Rules | Yes | Tech Lead / Dev Lead |
| Platform Constraints | Yes | Platform Leads |
| QA & Testing Standards | Yes | QA Lead |
| Release & CI/CD | Yes | DevOps / Tech Lead |
| Security & Privacy | Yes | Tech Lead + Legal |
| Performance Budgets | Yes | Architect + Platform Leads |
| Localization & i18n | If multi-market | PM + Dev Lead |
| Monitoring & Analytics | Yes | PM + Tech Lead |
