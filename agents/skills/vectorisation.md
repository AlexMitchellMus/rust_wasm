# Skill: writing vectorisable Rust

How to write hot loops so they turn into SIMD, and how to check that they did.

## Know which compiler you're writing for

| Pipeline | Auto-vectorises? | What to do |
| --- | --- | --- |
| LLVM (normal rustc, `-O2`/`-O3`) | Yes, simple loops | Write loops in the shapes below and let LLVM do it |
| Our pipeline (Cranelift → clif-to-wasm) | **No**, not yet (a roadmap item) | Use explicit `core::arch::wasm32` SIMD for hot loops, or call a host bulk API |
| Wasmtime (wasm → native) | No; it translates wasm SIMD (`v128`) to native SIMD | Emit `v128` instructions and they map to SSE/NEON |

So for code built by our pipeline, **explicit SIMD is the reliable path** until
tier-2 auto-vectorisation exists. Code written in the shapes below is still
worth it: it helps LLVM today and is what an auto-vectoriser will look for.

## Shapes that vectorise

- **Data-oriented layout.** Structure of arrays (`xs: Vec<f32>, ys: Vec<f32>`)
  rather than arrays of structs, so each loop reads contiguous memory.
- **Fixed-size chunks.** `for c in a.chunks_exact(4)` (or 8, 16) plus a scalar
  tail via `chunks_exact(..).remainder()`.
- **No bounds checks in the loop.** Iterate with `zip` instead of indexing, or
  slice once before the loop (`let a = &a[..n]; let b = &b[..n];`) so the
  compiler can prove the length.
- **No early exits or calls in the inner loop.** Keep the body to arithmetic,
  loads and stores; pull branches out, or replace them with `select`-style
  arithmetic (`min`, `max`, masks).
- **No loop-carried dependencies you don't need.** Sums are fine (reductions),
  but floating-point reductions only vectorise if you accumulate into several
  partial sums yourself, because reordering float additions changes results.
- **`#[inline]`** small helpers called from hot loops, so they can be
  vectorised together.

## Explicit wasm SIMD

```rust
#[cfg(target_feature = "simd128")]
fn add_scaled(out: &mut [f32], a: &[f32], b: &[f32], k: f32) {
    use core::arch::wasm32::*;
    let kv = f32x4_splat(k);
    let n = out.len().min(a.len()).min(b.len());
    let (out, a, b) = (&mut out[..n], &a[..n], &b[..n]);
    let mut i = 0;
    while i + 4 <= n {
        // SAFETY: i + 4 <= n == out.len() == a.len() == b.len(); unaligned
        // v128 loads and stores are allowed in wasm.
        unsafe {
            let va = v128_load(a.as_ptr().add(i).cast());
            let vb = v128_load(b.as_ptr().add(i).cast());
            v128_store(out.as_mut_ptr().add(i).cast(), f32x4_add(va, f32x4_mul(vb, kv)));
        }
        i += 4;
    }
    for j in i..n {
        out[j] = a[j] + b[j] * k;
    }
}
```

Build with `-C target-feature=+simd128`. Always keep a scalar version (for
targets without `simd128`) and a test that compares the two.

## Check that it worked

1. **Look at the wasm.** `wasm-tools print module.wasm | grep -c v128` (or
   `f32x4`, `i32x4`) — no SIMD instructions means nothing was vectorised.
2. **Compare outputs.** Add the program to the difftest corpus; SIMD and
   scalar paths must agree (for floats, agree exactly unless the test documents
   an allowed reassociation).
3. **Measure.** Use the A.2 harness ([measuring-performance.md](measuring-performance.md))
   and report before/after medians.

## When not to bother

Small arrays, code dominated by host calls, or loops that run rarely. Measure
first; a host bulk API or the GPU path may beat any CPU SIMD for large data.
