/// HTML 规则解析引擎。
///
/// 对应原版 `util/js/HtmlParser.java`（299 行，基于 jsoup），
/// 是海阔 / DRPY 生态的事实标准。JS 侧通过全局函数 `pdfh` / `pd` /
/// `pdfa` / `pdfla` 调用，因此这套语义必须与参考实现严格一致，
/// 否则现成爬虫的解析规则会大面积失效。
///
/// 移植要点（来自 HtmlParser.java 的实现细节）：
/// - 单规则形如 `div.class--exclude:eq(0)`
///   - `--` 之后是排除规则，支持多个
///   - `:eq(n)` / `:lt(n)` / `:gt(n)` / `:first` / `:last` 是下标选择
///   - `body` 与 `#` 前缀有特殊语义，不自动追加 eq 下标
/// - 属性白名单（`url|src|href|-original|-src|-play|-url|style`）自动 urljoin
/// - `^(ftp|magnet|thunder|ws):` 这类特殊链接跳过 urljoin
/// - `url(...)` 语法用于从 style 中提取地址
abstract class HtmlRules {
  /// 解析单元素，返回文本或属性值。
  /// 对应 `pdfh(html, rule)`。
  String pdfh(String html, String rule);

  /// 解析单元素并做 urljoin。
  /// 对应 `pd(html, rule, addUrl)`。
  String pd(String html, String rule, String addUrl);

  /// 解析为数组。
  /// 对应 `pdfa(html, rule)`。
  List<String> pdfa(String html, String rule);

  /// 列表解析：先定位列表块，再在块内分别取文本与链接。
  /// 对应 `pdfla(html, p1, listText, listUrl, addUrl)`。
  List<String> pdfla(
    String html,
    String p1,
    String listText,
    String listUrl,
    String addUrl,
  );

  /// URL 拼接，对应 `HtmlParser.joinUrl`。
  /// 原版用 `new URL(new URL(parent), child)` 语义。
  String joinUrl(String parent, String child);

  /// 判断规则是否需要下标索引，对应 `HtmlParser.isIndex`。
  bool isIndex(String rule);
}
