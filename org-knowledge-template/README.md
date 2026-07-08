# Org Knowledge Repository

> This is Repo B — the organizational source of truth for all platform development standards.
> Maintained by: PM + Architects + Design Lead
> Access: Read for all developers, Write requires approval via PR

## Purpose

This repository is the single source of truth that Platform Guardian reads to enforce
development standards across all platforms. Every policy, spec, design decision, and rule
lives here. Without content in this repository, developers cannot build.

## How to Contribute

1. Create a branch from `main`
2. Add or update content in the relevant domain folder
3. Open a PR — approval required from the domain owner (see table below)
4. After merge, all developers will receive the update on their next `guardian sync`

## Domain Ownership

| Domain | Folder | Owner | Required Approver |
|--------|--------|-------|-------------------|
| Design System | `design-system/` | Design Lead | Design Lead |
| Product Specifications | `product-spec/` | Product Manager | PM |
| Architecture Decisions | `architecture/` | Architect | Architect + Tech Lead |
| Development Guidelines | `dev-guidelines/` | Tech Lead | Tech Lead |
| AI Work Rules | `ai-rules/` | Dev Lead | Tech Lead |
| Platform Constraints | `platforms/` | Platform Leads | Relevant Platform Lead |
| QA & Testing | `qa-process/` | QA Lead | QA Lead |
| Release & CI/CD | `release-process/` | DevOps | Tech Lead + DevOps |
| Security & Privacy | `security/` | Tech Lead | Tech Lead + Legal |
| Performance Budgets | `performance/` | Architect | Architect |
| Localization | `localization/` | Dev Lead | PM + Dev Lead |
| Monitoring & Analytics | `monitoring/` | PM + Dev Lead | PM |

## Versioning

This repository is versioned via git tags. Platform Guardian tracks which version each
project has been audited against. When a new version is tagged, all projects receive a
notification to re-run their audit.

Tag format: `v{major}.{minor}.{patch}`
- Major: Breaking changes that require all projects to re-run Phase 2+
- Minor: New domains or significant additions — projects should re-audit
- Patch: Clarifications and non-breaking additions

## Required Structure

Each folder must have at minimum:
1. A `README.md` explaining what the folder contains and who maintains it
2. Content files in Markdown format
3. A `CHANGELOG.md` for the domain

## Status

| Domain | Status | Last Updated |
|--------|--------|-------------|
| design-system/ | 🔴 Not started | — |
| product-spec/ | 🔴 Not started | — |
| architecture/ | 🔴 Not started | — |
| dev-guidelines/ | 🔴 Not started | — |
| ai-rules/ | 🔴 Not started | — |
| platforms/ | 🔴 Not started | — |
| qa-process/ | 🔴 Not started | — |
| release-process/ | 🔴 Not started | — |
| security/ | 🔴 Not started | — |
| performance/ | 🔴 Not started | — |
| localization/ | 🔴 Not started | — |
| monitoring/ | 🔴 Not started | — |

🔴 Not started | 🟡 In progress | 🟢 Complete
