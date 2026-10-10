///|
test "rng deterministic sequence" {
  let a = Rng::new(42UL)
  let b = Rng::new(42UL)
  for _i in 0..<100 {
    assert_true(a.next_u64() == b.next_u64())
  }
}
