//! (e) Maths node: 100k f64 points in linear memory, transformed with
//! `y = sin(x)*0.5 + cos(x*0.25) + sqrt(|x|)`, then reduced to a mean.
//!
//! `no_std` + `alloc`, `panic = "abort"`, a fixed 1 MiB heap in `.bss` (no
//! `memory.grow`), and the Stage-A plugin ABI:
//!
//! ```text
//! wasm_alloc(size, align) -> ptr
//! eval(ptr, len, out) -> i32          // out[0] = mean(transform(xs))
//! eval_stats(ptr, len, out3) -> i32   // out3 = [mean, min, max]
//! wasm_reset()                        // reset the bump allocator
//! ```
#![no_std]

extern crate alloc;

use core::alloc::{GlobalAlloc, Layout};
use core::cell::UnsafeCell;

// Fixed 1 MiB plugin heap in .bss. The host allocates the input/output buffers
// from this heap; eval itself does not allocate, so repeated calls are safe.
const HEAP_SIZE: usize = 1 << 20;
static mut HEAP: [u8; HEAP_SIZE] = [0; HEAP_SIZE];

struct Counter(UnsafeCell<usize>);
unsafe impl Sync for Counter {}
static NEXT: Counter = Counter(UnsafeCell::new(0));

struct Bump;

unsafe impl GlobalAlloc for Bump {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let start = core::ptr::addr_of_mut!(HEAP) as *mut u8 as usize;
        let mut p = unsafe { *NEXT.0.get() };
        if p == 0 {
            p = start;
        }
        let aligned = (p + layout.align() - 1) & !(layout.align() - 1);
        let end = aligned + layout.size();
        if end > start + HEAP_SIZE {
            return core::ptr::null_mut();
        }
        unsafe { *NEXT.0.get() = end; }
        aligned as *mut u8
    }

    unsafe fn dealloc(&self, _ptr: *mut u8, _layout: Layout) {}
}

#[global_allocator]
static ALLOC: Bump = Bump;

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}

#[unsafe(no_mangle)]
pub extern "C" fn wasm_alloc(size: usize, align: usize) -> *mut u8 {
    unsafe { ALLOC.alloc(Layout::from_size_align(size.max(1), align.max(1)).unwrap()) }
}

/// Reset the bump allocator. The host may call this between evaluations.
#[unsafe(no_mangle)]
pub extern "C" fn wasm_reset() {
    unsafe { *NEXT.0.get() = 0; }
}

/// The transform under test. Deliberately a normal (inlinable) function: LLVM
/// and cg_clif's MIR inliner are both free to inline it into `reduce`.
#[inline]
fn transform(x: f64) -> f64 {
    // sqrt is a real f64 op; sin/cos come from the libm crate (no_std).
    libm::sin(x) * 0.5 + libm::cos(x * 0.25) + libm::sqrt(if x < 0.0 { -x } else { x })
}

#[inline(always)]
fn reduce(xs: &[f64]) -> (f64, f64, f64) {
    let mut sum = 0.0f64;
    let mut min = f64::INFINITY;
    let mut max = f64::NEG_INFINITY;
    for &x in xs {
        let y = transform(x);
        sum += y;
        if y < min {
            min = y;
        }
        if y > max {
            max = y;
        }
    }
    let mean = if xs.is_empty() { 0.0 } else { sum / xs.len() as f64 };
    (mean, min, max)
}

/// `eval` receives `len` f64 points at `params` and writes one f64 result to
/// `out`. Returns 0 on success, 1 on a null pointer.
#[unsafe(no_mangle)]
pub extern "C" fn eval(params: *const f64, len: usize, out: *mut f64) -> i32 {
    if params.is_null() || out.is_null() {
        return 1;
    }
    let xs = unsafe { core::slice::from_raw_parts(params, len) };
    let (mean, _, _) = reduce(xs);
    unsafe { *out = mean; }
    0
}

/// Same input, but writes `[mean, min, max]` so the reduce is observable.
/// Not on the timed path; used to sanity-check the transform.
#[unsafe(no_mangle)]
pub extern "C" fn eval_stats(params: *const f64, len: usize, out: *mut f64) -> i32 {
    if params.is_null() || out.is_null() {
        return 1;
    }
    let xs = unsafe { core::slice::from_raw_parts(params, len) };
    let (mean, min, max) = reduce(xs);
    unsafe {
        *out = mean;
        *out.add(1) = min;
        *out.add(2) = max;
    }
    0
}

/// Proof that `alloc` is linked and usable in this crate. Not on the timed path.
#[unsafe(no_mangle)]
pub extern "C" fn alloc_smoke(n: usize) -> f64 {
    use alloc::vec::Vec;
    let mut v: Vec<f64> = Vec::new();
    for i in 0..n.min(1024) {
        v.push(i as f64);
    }
    v.iter().sum()
}
