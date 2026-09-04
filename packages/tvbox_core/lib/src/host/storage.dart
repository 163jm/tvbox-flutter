/// JS 侧 `local` 对象背后的键值存储。
///
/// 原版用 Hawk，key 格式为 `jsRuntime_{id}_{key}`，
/// 其中 id 是爬虫标识，key 是爬虫自己传的名字。
/// 移植时必须保留这个前缀规则，否则不同站点之间会互相覆盖数据。
abstract class KeyValueStore {
  /// 读取，不存在时返回 [defaultValue]（原版默认返回空串，不是 null）。
  String get(String id, String key, {String defaultValue = ''});

  void set(String id, String key, String value);

  void delete(String id, String key);
}
