#![allow(dead_code)]
#[allow(clippy::too_many_lines)]
fn a() { todo!() }
fn b() { unimplemented!("x") }
fn c(x: u32) -> u32 { dbg!(x) }
fn d() { std::thread::sleep(std::time::Duration::from_millis(5)); }
fn e() { std::process::exit(1) }
#[test]
#[ignore]
fn f() {}
