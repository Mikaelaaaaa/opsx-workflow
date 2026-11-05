# CODEBASE.md Template

Structured codebase context for AI agents. Every field should be a fact, not an opinion.

## Required sections

### Project Identity
```markdown
- **Name**: {name}
- **Type**: {web app | CLI | library | monorepo | infrastructure | scripts}
- **Languages**: {primary}, {secondary}
- **Framework**: {main framework}
- **Package Manager**: {npm | pnpm | pip | cargo | none}
```

### Entry Points
Table: Entry | Path | Purpose

### Module Inventory
One section per module:
```markdown
### {Module Name}
- **Path**: `src/{module}/`
- **Purpose**: {one line}
- **Exports**: `{key exports}`
- **Depends on**: `{modules}`
- **Depended by**: `{modules}`
```

### Build & Run
The essential commands — install, dev, test, build.

## Optional sections (include when relevant)

### Key Patterns
Named patterns with where/convention/example.

### Data Flow
ASCII showing the primary request/data pipeline.

### Environment & Config
Table: Variable | Purpose | Required

### File Naming Conventions
Pattern → meaning mapping.

### Gotchas
Non-obvious things that would surprise a developer or AI working in this codebase.

### Packages (for monorepos)
Table: Package | Path | Purpose | Internal Dependencies

### Stacks (for infrastructure repos)
Table: Stack | Path | What it deploys | Hosts

## Guidelines

- Facts only, no opinions
- Use exact paths and file references
- One sentence per description
- Structure for grep-ability (consistent headers, table format)
- Don't duplicate what's already in CLAUDE.md — CODEBASE.md covers structural facts, CLAUDE.md covers behavioral instructions
