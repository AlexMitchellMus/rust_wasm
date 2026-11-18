# Stage A results

Date: 2026-11-18. Host: macOS arm64 (Apple silicon), 14 CPUs, 48 GB RAM.
Rust: `nightly-2026-10-19` (1.101.0-nightly, `b6eeb93c9`), isolated under
`toolchain/`. All timings are median of three warm runs except "cold", which is
one build in a fresh target directory. Sizes are bytes of the linked `.wasm`.
Every artifact below was validated with `wasmparser 0.263` (all features) and
executed by Wasmtime 50.0.2.

## Verdict

| Program | What it proves | Result |
|---|---|---|
| (a) `a_add` | `no_std`, pure-Rust core, exported `add(i32,i32)` | **PASS** `add(20,22)=42` |
| (b) `b_alloc` | `no_std`+`alloc`: `Vec`, `String`, `format!`, closures, trait objects, f64/`libm` | **PASS**, `bench` runs and returns finite results |
| (c) `c_plugin` | NodeCraft plugin: `wasm_import_module = "nodecraft"`, f64 parameter list, allocation, result through memory, `panic=abort` | **PASS**, import appears as `nodecraft::host_bias`, `eval` returns `2.25` for params 1,2,3,4 |
| (d) `d_hello_std` | `std` on `wasm32-wasip1`, LLVM comparison | **PASS**, prints `hello from std wasm; sum=14` |

Strict builds (`CG_CLIF_WASM_STRICT=1`, which turns clif-to-wasm "stub with a
trap" into an error) pass for (a), (b) and (c). No function was replaced by a
trap in these programs, including `core`, `alloc`, `compiler_builtins` and
`libm` compiled by cg_clif.

## Compile + link time and size (O2)

`clif-lld` uses the **pure-Rust sysroot** built by `-Zbuild-std` with cg_clif.
Its "cold" column includes building `core`, `alloc` and `compiler_builtins`
(that is the ~6 s). Once built, the warm column is a normal plugin rebuild.
`clif-prebuilt` is the same backend against rustup's **LLVM-built** sysroot,
which tests ABI interoperability, not the pure-Rust shipping path.

| program | config | cold s | warm s | bytes | LLVM O2 warm s | LLVM O2 bytes |
|---|---|---:|---:|---:|---:|---:|
| a_add | clif-lld (pure sysroot) | 6.366 | 0.127 | 236 | 0.074 | 306 |
| b_alloc | clif-lld (pure sysroot) | 7.056 | 0.153 | 89,739 | 0.117 | 18,920 |
| c_plugin | clif-lld (pure sysroot) | 6.855 | 0.145 | 34,502 | 0.100 | 7,274 |
| a_add | clif-prebuilt (LLVM std) | 0.166 | 0.075 | 236 | — | — |
| b_alloc | clif-prebuilt (LLVM std) | 1.070 | 0.100 | 60,741 | — | — |
| c_plugin | clif-prebuilt (LLVM std) | 0.184 | 0.089 | 18,225 | — | — |

The pure-Rust `core` + `alloc` + `compiler_builtins` rlibs total **1.8 MB**
(873 KB + 195 KB + 765 KB), versus 7.6 MB for rustup's LLVM-built set. The 6–7 s
cold number is paid once when producing the shipped sysroot; plugin builds after
that are 0.13–0.15 s. Against the 0.41 s target, **warm compile+link is already
under the target by ~3×**.

Why the pure-Rust build is larger: object granularity. cg_clif's wasm objects
appear not to be split as finely as LLVM's, so `--gc-sections` retains more of
each CGU. The same plugin is 34.5 KB with the pure sysroot and 18.2 KB against
the LLVM sysroot; both are small enough to ship.

## Opt-level 0 vs 2

| program | backend | cold s | warm s | bytes | notes |
|---|---|---:|---:|---:|---|
| a_add | clif O0 | 0.170 | 0.074 | 304 | |
| b_alloc | clif O0 | 1.344 | 0.100 | 80,026 | |
| c_plugin | clif O0 | 0.179 | 0.086 | 25,299 | |
| a_add | LLVM O0 | 0.166 | 0.073 | 307 | |
| b_alloc | LLVM O0 | 0.746 | 0.100 | 60,221 | |
| c_plugin | LLVM O0 | 0.169 | 0.091 | 16,442 | |

The O0 cg_clif numbers use rustup's prebuilt (LLVM, O2) sysroot. Building the
sysroot itself at O0 fails; see blockers.

## Runtime in Wasmtime

`b_alloc::bench(n)` is a dependent f64 loop with `sqrt` + `sin`, a trait-object
dispatch per iteration and a 64-element `Vec`; n = 2,000,000, median of 3 calls.

| binary | ns/iteration |
|---|---:|
| cg_clif O2, rust-lld | 98.19 |
| cg_clif O2, wild | 98.62 |
| LLVM O2, rust-lld | 25.28 |
| LLVM O2, wild | 24.93 |
| cg_clif O0 | 238.87 |
| LLVM O0 | 206.51 |

At O2 cg_clif is **3.9× slower** than LLVM on this benchmark; at O0 it is 1.16×
slower. The plugin host-call path itself is ~1.5 µs per `eval` (dominated by the
Wasmtime store/instance and call boundary), versus ~2 µs for the LLVM build —
not meaningfully different at that scale.

## Wild vs rust-lld

Wild 0.11.0 (`fd79578`) links all three cg_clif programs with
`-C linker-flavor=wasm-ld`, and the resulting modules validate and run with
identical outputs. It is a drop-in replacement for this pipeline.

One concrete difference: **Wild emits `.bss` as literal data**. Our 1 MiB heap
is zero-initialized static memory; rust-lld represents it in the memory's initial
size (no file bytes), while Wild writes a ~1 MiB data segment:

| program | rust-lld bytes | wild bytes | delta |
|---|---:|---:|---:|
| a_add | 236 | 267 | +31 |
| b_alloc | 89,739 | 1,139,729 | +1,049,990 |
| c_plugin | 34,502 | 1,083,560 | +1,049,058 |

The code sections are the same size; only `DATA` differs. For plugin distribution,
either keep rust-lld (which is allowed as the comparison/reference linker) or move
the plugin heap out of `.bss` (host-allocated / `__heap_base` plus a fixed initial
memory). This is a Wild behavior to track, not a codegen bug.

## (d) std / wasm32-wasip1

Built by LLVM with rustup's prebuilt std, **95,055 bytes**, first build ~0.32 s,
runs under Wasmtime's WASI preview-1 host. Rust's `wasm32-wasip1` std links
prebuilt `crt1-command.o` and `libc.a` from the rustup `self-contained/`
directory (no wasi-sdk was installed). That C code is exactly what the plugin path
avoids: (a)–(c) are `no_std` + `alloc`, have no WASI imports, and only import the
explicit `nodecraft` host function.

**std is not needed for these plugins.** (b) covers the containers, formatting,
closures, traits and f64 maths a maths/geometry plugin needs; (c) covers the host
boundary. A plugin that truly needs files/network/clock would violate the
determinism requirement anyway.

## What clif-to-wasm rejected or struggled with

1. **`memory.size` / `memory.grow` intrinsics.** cg_clif emits
   `llvm.wasm.memory.size.i32` / `grow.i32` for
   `core::arch::wasm32::{memory_size, memory_grow}`; clif-to-wasm replaces them
   with trap stubs and warns. A growable heap is therefore unusable. Workaround:
   a fixed `.bss` heap (used here) or a host-managed heap. This is the main
   practical limitation found.
2. **f128 soft-float at O0.** Building `compiler_builtins` with `opt-level=0`
   fails with a libcall signature conflict:
   `__floatsitf` declared once as `(i32) -> f128` and once as
   `(i32 sret, i32) -> ()`. clif-to-wasm does not support f128. At O2 the
   offending functions are eliminated and the build succeeds. Consequence: build
   the shipped sysroot at O2; plugins themselves can be O0 against it (verified).
3. **Atomics.** An `AtomicUsize` allocator counter lowered to wasm atomic
   instructions while the module did not declare the `atomics` feature; Wasmtime
   refused to compile it. Plugins are single-threaded per instance, so a plain
   `UnsafeCell` counter is sufficient and removes the issue. Atomics/threads were
   not otherwise exercised; `wasm32-wasip1-threads` is untested here.
4. **No debug info.** cg_clif's wasm objects carry no DWARF (the native path still
   does). Panic messages are gone with `panic=abort` anyway.

Not hit: i128 `mulhi`, f128 arithmetic in user code, vector big-endian ops,
`try_call`, dynamic stack slots, `get_return_address`.

## Linker/validation details

* Every artifact passes `wasmparser::Validator` with all features enabled.
* Module exports `memory`, `wasm_alloc`, and the program's exports; (c) imports
  exactly `nodecraft::host_bias (f64) -> f64`. No WASI imports.
* `wasm_opt` was not run. It would reduce size further but is another LLVM tool;
  not part of the pure-Rust path.

## Stage B feasibility (rustc.wasm with no LLVM codegen)

**High, and already demonstrated by the project this patch comes from**, not just
inferred from stage A:

* The playground at `ryancbuckley/rust-playground-inbrowser` builds `rustc.wasm`
  for `wasm32-wasip1-threads` from the same cg_clif patch series and the same
  nightly, statically linking cg_clif + clif-to-wasm, and runs it under a WASI
  kernel. It reports a ~98 MB `rustc.wasm` (23 MB gzipped), ~0.3 s for a hello
  program, and 2,640/2,650 differential tests passing against LLVM.
* Stage A confirms the backend is not tied to WASI: the same patched cg_clif
  produces clean `wasm32-unknown-unknown` objects. Inside rustc.wasm the target
  is just a flag.
* **What must ship:** `rustc.wasm` (LLVM is used once to build rustc itself, not
  to compile plugins), the patched cg_clif statically linked (codegen backends
  cannot be dlopen'd inside wasm), the 1.8 MB pure-Rust plugin sysroot, the
  prebuilt SDK rlib, and Wild. Rustc.wasm can call Wild through a host import
  (`playground.spawn`) as the playground does, or the host can link the emitted
  `.o` files natively with the 13 MB Wild binary.
* **Threads:** rustc.wasm uses wasi-threads for its own parallelism; Wasmtime on
  desktop supports this without browser COOP/COEP constraints. A single-threaded
  build is possible if it simplifies the host, at a compile-time cost.
* **Proc macros:** plugins must not need them. Our SDK is a prebuilt rlib with
  pregenerated bindings, matching the plan. If a dependency insists on a proc
  macro, the playground has a wasmi-based `-Zwasm-proc-macros` escape hatch, but
  it is complexity we should avoid.
* **Sysroot determinism:** rlibs must match the exact rustc nightly and the
  cg_clif backend revision; ship them as one versioned bundle. Build them O2.
  The O0 f128 failure means do not let a user opt-level leak into the sysroot
  build.
* **Latency:** native warm plugin compile is 0.13–0.15 s. Even allowing 2–3× for
  rustc.wasm, this is at or under the 0.41 s LLVM-rustc.wasm baseline. This is the
  number stage B must measure on the real rustc.wasm.
* **Memory:** the playground budgets 384 MB for rustc.wasm. Desktop-only stage B
  is fine; a browser-hosted compiler needs that budget and threads.

Stage B risks are integration (WASI syscalls, spawn/linker plumbing, rustc's
thread usage, packaging size), not codegen. Stage A removes the codegen unknown.

## Stage C notes (NodeCraft)

The raw ABI proven by (c) is enough for a first integration:

```
wasm_alloc(size, align) -> ptr
eval(params_ptr: *const f64, len: usize, out_ptr: *mut f64) -> i32
import nodecraft::host_bias(f64) -> f64
```

* One `Store`/instance per evaluation or per worker, memory limit sized to the
  plugin's heap; epoch/fuel interruption; no WASI imports at all.
* `panic=abort` becomes a wasm trap; Wasmtime returns it as an error, so the host
  keeps the last good plugin and reports a node error.
* Determinism: the only imports are explicit host functions; no clock, files,
  network or unseeded RNG. Time and seeds are parameters, as the plan requires.
* WIT/components can come later: wrap this core module host-side, or regenerate
  the SDK bindings with `wit-bindgen` at SDK build time. Nothing in stage A
  depends on proc macros at plugin compile time.
* Hot reload: cache by BLAKE3(source + SDK + compiler revision), compile on a
  dedicated thread, swap the `InstancePre`; do not re-enter the kernel pool from
  host functions.

---

# Stage B results (rustc.wasm with cg_clif only)

Date: 2026-11-18. Host: macOS arm64 (Apple silicon), 14 CPUs, 48 GB RAM.
Isolated rustup/cargo under `toolchain/`. The compiler source is
`rust-lang/rust@b6eeb93c992027a03e1fd120b6652546396b142c` with the
`ryancbuckley/rust-playground-inbrowser@f529863` patch series (23 patches).
Details and reproduce steps: [`stage-b/README.md`](stage-b/README.md).

## Verdict

| Check | Result |
|---|---|
| rustc.wasm builds for `wasm32-wasip1-threads` with `codegen-backends=["cranelift"]` | **PASS** |
| No LLVM codegen inside rustc.wasm (imports/symbols/sections) | **PASS** (0 LLVM imports, 0 `rustc_codegen_llvm`/`rustc_llvm` symbols) |
| Wasmtime runs rustc.wasm, including its `wasi.thread-spawn` compiler thread | **PASS** (Wasmtime 46.0.3) |
| rustc.wasm compiles stage A plugin (c) to a relocatable wasm object | **PASS** |
| Native Wild links it through the `playground.spawn` host import | **PASS**, 23 args, exit 0 |
| Plugin loads in Wasmtime; `eval(1,2,3,4)` | **PASS**, `2.25` |
| Warm edit-to-result well under 1 s | **PASS**, **98.1 ms** in a hot host; **~0.74 s** CLI with warm module cache |

## Build

| Item | Value |
|---|---|
| `./x.py install` | 580.9 s wall (9m41s), x.py reported 9m08s; +31 s for the stage1 library |
| toolchain disk | **12 GB** (source+build 10 GB, build 6.6 GB, artifacts/sysroots/cache ~1 GB) |
| rustc.wasm | **143,715,574 B** (137 MiB), SHA-256 `88d30a79…b734f089` |
| rustc.wasm imports | 26 WASI p1 + `env.memory` + `playground.spawn` + `wasi.thread-spawn` |
| rustc.wasm exports | `memory`, `_start`, `wasi_thread_start` |
| rustc.wasm module compile (cold, no cache) | **39,649.97 ms** median [39,547.03–40,148.85] |
| rustc.wasm module load (Wasmtime cache hit) | **557.54 ms** median [556.58–561.48] |

Wasmtime 50.0.2 was the intended "latest" host, but it removed
`wasi-threads` in 47.0.0 and rustc always runs compilation on a spawned thread.
Stage B pins **Wasmtime 46.0.3**, the last release with
`wasmtime-wasi-threads`; the compiler itself is unmodified. See
[`stage-b/research-wasmtime.md`](stage-b/research-wasmtime.md).

## Warm edit-to-result (median of 5)

Stage A's plugin (c) source gets a real one-line `TWEAK` edit each run; the
result stays 2.25. "Module resident" keeps one Wasmtime engine + compiled
rustc.wasm and instantiates a fresh rustc per edit, as a hot-reload host would.
The CLI number is the whole process wall time with a warm Wasmtime module cache.

| Phase | Median | Min–max |
|---|---:|---:|
| instantiate rustc.wasm | **0.79 ms** | 0.77–1.12 |
| compile inside rustc.wasm (frontend + cg_clif + clif-to-wasm) | **85.36 ms** | 83.43–110.84 |
| link with native Wild (host `playground.spawn`) | **5.36 ms** | 5.11–6.50 |
| load linked plugin (1,066,803 B) | **6.97 ms** | 6.81–7.46 |
| `eval(1,2,3,4)` call | **~0.001 ms** | — |
| **edit-to-result, module resident** | **98.05 ms** | 96.4–125.6 |
| **CLI warm run (cache hit)** | **~0.74 s wall** | — |

Raw data: [`stage-b/results/stage-b.json`](stage-b/results/stage-b.json).

## No LLVM inside rustc.wasm

Generated by `stage-b-host inspect --wasm rustc.wasm` plus `strings`; raw output is [`stage-b/results/rustc-inspect.json`](stage-b/results/rustc-inspect.json).

| Probe | Count |
|---|---:|
| LLVM imports (module/name contains `llvm`) | **0** |
| LLVM exports | **0** |
| function names containing `rustc_codegen_llvm` | **0** |
| function names containing `rustc_llvm` | **0** |
| function names containing uppercase `LLVM` | **0** |
| `LLVMInitialize` / `LLVMRust` / `LLVMContext` strings | **0** |
| `libLLVM` string | 1 (linker search-path table, not code) |

The 129 function names containing `llvm` are cg_clif's
`rustc_codegen_cranelift::intrinsics::llvm_aarch64::…` helpers, i.e. Cranelift
lowerings of LLVM-named intrinsics, not the LLVM library. `rustc_llvm` and
`rustc_codegen_llvm` are not linked.

## Plugin sysroots

| sysroot | core / alloc / compiler_builtins | accepted by rustc.wasm? | plugin result |
|---|---|---|---|
| `sysroot-pure` (Stage A cg_clif, rustup nightly) | cg_clif / cg_clif / cg_clif | **No**, E0514: `1.101.0-nightly` vs `1.101.0-dev` | — |
| `sysroot-stage1` (native stage1 from the rustc.wasm build) | LLVM / LLVM / LLVM | **Yes**, exact version | **2.25** |
| `sysroot-wasm-hybrid` (rustc.wasm core+alloc, stage1 compiler_builtins) | **cg_clif / cg_clif** / LLVM | **Yes** | **2.25** (compile 133.6 ms, link 29.5 ms, e2e 144.5 ms) |

The hybrid sysroot is the self-hosting proof: **rustc.wasm built `core`
(856 KiB) and `alloc` (195 KiB) with cg_clif**, then `alloc` was rebuilt against
a `compiler_builtins` built by the native stage1 LLVM compiler against
rustc.wasm's core metadata. Building `compiler_builtins` with rustc.wasm fails
on the known f128 libcall conflict (`__multf3`/`__subtf3` declared both
f128-return and sret). The plugin path therefore still contains LLVM-generated
`compiler_builtins`, but no LLVM code generator is in rustc.wasm.

## Stage A.2: realistic plugins on the native Stage A toolchain

Date: 2026-11-18. Medians of 5 warm runs. Both plugins are `no_std`+`alloc`,
1 MiB `.bss` heap, linked with Wild for cg_clif and rust-lld for LLVM.
(e) 100k f64 points: `sin`, `cos`, `sqrt`, reduce. (f) 40k iterations × 5
imported host calls = 200,000 calls. Full report:
[`stage-b/a2/RESULTS.md`](stage-b/a2/RESULTS.md); raw:
[`stage-b/results/a2.json`](stage-b/results/a2.json).

| program / metric | LLVM O2 | cg_clif O2 | cg_clif / LLVM |
|---|---:|---:|---:|
| (e) warm compile+link | 0.100 s | 0.131 s | **1.30×** |
| (e) Wasmtime module load | 6.77 ms | 17.18 ms | **2.54×** |
| (e) run 100k points | 2.30 ms / 23.0 ns·pt | 8.78 ms / 87.8 ns·pt | **3.82×** |
| (e) code size | 13,173 B | 39,709 B | **3.01×** |
| (f) warm compile+link | 0.090 s | 0.129 s | **1.44×** |
| (f) Wasmtime module load | 4.08 ms | 10.15 ms | **2.49×** |
| (f) run 200k host calls | 0.622 ms / 3.11 ns·call | 0.570 ms / 2.85 ns·call | **0.92×** |
| (f) code size | 4,638 B | 21,679 B | **4.67×** |

MIR inlining:

* `-Zinline-mir -Zmir-opt-level=3` (the requested config) **fails** building
  `compiler_builtins` on the f128 (`__floatsitf`) signature conflict.
* `-Zinline-mir -Zmir-opt-level=4` builds but saves only **79 B** (e) / **207 B**
  (f) of code and changes run time by <2%.
* `-Zinline-mir` alone at MIR opt level 2 is **byte-identical** to the default.
* `-Zinline-mir=no -Zmir-opt-level=2` also fails (`__umodti3` i128 ABI), so
  default `clif_o2` is the meaningful MIR-disabled baseline.

Interpretation: plugin compile is 1.3–1.4× LLVM (still well under the 0.41 s
target); Wasmtime load is ~2.5×; maths throughput is 3.8× slower with cg_clif,
while host-call-heavy geometry is at parity because the host boundary dominates.
Total artifact size is inflated by Wild's 1 MiB `.bss` data segment; code size
is 3–4.7× LLVM's.

## What is still not Rust

1. **Build-time LLVM**: stage0's LLVM backend builds the native stage1 rustc;
   the stage1 rustc builds rustc.wasm and (for the main path) the plugin
   sysroot. LLVM is not inside rustc.wasm.
2. **`compiler_builtins` in the hybrid sysroot** is LLVM-generated (core/alloc
   are cg_clif). The main `run.sh` path uses the fully stage1-built sysroot for
   reproducibility and version matching.
3. **Wasmtime** is Rust with C pieces (signals/unwinding). Wild, cg_clif and
   clif-to-wasm are pure Rust.
4. **No DWARF** in cg_clif wasm objects; `panic=abort`.

## Blockers and stage C recommendation

* Wasmtime ≥47 cannot run unmodified rustc.wasm (wasi-threads removed). Pin
  46.0.3, or patch rustc to run the compiler on the main thread and use latest
  Wasmtime. The latter is a small compiler patch but a larger semantic change.
* Cold module compile is ~40 s at 137 MiB. Ship a precompiled `.cwasm` / browser
  cache; 98 ms is the edit budget once resident.
* Sysroot version lock: rustc.wasm's `1.101.0-dev` rejects a rustup-nightly
  `1.101.0-nightly` sysroot. Ship rustc.wasm + sysroot + Wild + host as one
  versioned bundle, or build the sysroot with rustc.wasm itself.
* f128 is still unsupported by clif-to-wasm and blocks a fully cg_clif-built
  `compiler_builtins`.
* Wild materialises the 1 MiB `.bss` heap; move the plugin heap out of `.bss`
  (host-allocated or `__heap_base` + fixed initial memory) before shipping.
* cg_clif maths throughput is 3.8× slower than LLVM; host-call-heavy code is at
  parity. For NodeCraft, start with the raw ABI (stage A/B), keep rustc.wasm
  resident, cache the compiled module, and keep LLVM out of the plugin codegen
  path. Only revisit a pure-Rust optimizing backend if maths-heavy nodes become
  the bottleneck.
* Retire the LLVM-inside-wasm path for plugin codegen now. Keep LLVM only for
  the build-time stage1/sysroot until a self-hosting stage2 exists; the hybrid
  sysroot shows the next concrete step (rustc.wasm building core/alloc), with
  compiler_builtins/f128 as the remaining piece.
