# Roadmap

The aim: a Rust compiler that runs anywhere WebAssembly runs, starts
instantly, compiles the whole language, contains no LLVM, is built without
LLVM, and produces code that matches or beats LLVM where it matters.

Four goals. Each item says how we will know it is done. Pick an unclaimed item,
open an issue saying you are working on it, and follow
[GUIDELINES.md](GUIDELINES.md).

Status keys: **done**, **in progress**, **open**, **research** (needs
investigation before it can be planned).

## Already done

| | |
| --- | --- |
| **done** | `rustc.wasm` with Cranelift as its only code generator, compiling a `no_std` + `alloc` program and linking it with Wild (stages A–C, [`experiments/cranelift-wasm/`](../experiments/cranelift-wasm/)) |
| **done** | Single-threaded compiler on plain WASI preview 1 and the latest Wasmtime |
| **done** | `core`, `alloc` and `compiler_builtins` built by `rustc.wasm` itself |
| **done** | Growable heap (`memory.grow` / `memory.size` in clif-to-wasm) |
| **done** | CI that builds and tests the whole pipeline and audits `rustc.wasm` for LLVM |
| **done** | Differential tests: the same programs built with LLVM and with our pipeline must produce identical output ([`difftest/`](../experiments/cranelift-wasm/difftest/)) |

## Goal 1 — Generated code as fast as LLVM, faster where it counts

Today: tight numeric loops run about 3.9× slower than LLVM `-O2` output; code
that mostly calls its host runs at parity. Both go through Wasmtime's Cranelift
to native code, so the gap is optimisation *before* wasm: inlining, loop
optimisation, scalar replacement, vectorisation.

| Status | Item | Done when |
| --- | --- | --- |
| **in progress** | First code-generation wins in clif-to-wasm (local allocation, stack shaping, fewer redundant loads/stores) | Measured improvement on the A.2 maths benchmark; difftest green |
| **open** | A benchmark suite against LLVM `-O0` and `-O2`, run in CI, results published | A table in the README updated by CI |
| **open** | Tier 2: a background optimising build (aggressive inlining, Cranelift e-graph at full strength, loop-invariant code motion, wasm-level clean-up), swapped in when ready | Within 1.5× of LLVM `-O2` on scalar benchmarks |
| **open** | Explicit SIMD (wasm `simd128`) supported end to end through clif-to-wasm, with SDK helpers | A `simd128` program in the difftest corpus; measured speed-up |
| **research** | Auto-vectorisation in tier 2 for simple loops | Matches LLVM on the vectorisable benchmarks |
| **research** | Profile-guided recompilation from live profiles | Measured win over the static tier-2 build |
| **research** | Specialisation of hot functions on runtime-constant inputs | Measured win, with a fallback when inputs change |
| **research** | Bulk maths offloaded to the GPU (host-compiled kernels via wgpu) | Beats LLVM-built wasm by an order of magnitude on large arrays |

## Goal 2 — Near-instant compiler start

Today: the first load compiles the 137 MB `rustc.wasm` to native code (about
40 s); later loads come from Wasmtime's cache in about 0.44 s.

| Status | Item | Done when |
| --- | --- | --- |
| **in progress** | Precompiled native `rustc.wasm` per host, with version checks and a fallback | First compile after install in well under 1 s |
| **in progress** | Incremental compilation kept across edits | One-line edits measurably faster than a cold compile |
| **open** | Snapshot an already-initialised compiler, so starting skips set-up; copy-on-write memory instantiation | Instantiation in about 10 ms |
| **open** | A smaller `rustc.wasm` (drop Clippy, rustfmt and unused targets from the build) | Size and load time measured before/after |
| **open** | A resident compiler service in the host (keep `rustc.wasm` loaded, reuse its caches) | Edit → result under 100 ms on a CI runner |

## Goal 3 — The whole language and ecosystem

| Status | Item | Done when |
| --- | --- | --- |
| **open** | Procedural macros: proc-macro crates compiled to wasm and run inside the compiler (host-provided Wasmtime instance, at native speed) | `serde`'s derive works |
| **open** | `std` for WASI preview 1 and 2, built by Cranelift | A `std` program in the difftest corpus |
| **open** | Multiple crates and dependencies: a small resolver in the host plus a cache of prebuilt popular crates | A program using several crates.io crates builds |
| **open** | Component model output (WIT, WASI 0.2) | A component runs in Wasmtime |
| **open** | Debug info: DWARF through the Cranelift backend, clif-to-wasm and Wild | Stack traces with source lines |
| **open** | Panics that unwind, via wasm exception handling | Unwinding tests pass |
| **open** | Threads: host-provided `thread-spawn` now, shared-everything-threads when it ships (see the README) | Parallel code generation measured |
| **open** | Versioned releases: `rustc.wasm`, matching standard library, Wild and third-party notices | A published, reproducible release |

## Goal 4 — No LLVM anywhere, not even to build

Today LLVM is used once at build time to compile rustc itself into
`rustc.wasm`, and `rustc.wasm`'s own `std` contains wasi-libc, which is C.

| Status | Item | Done when |
| --- | --- | --- |
| **research** | Self-hosting: `rustc.wasm` compiles rustc into `rustc.wasm` | A `rustc.wasm` built only by `rustc.wasm` passes CI and difftest |
| **research** | Replace wasi-libc in the compiler's `std` with Rust (or a `std` that targets WASI directly) | No C in the build |
| **open** | Reproducible builds: the same inputs give a byte-identical `rustc.wasm` | Two independent builds compare equal |

## Quality work (always open)

| Status | Item | Done when |
| --- | --- | --- |
| **open** | Make the review scan a blocking CI gate (fix existing findings first) | `quality.yml` fails on any finding |
| **open** | Fix the cause of the tolerated `generate-copyright` packaging failure | CI no longer matches a failure message |
| **open** | Run rustc's run-pass tests and rustc_codegen_cranelift's own tests through our pipeline | Pass rate published and tracked |
| **open** | Fuzzing with a random program generator in every CI run | Seeds and findings recorded |

## Good first tasks

- Add programs to the difftest corpus for areas it doesn't cover yet.
- Fix review-scan findings in one file at a time.
- Improve error messages in the host when compilation fails.
- Measure and document something nobody has measured yet.
