///|
/// 验证码缓存抽象，对齐 AJ-Captcha 的 CaptchaCacheService。
/// 单机用 MemoryCache；分布式部署由集成层提供实现（如 Redis）。
pub trait Cache {
  /// 写入缓存；expires_in_seconds <= 0 表示不过期。
  fn set(Self, key : String, value : String, expires_in_seconds : Int64) -> Unit
  /// 读取缓存；键不存在或已过期返回 None（读时惰性淘汰）。
  fn get(Self, key : String) -> String?
  /// 键是否存在且未过期。
  fn exists(Self, key : String) -> Bool
  /// 删除键。
  fn delete(Self, key : String) -> Unit
}

///|
/// 内存缓存，语义对齐 AJ-Captcha 的 CacheUtil：
/// - `key_HoldTime` 过期时间戳的懒淘汰模型；
/// - 超过容量阈值整体清空（防内存膨胀）。
/// 与 Java 版的差异：时钟通过 now_ms 注入，便于测试与跨平台移植。
pub struct MemoryCache {
  data : Map[String, String]
  expiry : Map[String, Int64]
  now_ms : () -> Int64
  max_entries : Int
}

///|
/// 创建内存缓存。
/// - `now_ms`：当前毫秒时间戳（注入时钟）
/// - `max_entries`：容量阈值，超过两倍即整体清空（默认 1000，同 CacheUtil）
pub fn MemoryCache::new(
  now_ms : () -> Int64,
  max_entries? : Int = 1000,
) -> MemoryCache {
  { data: Map([]), expiry: Map([]), now_ms, max_entries, }
}

///|
fn MemoryCache::evict_if_full(self : MemoryCache) -> Unit {
  if self.data.length() > self.max_entries * 2 {
    self.data.clear()
    self.expiry.clear()
  }
}

///|
fn MemoryCache::expired(self : MemoryCache, key : String) -> Bool {
  match self.expiry.get(key) {
    Some(hold_time) => hold_time < (self.now_ms)()
    // 无过期时间条目 = 永不过期
    None => false
  }
}

///|
pub impl Cache for MemoryCache with fn set(self, key, value, expires_in_seconds) {
  self.evict_if_full()
  self.data.set(key, value)
  if expires_in_seconds > 0L {
    self.expiry.set(key, (self.now_ms)() + expires_in_seconds * 1000L)
  } else {
    self.expiry.remove(key)
  }
}

///|
pub impl Cache for MemoryCache with fn get(self, key) {
  if self.expired(key) {
    // 读时惰性淘汰
    self.data.remove(key)
    self.expiry.remove(key)
    return None
  }
  self.data.get(key)
}

///|
pub impl Cache for MemoryCache with fn exists(self, key) {
  Cache::get(self, key) is Some(_)
}

///|
pub impl Cache for MemoryCache with fn delete(self, key) {
  self.data.remove(key)
  self.expiry.remove(key)
}

///|
/// 将 Cache 的 trait 方法提升为 MemoryCache 的可直调方法。
pub extend MemoryCache with Cache::{set, get, exists, delete}
