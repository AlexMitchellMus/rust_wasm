# AGENTS.md

Orientation for anyone, human or AI agent, about to change this repository.
Read it before you start; it is short.

rust_wasm builds **rustc as a WebAssembly module that compiles Rust to
WebAssembly with no LLVM inside**. The goal and current status are in the
[README](README.md). Everything you need to contribute is in [`agents/`](agents/):

| Read | For |
| --- | --- |
| [`agents/ROADMAP.md`](agents/ROADMAP.md) | The goals still to complete, with acceptance criteria. Pick work from here. |
| [`agents/GUIDELINES.md`](agents/GUIDELINES.md) | Conventions every change must follow: code style, lints, nesting, errors, `unsafe`, tests, benchmarks, commits, patches. |
| [`agents/skills/`](agents/skills/) | How-tos: writing vectorisable code, running the anti-pattern review, measuring performance. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How we work with upstream projects (we don't send them changes yet) and how AI tools may be used. |

## Ground rules

1. **Fix the cause, not the symptom.** No special cases, magic offsets or
   timing delays to make a problem go away. Find the shared source and fix it
   there. See [GUIDELINES.md](agents/GUIDELINES.md#fix-root-causes).
2. **Prove it.** Every fix has a test that fails before it and passes after.
   Every speed claim has a measurement. Faster must never mean wrong: the
   differential tests (LLVM vs our pipeline) must stay green.
3. **Run the review scan** before you commit:
   `agents/scripts/review-scan.sh`. See
   [skills/anti-pattern-review.md](agents/skills/anti-pattern-review.md).
4. **Patches to upstream projects live here** as patch files, licensed as the
   project they modify. Nothing is sent upstream without a decision. See
   [CONTRIBUTING.md](CONTRIBUTING.md).
5. **A human owns every change** and can explain it. AI tools are welcome;
   unexplained code is not.
6. **Never** weaken, delete or ignore a test to make CI pass, and never make CI
   accept a failure by matching its message.
