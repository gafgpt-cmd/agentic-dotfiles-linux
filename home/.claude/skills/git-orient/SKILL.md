---
name: git-orient
description: "Use before ANY git add/commit, especially when a change touches files outside the current project (dotfiles, sibling repos, $HOME config). Decides which repo a change belongs in, warns + offers before committing cross-repo (never silent), and applies git/GitHub good practice for an owner who does not drive git well."
---

# git-orient

Before any commit ask: **which repo does this change belong in?** Warn + offer. Never silent cross-repo.

## Sweep first — the cwd is NOT the owning repo
Working in a directory does not mean an edit lands in that directory's repo. The owner may edit a file owned by a DIFFERENT repo (symlink into dotfiles, nested repo, sibling checkout) without realizing. Establish the map; never assume.
- Per edited file: `git -C "$(dirname "$(readlink -f <file>)")" rev-parse --show-toplevel` → its TRUE owning repo. `readlink -f` FIRST — config is often a symlink into a dotfiles repo.
- Compare to the repo you assumed (cwd's `git rev-parse --show-toplevel`). Different → **WARN**: "`<file>` lives in `<repoA>`, not `<repoB>` where you're working" — then route it to `<repoA>`.
- Ambiguous or multi-location change → sweep the area: `find <root> -maxdepth 4 -type d -name .git -prune` (each hit's parent is a repo root). Nested repos and boundary-crossing symlinks are the traps.
- A file in NO repo (e.g. a real `~/.claude/...`, `~/AGENTS.md`) is **UNVERSIONED** — say so. Its real home is usually a dotfiles repo (deployed by nix / stow / bootstrap); author + commit it THERE, don't leave it loose or stuff it into the project you happen to be in.

## Which repo owns the change
- File under the current project root → current repo.
- `$HOME` dotfile / global config (`~/.zshenv`, `~/.gitconfig`, `~/.ssh/config`, editor/agent config) → the **dotfiles repo**. Run `readlink -f <file>` FIRST: a symlinked config resolves into a repo elsewhere; commit THERE with `git -C <that-repo>`, not at the symlink path.
- File under another project dir → that project's repo (`git -C <dir>`).
- One fix spanning repos → **split**: one self-contained commit per repo.
- Unsure → `git -C <dir> rev-parse --show-toplevel` finds the owner. File in no repo → say so, do not invent one.

## Warn + offer (the owner does not drive git well)
- Change belongs in a DIFFERENT repo than the current one → STOP. Say plainly: "this belongs in `<repo>`, not `<current>`."
- OFFER to commit it there, showing the exact message. Do NOT silently commit into another repo.
- Any cross-repo or `$HOME` write: name the exact repo + path + one-line message; wait for go UNLESS the owner already said "commit everything".
- After committing: report each repo touched and its new HEAD. Never assume; state it.

## Good practice, sized for a non-coder
- Stage NAMED files only. NEVER `git add -A` / `git add .` (sweeps secrets, scratch, unrelated themes). `git status` first, every time.
- One theme per commit. Message = what + WHY. No `Co-Authored-By`, no agent trailer.
- Regenerable/generated output → gitignore it, do not commit. Do not leave a file tracked AND ignored; untrack with `git rm --cached` (keeps the file on disk).
- NEVER push, force-push, `reset --hard`, rebase, or rewrite shared history without explicit owner go. Push is ALWAYS the owner's call.
- Do not bypass hooks (gitleaks, pre-commit) with `--no-verify`. A blocked commit is a finding to fix, not to force. A gitleaks false positive → a scoped `.gitleaksignore` entry, reviewed.
- Risky work on the default branch → branch first.
- Deletion: `send2trash`, never `rm` / `git rm` a file off disk. Untrack ≠ delete.
- Verify before commit: tests/lint green, no secrets, links resolve.

## The .zshenv lesson (why this skill exists)
Owner config is often a **symlink into a dotfiles repo**. Editing the symlink path writes the real file, but committing needs `git -C <dotfiles-repo>`. A fix that lands in `$HOME` almost never belongs in the project repo. Resolve the symlink, warn, offer — do not stuff it into the current repo or leave it dangling uncommitted.
