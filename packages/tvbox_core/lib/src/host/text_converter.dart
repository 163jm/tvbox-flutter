/// 繁简转换，对应原版 `util/js/Trans.java`（`s2t` / `t2s`）。
///
/// 大量爬虫在搜索前把关键词做简繁双向转换以提高命中率，
/// 因此这不是可选项。
abstract class TextConverter {
  /// 简体转繁体。
  String s2t(String text);

  /// 繁体转简体。
  String t2s(String text);
}
