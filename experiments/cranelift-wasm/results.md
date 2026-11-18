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
