import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tvbox_core/tvbox_core.dart';

import 'player/video_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 必须在 runApp 之前调用，否则第一次 open 会因为 native 库未加载而卡住。
  MediaKit.ensureInitialized();
  runApp(const TvBoxApp());
}

class TvBoxApp extends StatelessWidget {
  const TvBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TVBox',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B6D11)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  /// 公开测试流，用于验证播放器链路是否打通。
  static const _testUrl =
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TVBox 桌面端')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _Section(
            title: '已完成',
            items: [
              'tvbox_core：Spider / JsEngine / PlatformBridge 抽象',
              'JsHostApi：20 个 JS 宿主全局函数签名对齐 Global.java',
              'JsSpider：模块加载器、//bb 与 //DRPY bytecode、模板预加载',
              'SpiderRunner：worker isolate 封装，隔离同步阻塞',
              '播放器：media_kit (libmpv) 全平台统一',
            ],
          ),
          const SizedBox(height: 16),
          const _Section(
            title: '待补齐（按阶段）',
            items: [
              'P1 同步 HTTP：libcurl FFI，决定 JS 爬虫能否跑起来',
              'P1 JsCrypto / TextConverter：aesX、rsaX、s2t/t2s',
              'P2 HtmlRules：jsoup 规则引擎移植（pdfh/pd/pdfa/pdfla）',
              'P3 桌面 UI：首页、分类、搜索、详情',
              'P6 jar / python：内嵌 JVM 与 libpython',
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const VideoPage(
                  params: PlayParams(url: _testUrl, title: '测试流'),
                ),
              ),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放测试流'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...items.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('· '),
                    Expanded(child: Text(e)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
