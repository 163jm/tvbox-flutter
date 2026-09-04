import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tvbox_core/tvbox_core.dart';

/// 播放页。
///
/// 全平台统一走 libmpv（`media_kit`）。选择它的原因：
/// - 同一套 API 覆盖 Windows / Linux / macOS / Android / iOS
/// - 解码能力与 libass 字幕渲染都在 native 层，不受平台播放器差异影响
/// - HLS / DASH / 各类封装与编码的支持面比 ExoPlayer 更广
///
/// 注意 [PlayParams.needsProxy]：mpv 支持为首个请求带 header，但分片
/// 请求（m3u8 里的 ts）通常带不上，因此带 header 的地址仍建议走本地代理。
class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.params});

  final PlayParams params;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final Player _player;
  late final VideoController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    final params = widget.params;
    try {
      await _player.open(Media(params.url, httpHeaders: params.headers));

      final subtitle = params.subtitleUrl;
      if (subtitle != null && subtitle.isNotEmpty) {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(subtitle, title: params.title),
        );
      }

      if (params.position > Duration.zero) {
        await _player.seek(params.position);
      }
      await _player.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '播放失败：$e');
    }
  }

  @override
  void dispose() {
    // 先停再释放，避免 mpv 在 dispose 时仍在回调
    _player.stop().then((_) => _player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: Video(controller: _controller)),
          if (_error != null)
            Center(
              child: Text(_error!, style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
