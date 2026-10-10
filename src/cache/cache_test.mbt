///|
/// 可控假时钟（毫秒），用于测试 TTL 行为。
priv struct FakeClock {
  mut now : Int64
}

///|
fn FakeClock::new() -> FakeClock {
  { now: 1_000_000L }
}

///|
fn FakeClock::now_ms(self : FakeClock) -> Int64 {
  self.now
}

///|
fn FakeClock::advance(self : FakeClock, seconds : Int64) -> Unit {
  self.now = self.now + seconds * 1000L
}

///|
fn make_cache(clock : FakeClock) -> @cache.MemoryCache {
  @cache.MemoryCache::new(fn() { clock.now_ms() })
}

///|
test "cache set and get" {
  let clock = FakeClock::new()
  let cache = make_cache(clock)
  cache.set("k", "v", 60L)
  assert_true(cache.get("k") == Some("v"))
  assert_true(cache.exists("k"))
}

///|
test "cache expires after ttl" {
  let clock = FakeClock::new()
  let cache = make_cache(clock)
  cache.set("k", "v", 120L)
  clock.advance(119L)
  assert_true(cache.get("k") == Some("v"))
  clock.advance(2L)
  assert_true(cache.get("k") is None)
  assert_true(!cache.exists("k"))
}

///|
test "cache delete removes key" {
  let clock = FakeClock::new()
  let cache = make_cache(clock)
  cache.set("k", "v", 60L)
  cache.delete("k")
  assert_true(cache.get("k") is None)
}

///|
test "cache zero ttl means never expire" {
  let clock = FakeClock::new()
  let cache = make_cache(clock)
  cache.set("k", "v", 0L)
  clock.advance(3600L)
  assert_true(cache.get("k") == Some("v"))
}

///|
test "cache clears when over threshold" {
  let clock = FakeClock::new()
  let cache = @cache.MemoryCache::new(fn() { clock.now_ms() }, max_entries=4)
  for i in 0..<20 {
    cache.set("key\{i}", "v", 60L)
  }
  // 超过 max_entries * 2 后整体清空
  assert_true(cache.get("key0") is None)
}
