---
name: commit
description: Stage, format, and commit code changes using conventional commits (feat/fix/docs/chore/refactor). Auto-detects whether to amend the previous commit when changes are strongly related. Use when the user wants to commit, says "commit this", "commit changes", "push this", or mentions git commit/amend.
---

# Commit Skill

## Quick start

Run these checks, then commit:

```bash
# 1. Current state
git status && git diff --stat && git diff --cached --stat

# 2. Last commit for context (scope, amend decision)
git log -1 --format='%s'
```

## Workflow

### 1. Determine commit type

| Type       | When                                     |
| ---------- | ---------------------------------------- |
| `feat`     | New feature or functionality             |
| `fix`      | Bug fix                                  |
| `docs`     | Documentation only                       |
| `chore`    | Build, deps, config, tooling             |
| `refactor` | Code restructuring, no behaviour change  |
| `style`    | Formatting, whitespace (no logic change) |
| `test`     | Adding or updating tests                 |

### 2. Determine scope

Extract the feature/module name from changed file paths or the work context. Use lowercase, hyphenated names. Examples: `auth`, `payment`, `dashboard`.

### 3. Write commit message

```
type(scope): imperative description, no period
```

- **Imperative mood**: "add button" not "added button"
- **Lowercase after colon**
- **No trailing period**
- **Max ~72 chars for summary line**
- For multi-line: blank line then body

### 4. Amend decision

Judge if changes are **strongly related** to the last commit. Use `--amend` when:

- Same scope AND same type as last commit
- Same files being modified (or files in same module)
- "Forgot to add X" / fixup / follow-up nature
- Short time gap (same working session)

**Skip amend** when:

- Different scope from last commit
- Different type (feat → fix)
- Distinct, self-contained change

### 5. Execute

```bash
# Amend last commit
git add <files> && git commit --amend -m "type(scope): description"

# New commit
git add <files> && git commit -m "type(scope): description"
```

Stage only the files relevant to the commit message. Never `git add -A` blindly.

## Examples

```bash
# New feature
git add apps/web/src/resume-editor/Form.tsx
git commit -m "feat(resume-editor): add work experience form section"

# Bug fix, same scope as last commit → amend
git add apps/web/src/auth/login.ts
git commit --amend -m "fix(auth): handle expired token redirect"

# Chore
git add package.json pnpm-lock.yaml
git commit -m "chore(deps): bump next to 14.2"
```

## Edge cases

- **No staged files**: run `git add` for relevant files first, ask user if unclear which files
- **Merge conflicts**: warn, do not proceed
- **Empty commit**: abort, nothing to commit
- **Amend on pushed commit**: warn that force push will be needed
