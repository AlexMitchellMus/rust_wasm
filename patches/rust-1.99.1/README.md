# rustc.wasm compiler patches — Rust 1.99.1

These are the compiler-side patches that let `rustc` itself be built for
`wasm32-wasip1-threads` and run under a WASI host. They used to live on
`oligamiq/rust@compile_rustc_for_wasm17`; this recipe repo now carries them so
no second `rust` fork is needed.

- **Upstream tag:** `rust-lang/rust` `1.99.1`
- **Base commit:** `58cf8f9c35b355199727627d07ae34a4e2846d67`
- **Patch series:** 5 commits, `0001` … `0005`, apply in order
- **Net diff against the base:** 15 files, +351 / −9

## How CI applies them

The workflow checks out `rust-lang/rust` at tag `1.99.1` **without**
submodules, runs

```sh
git am patches/rust-1.99.1/*.patch
```

with a throwaway committer identity, and only then initializes submodules
(`git submodule sync` + `git submodule update --init --recursive --depth 1`).
The ordering matters: patch 2 rewrites `.gitmodules` and the
`src/llvm-project` gitlink to the YoWASP LLVM fork, so initializing submodules
before the patches would fetch the wrong LLVM.

The script `ci/apply-rust-patches.sh` (in the recipe repo root) performs all of
this and exits non-zero if a patch does not apply or if the series does not have
exactly 5 files.

## Patches

| # | Original commit | Rebased commit | Subject | What it does |
|---|---|---|---|---|
| 0001 | `2af9f557993` | `3d08ef18932` | `[WIP] Support compiling rustc to WebAssembly` | Runs the compiler on the wasm main thread instead of spawning a thread; raises the wasm default stack to 32 MiB; uses pid 1 for ICE file names; does not build a linker `PATH` on wasm; cfg-gates the `libloading`/dlopen path behind a stub in `rustc_metadata`'s `host_dylib.rs`. Also `.gitignore` entries. |
| 0002 | `08ec940e111` | `9187905acb8` | `Compile rustc+LLVM to wasm` | The core build patch: WASI CMake block in `src/bootstrap/src/core/build_steps/llvm.rs` (`LLVM_ENABLE_THREADS`, `-pthread`, `-D_WASI_EMULATED_MMAN`, 4 GiB linker max memory, 1 MiB C++ stack), `rustc_llvm/build.rs` WASI flags, `config.llvm.toml` for a `wasm32-wasip1-threads` host, target-spec changes (shared memory, 1 GiB max memory, `-lwasi-emulated-mman`), `compile.rs` skip list, `libc++.a`. Rewrites `.gitmodules` / `src/llvm-project` to `YoWASP/llvm-project` branch `llvmorg-22.1.0+wasm` (`97196c8eeb1d495fa43bb8af2fb26af5ef5b89fb`). |
| 0003 | `bab49c215b1` | `66b874f9926` | `Link against lld for linking compiled object files` | In-process LLD instead of spawning a linker: new `LLD.cpp` (`RustRunLld` around `lld::lldMain`, ELF + wasm drivers), calls it from `rustc_codegen_ssa/src/back/link.rs`, compiles/links `lldCommon`/`lldELF`/`lldWasm`/`LLVMOption` in `rustc_llvm/build.rs`, enables the `lld` CMake project for the wasm-host LLVM. The C++ side is gated to wasi targets so a native `x.py check` does not need LLD headers. |
| 0004 | `315dd3f99d9` | `c8871cb8a52` | `Make linking for wasm32-wasip1 work by default` | Adds `-Clink-self-contained=no` for wasi in `src/bootstrap/src/core/builder/cargo.rs`; the remaining target-spec/config changes from the original commit were already upstream or landed in 0002. |
| 0005 | `f7a223c1c21` | `f5e1d56ab21` | `Disable rpath for lld when requested` | Sets `CMAKE_SKIP_RPATH=ON` when LLD is built without rpath, preserving 1.99.1's separate Linux/Darwin rpath branches. |

The original series had a sixth commit, `132c6388ad7` (`Update comment.txt`),
which only updated stale 1.83-era documentation and was dropped during the
rebase.

## Known risks

- **LLVM 22.1 vs rustc 1.99.1.** Rust 1.99.1 pins LLVM `rustc/23.1-2026-07-22`,
  but accepts LLVM ≥ 21 and has LLVM 22/23 guards. There is no
  `llvmorg-23.x+wasm` YoWASP fork, so this series pins `22.1.0+wasm`. This is
  the main untested combination.
- **wasi-sdk 34.** The recipe installs wasi-sdk 34 and rewrites the
  toolchain-generated config's `wasi-sdk-*` path to the extracted
  `rust/wasi-sdk`.
- **Main-thread stack.** The 32 MiB `DEFAULT_STACK_SIZE` only applies to a
  spawned rustc thread; on wasm the compiler runs on the main thread, whose
  stack is fixed at link time. Add `-Wl,-z,stack-size=N` if rustc overflows.

## Regenerating

From a `rust` clone containing the rebased branch:

```sh
git format-patch --no-signature --numbered -o ../rust_wasm/patches/rust-1.99.1 \
  1.99.1..compile_rustc_for_wasm-1.99.1
```

Keep the file numbering; `ci/apply-rust-patches.sh` applies them sorted and
fails if the count is not 5.
