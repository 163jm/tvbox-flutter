import 'dart:async';
import 'dart:isolate';

import 'spider.dart';

/// 在 isolate 里创建爬虫的工厂。
///
/// 由 app 层实现：它知道该用哪套 JsEngine、PlatformBridge 与 ModuleSource。
typedef SpiderFactory = Spider Function(String key, String api, String ext);

/// worker isolate 的服务端循环。
///
/// 由 app 层的顶层入口函数调用：
/// ```dart
/// @pragma('vm:entry-point')
/// void spiderWorkerMain(SendPort sendPort) =>
///     runSpiderWorker(sendPort, _createSpider);
/// ```
///
/// 为什么必须单独跑一个 isolate：JS 爬虫里的 `req()` 是**同步** HTTP，
/// 会把当前 isolate 阻塞住。放在 UI isolate 上就是界面卡死，
/// 原版用的是 `newSingleThreadExecutor()`，这里用 isolate 达到同样效果。
void runSpiderWorker(SendPort sendPort, SpiderFactory factory) {
  final commands = ReceivePort();
  sendPort.send(commands.sendPort);

  Spider? spider;

  commands.listen((raw) {
    if (raw is! Map) return;
    final cmd = raw['cmd'] as String?;
    final reply = raw['reply'] as SendPort?;

    void answer(Object? value) => reply?.send(<String, Object?>{'value': value});

    switch (cmd) {
      case 'init':
        try {
          spider = factory(
            raw['key'] as String,
            raw['api'] as String,
            raw['ext'] as String? ?? '',
          )..init(raw['ext'] as String? ?? '');
          answer(null);
        } catch (e, s) {
          reply?.send(<String, Object?>{'error': '$e', 'stack': '$s'});
        }
        break;

      case 'homeContent':
        answer(spider?.homeContent(raw['filter'] as bool? ?? false));
        break;

      case 'homeVideoContent':
        answer(spider?.homeVideoContent());
        break;

      case 'categoryContent':
        answer(spider?.categoryContent(
          raw['tid'] as String? ?? '',
          raw['pg'] as String? ?? '1',
          raw['filter'] as bool? ?? true,
          (raw['extend'] as Map?)?.cast<String, String>() ?? const {},
        ));
        break;

      case 'detailContent':
        answer(spider?.detailContent((raw['ids'] as List?)?.cast<String>() ?? const []));
        break;

      case 'searchContent':
        answer(spider?.searchContent(
          raw['key'] as String? ?? '',
          raw['quick'] as bool? ?? false,
          raw['pg'] as String?,
        ));
        break;

      case 'playerContent':
        answer(spider?.playerContent(
          raw['flag'] as String? ?? '',
          raw['id'] as String? ?? '',
          (raw['vipFlags'] as List?)?.cast<String>() ?? const [],
        ));
        break;

      case 'liveContent':
        answer(spider?.liveContent(raw['url'] as String? ?? ''));
        break;

      case 'action':
        answer(spider?.action(raw['action'] as String? ?? ''));
        break;

      case 'destroy':
        spider?.destroy();
        spider = null;
        commands.close();
        break;

      default:
        answer(null);
    }
  });
}

/// UI 侧的爬虫代理。所有方法都是异步的，实际执行发生在 worker isolate。
class SpiderRunner {
  SpiderRunner._(this._commands, this._onExit);

  final SendPort _commands;
  final Future<void> _onExit;

  /// 启动一个 worker isolate。
  ///
  /// [entryPoint] 必须是顶层或静态函数，Dart 的 isolate 限制。
  static Future<SpiderRunner> spawn(
    void Function(SendPort) entryPoint,
  ) async {
    final initPort = RawReceivePort();
    final connection = Completer<SendPort>();
    final exitPort = RawReceivePort();
    final exitCompleter = Completer<void>();

    initPort.handler = (message) {
      if (!connection.isCompleted && message is SendPort) {
        connection.complete(message);
      }
    };
    exitPort.handler = (_) {
      if (!exitCompleter.isCompleted) exitCompleter.complete();
      exitPort.close();
    };

    try {
      await Isolate.spawn(
        entryPoint,
        initPort.sendPort,
        onExit: exitPort.sendPort,
      );
    } catch (_) {
      initPort.close();
      exitPort.close();
      rethrow;
    }

    final commands = await connection.future;
    initPort.close();
    return SpiderRunner._(commands, exitCompleter.future);
  }

  Future<Object?> _invoke(Map<String, Object?> cmd) async {
    final port = ReceivePort();
    _commands.send(<String, Object?>{...cmd, 'reply': port.sendPort});
    final result = await port.first;
    port.close();
    if (result is Map && result.containsKey('error')) {
      throw StateError('${result['error']}');
    }
    return (result as Map?)?['value'];
  }

  Future<void> init({
    required String key,
    required String api,
    String ext = '',
  }) =>
      _invoke(<String, Object?>{'cmd': 'init', 'key': key, 'api': api, 'ext': ext});

  Future<String> homeContent(bool filter) async =>
      await _invoke(<String, Object?>{'cmd': 'homeContent', 'filter': filter})
          as String? ??
      '';

  Future<String> homeVideoContent() async =>
      await _invoke(const <String, Object?>{'cmd': 'homeVideoContent'})
          as String? ??
      '';

  Future<String> categoryContent(
    String tid,
    String pg,
    bool filter,
    Map<String, String> extend,
  ) async =>
      await _invoke(<String, Object?>{
        'cmd': 'categoryContent',
        'tid': tid,
        'pg': pg,
        'filter': filter,
        'extend': extend,
      }) as String? ??
      '';

  Future<String> detailContent(List<String> ids) async =>
      await _invoke(<String, Object?>{'cmd': 'detailContent', 'ids': ids})
          as String? ??
      '';

  Future<String> searchContent(String key, bool quick, [String? pg]) async =>
      await _invoke(<String, Object?>{
        'cmd': 'searchContent',
        'key': key,
        'quick': quick,
        'pg': pg,
      }) as String? ??
      '';

  Future<String> playerContent(
    String flag,
    String id,
    List<String> vipFlags,
  ) async =>
      await _invoke(<String, Object?>{
        'cmd': 'playerContent',
        'flag': flag,
        'id': id,
        'vipFlags': vipFlags,
      }) as String? ??
      '';

  Future<String> liveContent(String url) async =>
      await _invoke(<String, Object?>{'cmd': 'liveContent', 'url': url})
          as String? ??
      '';

  Future<String?> action(String action) async =>
      await _invoke(<String, Object?>{'cmd': 'action', 'action': action})
          as String?;

  void destroy() => _commands.send(const <String, Object?>{'cmd': 'destroy'});

  Future<void> get onExit => _onExit;
}
