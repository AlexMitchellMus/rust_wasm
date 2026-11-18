fn main() {
    let v: Vec<f64> = (0..8).map(|i| i as f64 * 0.5).collect();
    println!("hello from std wasm; sum={}", v.iter().sum::<f64>());
}
