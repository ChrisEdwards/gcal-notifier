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
   bd sync
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

## Beads Rust (br) — Dependency-Aware Issue Tracking

br provides a lightweight, dependency-aware issue database and CLI for selecting "ready work," setting priorities, and tracking status.

### Essential Commands

```bash
br ready              # Show issues ready to work (no blockers)
br list --status open # All open issues
br show <id>          # Full issue details with dependencies
br create --title "Fix bug" --type bug --priority 2 --description "Details here"
br update <id> --status in_progress
br close <id> --reason "Completed"
br sync               # Export to JSONL for git sync
```

### Workflow Pattern

1. **Start**: Run `br ready --json` to find actionable work
2. **Claim**: Use `br update <id> --status in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id> --reason "Done"`
5. **Sync**: Always run `br sync` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog
- **Types**: task, bug, feature, epic, question, docs
- **JSON output**: Always use `--json` or `--robot` when parsing programmatically

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
