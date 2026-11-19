# Skill: anti-pattern review

Run the scan, then read the change against the list below. The scan catches
what a tool can; the list catches what it can't.

## 1. Run the scan

```bash
agents/scripts/review-scan.sh            # everything we own
agents/scripts/review-scan.sh --changed  # only files changed against origin/main
```

It runs, skipping (and saying so) any tool that isn't installed:

| Check | Catches |
| --- | --- |
| `cargo fmt --check` | Formatting drift |
| `cargo clippy` with our lint set ([`clippy.toml`](../../clippy.toml): nesting ≤ 5, functions ≤ ~100 lines, ≤ 7 arguments; pedantic lints; `unwrap_used`, `dbg_macro`, `todo`, `undocumented_unsafe_blocks`) | Style and correctness smells, deep nesting, long functions, undocumented `unsafe` |
| `ast-grep scan` ([`ast-grep/rules/`](../../ast-grep/rules/)) | Project-specific anti-patterns (below) |
| `shellcheck` | Shell script bugs (unquoted expansions, unset variables) |
| `ruff check` | Python script problems |

The scan covers our own code. Patch files and upstream checkouts follow their
project's rules and are excluded.

### Project rules (ast-grep)

| Rule | Severity | Why |
| --- | --- | --- |
| `no-todo-in-code` | error | `todo!()` / `unimplemented!()` must not be committed |
| `no-dbg-macro` | error | Debug output left in |
| `no-sleep-to-fix-ordering` | warning | Timing delays hide ordering bugs; fix the order |
| `no-process-exit-in-library` | warning | Libraries return errors; only `main` decides to exit |
| `allow-needs-expect` | warning | Use `#[expect(lint, reason = "...")]` so stale allows are caught |
| `no-ignored-tests` | warning | `#[ignore]` hides tests; justify in the reason or remove |

Add a rule when a review finds the same mistake twice. Each rule needs an `id`,
a `message`, a `note` explaining why, a `severity`, and `files`/`ignores`
scoped to our code. Check that a new pattern actually matches a known example
before trusting an empty result, and never hide ast-grep errors with
`2>/dev/null`: a pattern that fails to parse matches nothing and looks clean.

## 2. Read the change

Tools can't see these; reviewers must.

| Anti-pattern | Look for | Instead |
| --- | --- | --- |
| Symptom fix | A special case for one input, a magic constant, an offset that "makes it line up" | Find and fix the shared cause |
| Silent fallback | `unwrap_or_default()`, `ok()` or `let _ =` on something that can really fail | Return the error or report it clearly |
| Weakened test | Changed expectations, `#[ignore]`, `cfg` skips, deleted assertions in the same change as a fix | Fix the code; keep the test |
| CI accepting failure | Steps that grep logs for a known error and continue | Fix the cause |
| Unmeasured speed claim | "Faster" with no numbers | Median of 5, before/after |
| Unpinned input | `latest`, `main`, unversioned downloads, `cargo install` without a version | Pin exact versions/revisions |
| Unsafe without proof | `unsafe` with no `// SAFETY:` or no test | Explain and test it, or remove it |
| Deep nesting / long functions | More than 5 levels, functions past ~100 lines | Early returns, helpers |
| Duplicated logic | The same calculation in two places that must agree | One function, used by both |
| Per-platform forks | Separate scripts or code paths per OS doing the same job | One portable path; `cfg` only where the platform truly differs |
| Hidden global state | Statics/env vars that change behaviour silently | Pass configuration explicitly |
| Non-determinism | Clocks, unseeded randomness, hash-map iteration order in output | Explicit seeds and ordering |
| Unexplained code | Code the author can't explain (AI-generated or not) | Understand it or don't commit it |

## 3. Record what you found

Fix what's in scope. For anything else, open an issue or add an item to
[ROADMAP.md](../ROADMAP.md) under Quality work, with the file, the finding and
why it matters.
