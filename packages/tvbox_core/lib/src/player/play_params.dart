/// 播放参数。
///
/// 对齐原版 `ui/fragment/PlayFragment` 组装播放请求时用到的数据：
/// url、header、字幕、选集进度、播放器类型。
class PlayParams {
  const PlayParams({
    required this.url,
    this.headers = const <String, String>{},
    this.title = '',
    this.subtitleUrl,
    this.subtitleHeaders = const <String, String>{},
    this.position = Duration.zero,
    this.playerType = -1,
    this.flag = '',
    this.key = '',
  });

  /// 播放地址。
  final String url;

  /// 播放请求需要带的 header。
  ///
  /// 大部分播放器无法为 HLS / DASH 的分片请求附带自定义 header，
  /// 这类地址必须经由本地代理转发，见 [needsProxy]。
  final Map<String, String> headers;

  final String title;

  /// 字幕地址，可为本地文件或 http(s) 链接。
  final String? subtitleUrl;

  final Map<String, String> subtitleHeaders;

  /// 续播进度。
  final Duration position;

  /// 0=system 1=ijk 2=exo 10=mxplayer -1=跟随全局设置。
  final int playerType;

  /// 播放来源标识（如 qiyi、qq），用于选集高亮。
  final String flag;

  /// 站点 key，用于记录历史。
  final String key;

  bool get needsProxy => headers.isNotEmpty;
}
