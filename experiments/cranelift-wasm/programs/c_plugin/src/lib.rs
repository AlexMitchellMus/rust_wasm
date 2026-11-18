//! NodeCraft-style plugin: host import, f64 parameter list, allocation, result in
//! linear memory, panic=abort, no_std.
#![no_std]

extern crate alloc;

use alloc::vec::Vec;
use core::alloc::{GlobalAlloc, Layout};
use core::cell::UnsafeCell;

// Fixed 1 MiB plugin heap in .bss; see b_alloc for why it is not growable.
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

// The host API this plugin expects. Imported from wasm module "nodecraft",
// not the default "env".
#[link(wasm_import_module = "nodecraft")]
unsafe extern "C" {
    fn host_bias(x: f64) -> f64;
}

#[unsafe(no_mangle)]
pub extern "C" fn wasm_alloc(size: usize, align: usize) -> *mut u8 {
    unsafe { ALLOC.alloc(Layout::from_size_align(size.max(1), align.max(1)).unwrap()) }
}

/// `eval` receives `len` f64 parameters at `params`, and writes one f64 result
/// to `out`. Returns 0 on success.
#[unsafe(no_mangle)]
pub extern "C" fn eval(params: *const f64, len: usize, out: *mut f64) -> i32 {
    if params.is_null() || out.is_null() {
        return 1;
    }
    let xs = unsafe { core::slice::from_raw_parts(params, len) };
    let mut adjusted: Vec<f64> = Vec::with_capacity(xs.len());
    for &x in xs {
        adjusted.push(unsafe { host_bias(x) });
    }
    let sum: f64 = adjusted.iter().sum();
    let mean = if adjusted.is_empty() { 0.0 } else { sum / adjusted.len() as f64 };
    unsafe { *out = mean };
    0
}
