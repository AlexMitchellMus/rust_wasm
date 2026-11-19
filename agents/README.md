# agents/

Everything a contributor (human or AI agent) needs, in one place. Start with
[`../AGENTS.md`](../AGENTS.md).

| File | What it's for |
| --- | --- |
| [`ROADMAP.md`](ROADMAP.md) | The four goals and every open item, with how we'll know each is done |
| [`GUIDELINES.md`](GUIDELINES.md) | Conventions: root-cause fixes, Rust style, nesting ≤ 5, lints, errors, `unsafe`, performance, tests, CI, commits, patches; review checklist |
| [`skills/vectorisation.md`](skills/vectorisation.md) | Writing loops that vectorise, explicit wasm `simd128`, checking it worked |
| [`skills/measuring-performance.md`](skills/measuring-performance.md) | Getting numbers that mean something; our benchmarks and where results go |
| [`skills/anti-pattern-review.md`](skills/anti-pattern-review.md) | The review scan, the project rules, and the manual anti-pattern list |
| [`scripts/review-scan.sh`](scripts/review-scan.sh) | Runs the scan (ast-grep rules, cargo fmt, clippy, shellcheck, ruff); `--changed`, `--strict` |
| [`scripts/rule-fixtures/`](scripts/rule-fixtures/) | Known good and bad examples the scan uses to prove its rules still match |

Related files at the repository root: [`clippy.toml`](../clippy.toml) (nesting,
function length and argument thresholds), [`sgconfig.yml`](../sgconfig.yml) and
[`ast-grep/rules/`](../ast-grep/rules/) (project rules), and
[`.github/workflows/quality.yml`](../.github/workflows/quality.yml) (the scan in CI).
