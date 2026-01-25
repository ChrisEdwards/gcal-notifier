# Agent Development Guidelines

## RULE 1 – ABSOLUTE (DO NOT EVER VIOLATE THIS)

You may NOT delete any file or directory unless I explicitly give the exact command **in this session**.

- This includes files you just created (tests, tmp files, scripts, etc.).
- You do not get to decide that something is “safe” to remove.
- If you think something should be removed, stop and ask. You must receive clear written approval **before** any deletion command is even proposed.

Treat “never delete files without permission” as a hard invariant.

---

### IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Absolutely forbidden unless I give the **exact command and explicit approval** in the same message:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite code/data

Rules:

1. If you are not 100% sure what a command will delete, do not propose or run it. Ask first.
2. Prefer safe tools: `git status`, `git diff`, `git stash`, copying to backups, etc.
3. After approval, restate the command verbatim, list what it will affect, and wait for confirmation.
4. When a destructive command is run, record in your response:
   - The exact user text authorizing it
   - The command run
   - When you ran it

If that audit trail is missing, then you must act as if the operation never happened.

---

### Code Editing Discipline

- Do **not** run scripts that bulk-modify code (codemods, invented one-off scripts, giant `sed`/regex refactors).
- Large mechanical changes: break into smaller, explicit edits and review diffs.
- Subtle/complex changes: edit by hand, file-by-file, with careful reasoning.

---

### Backwards Compatibility & File Sprawl

We optimize for a clean architecture now, not backwards compatibility.

- No “compat shims” or “v2” file clones.
- When changing behavior, migrate callers and remove old code.
- New files are only for genuinely new domains that don’t fit existing modules.
- The bar for adding files is very high.

---

## Development Commands

Use these make targets for all checks and tests:

```bash
make check       # Run linting and static analysis (quiet output)
make test        # Run all tests (quiet output)
make check-test  # Run both checks and tests

# Verbose output when debugging failures
make check VERBOSE=1
make test VERBOSE=1
```

## Quick Reference: br Commands

```bash
# Adding comments - use subcommand syntax, NOT flags
br comments add <issue-id> "comment text"   # CORRECT
br comments <issue-id> --add "text"         # WRONG - --add is not a flag

# Labels
br label add <issue-id> <label>
br label remove <issue-id> <label>
```

---

### Third-Party Libraries

When unsure of an API, look up current docs (late-2025) rather than guessing.

---

## Available Tools

### ripgrep (rg)
Fast code search tool available via command line. Common patterns:
- `rg "pattern"` - search all files
- `rg "pattern" -t go` - search only Go files
- `rg "pattern" -g "*.go"` - search files matching glob
- `rg "pattern" -l` - list matching files only
- `rg "pattern" -C 3` - show 3 lines of context

### ast-grep (sg)
Structural code search using AST patterns. Use when text search is fragile (formatting varies, need semantic matches).
```bash
sg -p 'func $NAME($$$) { $$$BODY }' -l swift    # Find functions
sg -p '$VAR.transform($$$)' -l swift            # Find method calls
```

---

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   br sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

---

## Issue Tracking with beads-rust

This project uses **br** (beads-rust) for issue tracking. Data is stored in `.beads/` directory.

### Quick Reference

```bash
br ready              # Find available work (unblocked issues)
br list               # List all open issues
br list --all         # Include closed issues
br show <id>          # View issue details with dependencies
br show <id> --json   # JSON output for programmatic use
```

### Creating & Managing Issues

```bash
# Create issues
br create "Title" --type task --priority 2 --description "Details"
br create "Epic title" --type epic --priority 1
br create "Child task" --type task --parent <epic-id>

# Update status
br update <id> --status in_progress   # Claim work
br update <id> --status open          # Release work
br update <id> --assignee "email"     # Assign to someone

# Close issues
br close <id>                         # Mark complete
br close <id> --reason "explanation"  # With reason
```

### Dependencies

```bash
br dep add <issue> <depends-on>       # Add dependency (issue depends on depends-on)
br dep remove <issue> <depends-on>    # Remove dependency
br dep list <id>                      # List dependencies
br dep tree <id>                      # Show dependency tree
br dep cycles                         # Detect circular dependencies
```

### Filtering & Search

```bash
br list --status open                 # Filter by status
br list --type task                   # Filter by type (task, bug, feature, epic)
br list --priority 1                  # Filter by priority (0-4, 0=critical)
br list --label backend               # Filter by label
br list --assignee "email"            # Filter by assignee
br ready --type task                  # Ready tasks only (exclude epics)
```

### Syncing with Git

```bash
br sync --flush-only                  # Export DB to JSONL (for commits)
git add .beads/ && git commit         # Commit issue changes
```

### JSON Output

Most commands support `--json` for programmatic access:

```bash
br list --json | jq '.[0]'            # First issue
br ready --json | jq 'length'         # Count of ready issues
br show <id> --json | jq '.dependents'  # Get children of epic
```

### Priority Levels

| Priority | Meaning |
|----------|---------|
| P0 (0) | Critical - Drop everything |
| P1 (1) | High - Do soon |
| P2 (2) | Medium - Normal work |
| P3 (3) | Low - When time permits |
| P4 (4) | Backlog - Someday/maybe |

### Issue Types

- `epic` - Large feature or initiative containing child tasks
- `feature` - New functionality
- `task` - General work item
- `bug` - Defect to fix

### Parent-Child Relationships

When you create a task with `--parent <epic-id>`, a parent-child dependency is created. The epic's `dependents` field lists all children:

```bash
br show <epic-id> --json | jq '.dependents[] | select(.dependency_type == "parent-child")'
```

---

## Reference Projects

This project follows patterns established in two sibling Rust CLI projects:

### CodexBar
Location: `../CodexBar`

### Optimus Clip
Location: `../optimus-clip`

---

**IMPORTANT:** NEVER DISABLE LINT RULES JUST TO MAKE IT EASIER ON YOURSELF. THEY ARE THERE FOR A REASON. Do the right thing...always.

---

## Lint rules
Try to obey these rules as you write so you dont have to re-do code when the rules fail linting.

Keep lines under 150 chars.
Keeep files under 1000 lines long.
Keep function bodies less then 100 lines.long.
Keep cyclomatic complexity below 20.

When a file gets too big, don't compromise code quality to make it smaller. THE WHOLE POINT OF THESE RESTRICTIONS IS TO IMPROVE CODE QUALITY. JUST DO IT! Refactor, don't just delete lines. Improve the code.

---

## Philosophy

This codebase will outlive you. Every shortcut becomes someone else's burden. Every hack compounds into technical debt that slows the whole team down.

You are not just writing code. You are shaping the future of this project. The patterns you establish will be copied. The corners you cut will be cut again.

Fight entropy. Leave the codebase better than you found it.
