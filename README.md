# rust_wasm
A repository for Rust compiler binaries compiled to WebAssembly.

## Overview
This project builds and distributes the Rust compiler and LLVM tools compiled to WebAssembly.

## Upstream Sources
- **rustc_llvm**: [rust-lang/rust](https://github.com/rust-lang/rust) `1.99.1` plus the
  compiler patches in [`patches/rust-1.99.1/`](patches/rust-1.99.1/). There is no
  separate `rust` fork: CI checks out the upstream tag, applies the patch series
  with `git am`, then initializes submodules.
- **clang, wasm-ld, etc**: [YoWASP/clang](https://github.com/YoWASP/clang)

## Dependencies
- [toolchain-for-building-rustc](https://github.com/oligamiq/toolchain-for-building-rustc): Prebuilt toolchain for building rustc.

## Platform Support
This project targets Tier 1 and Tier 2 host platforms. See [Rust Platform Support](https://doc.rust-lang.org/nightly/rustc/platform-support.html) for details.

## CI

- [`cranelift_wasm.yml`](.github/workflows/cranelift_wasm.yml) is the primary
  path. It runs on pushes to `main` that touch
  `experiments/cranelift-wasm/**` or the workflow itself, plus
  `workflow_dispatch`. It builds the pure-Rust `rustc.wasm`
  (`wasm32-wasip1`, Cranelift/cg_clif only), builds the plugin sysroot with
  `rustc.wasm` itself, runs plugin (c) end to end on Wasmtime 50.0.2 and
  asserts `eval(1,2,3,4) == 2.25`, checks A.2 (e)/(f) correctness, and audits
  `rustc.wasm` for LLVM imports/symbols. The full build log is published to the
  [`ci-logs` release](https://github.com/AlexMitchellMus/rust_wasm/releases/tag/ci-logs);
  `rustc.wasm` and the pure sysroot are workflow artifacts kept for 7 days.
  The same logic runs locally:
  `experiments/cranelift-wasm/ci/build-and-test.sh`. The first green run
  (2026-11-18) took 45m21s on a 4-core `ubuntu-latest`; sizes, disk/cache use
  and the macOS/Linux differences are recorded in
  [`experiments/cranelift-wasm/README.md`](experiments/cranelift-wasm/README.md#ci).
- [`rustc_llvm_with_lld.yml`](.github/workflows/rustc_llvm_with_lld.yml) builds
  the LLVM/LLD-based compiler and dist jobs. It is **manual only**
  (`workflow_dispatch`) and no longer runs on push.

## 🚀 Release Process

To prevent repository bloat, we no longer commit binaries to Git. Instead, we use **GitHub Actions Artifacts** and **GitHub Releases**.

### Step 1: Build Artifacts
Generate the binaries by running the following workflows via the GitHub Actions UI (or `gh` CLI).

1. **Build LLVM**: Builds the WASM versions of LLVM/Clang tools.
2. **rustc_llvm_with_lld**: Builds the Rust compiler for the supported host platforms.
   - Run this workflow for each `job` input: `install`, `dist-linux`, `dist-macos`, `dist-windows`.

**Verification**: After each job completes, verify that the artifacts are uploaded in the "Artifacts" section at the bottom of the run details page.

### Step 2: Create Release
Once all builds (LLVM and Rust for each OS) are successful, create a release.

1. Run the **create release** workflow.
2. Provide the tag name (e.g., `v0.2.0`) in the `version` input.
3. **Automated Processes**:
   - Automatically downloads the latest artifacts from the most recent successful builds.
   - Packages them for distribution (`.tar.gz`, `.br`).
   - Uploads them directly to the **GitHub Releases** page.

### 🌐 Hosting & Download URLs
- Assets from GitHub Releases are automatically deployed and hosted on both **Cloudflare Pages** and **GitHub Pages**.
- **Cloudflare Pages Base URL**: `https://rustwasm0.pages.dev/`
- **GitHub Pages Base URL**: `https://oligamiq.github.io/rust_wasm/`
- **Path Format**: `/<version>/<filename>` (where `<version>` is the tag name without the `-release` suffix).

**Download Examples (for `v3.0.0`)**:
- Linux dist: 
  - Cloudflare: `https://rustwasm0.pages.dev/v3.0.0/x86_64-unknown-linux-gnu.tar.gz`
  - GitHub Pages: `https://oligamiq.github.io/rust_wasm/v3.0.0/x86_64-unknown-linux-gnu.tar.gz`
- Rust source: 
  - Cloudflare: `https://rustwasm0.pages.dev/v3.0.0/rust-src.tar.gz`
  - GitHub Pages: `https://oligamiq.github.io/rust_wasm/v3.0.0/rust-src.tar.gz`
- Brotli compressed LLVM binaries: 
  - Cloudflare: `https://rustwasm0.pages.dev/v3.0.0/llvm_opt.wasm.br`
  - GitHub Pages: `https://oligamiq.github.io/rust_wasm/v3.0.0/llvm_opt.wasm.br`

*Note: On Cloudflare Pages, files larger than 20MB are automatically split (`.part00`, `.part01`...) to bypass file size limits. Use the included `split_manifest.json` (e.g., `https://rustwasm0.pages.dev/v3.0.0/split_manifest.json`) to restore the original files. GitHub Pages hosts the complete, undivided files.*

## About `rustc_unwind.wasm`

The `rustc_unwind.wasm` file indicates that the compiler itself was built with `panic=unwind`. It does not automatically make generated programs use unwinding. The panic strategy of generated programs is still controlled by the selected sysroot and `-C panic`.

For normal target programs, use:
- `rustc.wasm` or `rustc_unwind.wasm`
- `sysroot-abort`
- `-C panic=abort`

Using `-C panic=unwind` requires a separate unwind-enabled sysroot and runtime support for WebAssembly exception handling.

## 🧹 Legacy Cleanup
The following branches previously used to store binaries are now deprecated. After confirming that the new release process distributes files correctly, please delete these branches to reduce repository size:

- `rustc_llvm_with_lld-bins`
- `rustc_llvm_with_lld-bins-tier2-host`
- `rustc_llvm_with_lld-bins-tier2-host-windows`
- `rustc_llvm_with_lld-bins-tier2-host-mac`
- `llvm-tools`
- `gh-pages` (if used only for binary distribution)

## References
- [Miri issue #722](https://github.com/rust-lang/miri/issues/722)
- [LLVM Discourse RFC](https://discourse.llvm.org/t/rfc-building-llvm-for-webassembly/79073/37)
- [rubri](https://github.com/LyonSyonII/rubri)

## License

Unless otherwise noted, the original source code, build scripts, configuration
files, and documentation in this repository are licensed under either of

- [MIT License](LICENSE-MIT)
- [Apache License, Version 2.0](LICENSE-APACHE)

at your option.

The build scripts (`build-netbsd-toolchain.sh`, `build-solaris-toolchain.sh`,
`crosstool-ng-build.sh`, `musl-toolchain.sh`, and `musl.sh`) and the
`*.defconfig` files include code copied or adapted from the
[Rust project's CI build infrastructure](https://github.com/rust-lang/rust/tree/46e8d20301cb4abe91ab0a4bea43bb085e1d4e4a/src/ci/docker).
Upstream copyrights are retained by the Rust contributors. Those portions remain
subject to Rust's [license terms and copyright notices](https://github.com/rust-lang/rust/blob/46e8d20301cb4abe91ab0a4bea43bb085e1d4e4a/COPYRIGHT).

Third-party code and distributed artifacts remain subject to their respective
licenses and copyright notices. The licenses of this repository do not relicense
those components. They include:

| Component | License |
| --- | --- |
| [Rust](https://github.com/rust-lang/rust) (rustc, the standard library, `rustc_codegen_cranelift`) | MIT OR Apache-2.0 |
| [Cranelift](https://github.com/bytecodealliance/wasmtime/tree/main/cranelift) and [Wasmtime](https://github.com/bytecodealliance/wasmtime) | Apache-2.0 WITH LLVM-exception |
| [clif-to-wasm](https://github.com/ryancbuckley/clif-to-wasm) | Apache-2.0 WITH LLVM-exception |
| [rust-playground-inbrowser](https://github.com/ryancbuckley/rust-playground-inbrowser) rustc-to-wasm patch series | Apache-2.0 |
| [Wild](https://github.com/wild-linker/wild) | MIT OR Apache-2.0 |
| [wasi-libc](https://github.com/WebAssembly/wasi-libc) (linked into wasm builds of `std`) | Apache-2.0 WITH LLVM-exception, MIT and others (see its LICENSE files) |
| [LLVM](https://github.com/llvm/llvm-project), Clang and LLD (the LLVM-based build under `patches/`; build-time only for `experiments/cranelift-wasm/`) | Apache-2.0 WITH LLVM-exception |

### Patch files

Patch files modify the project they apply to, and each one is licensed under
that project's license, not under this repository's MIT OR Apache-2.0 option.
This applies to `patches/**` and `experiments/**/patches/**`:

- `patches/rust-*/` and patches against `rustc_codegen_cranelift`: MIT OR Apache-2.0 (Rust).
- `patches/llvm-*/`: Apache-2.0 WITH LLVM-exception (LLVM).
- Patches against clif-to-wasm or Cranelift: Apache-2.0 WITH LLVM-exception.
- Patches against Wild: MIT OR Apache-2.0.

Each patch's header records that it was changed by the contributors to this
repository. Upstream patch series that the build scripts fetch at a pinned
revision (such as rust-playground-inbrowser's) are not copied into this
repository. If they are ever vendored here, their LICENSE and NOTICE files must
be copied with them.

Builds distributed from this repository (for example a `rustc.wasm` release)
must include the license texts and notices of every component inside them. A
modified build must not present itself as the official Rust compiler; describe
it as built from rustc.
