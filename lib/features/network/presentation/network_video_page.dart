import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../domain/live_models.dart';

/// 网络视频直链播放页（mp4 / m3u8 等）。
class NetworkVideoPage extends StatefulWidget {
  const NetworkVideoPage({super.key, required this.video});

  final NetworkVideo video;

  @override
  State<NetworkVideoPage> createState() => _NetworkVideoPageState();
}

class _NetworkVideoPageState extends State<NetworkVideoPage> {
  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  final ValueNotifier<Duration> _position = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<Duration> _duration = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<bool> _playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _buffering = ValueNotifier<bool>(false);
  final ValueNotifier<double?> _drag = ValueNotifier<double?>(null);

  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      _player.stream.position.listen(
        (Duration value) => _position.value = value,
      ),
      _player.stream.duration.listen(
        (Duration value) => _duration.value = value,
      ),
      _player.stream.playing.listen((bool value) => _playing.value = value),
      _player.stream.buffering.listen((bool value) => _buffering.value = value),
      _player.stream.error.listen((String message) {
        if (mounted) setState(() => _error = message);
      }),
    ]);
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _player.open(Media(widget.video.url), play: true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    _position.dispose();
    _duration.dispose();
    _playing.dispose();
    _buffering.dispose();
    _drag.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing.value) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePlay,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Video(
              controller: _controller,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              wakelock: true,
            ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Text(
                    '播放失败：$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 14, 0),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: () => context.canPop()
                              ? context.pop()
                              : context.go('/'),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            widget.video.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<bool>(
                    valueListenable: _buffering,
                    builder: (BuildContext context, bool buffering, _) {
                      if (!buffering) return const SizedBox.shrink();
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white70,
                          ),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _playing,
                    builder: (BuildContext context, bool playing, _) {
                      return AnimatedOpacity(
                        opacity: playing ? 0 : 1,
                        duration: const Duration(milliseconds: 160),
                        child: const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 62,
                          color: Colors.white70,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildProgress(context),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: <Widget>[
          ValueListenableBuilder<Duration>(
            valueListenable: _position,
            builder: (BuildContext context, Duration position, _) {
              return SizedBox(
                width: 46,
                child: Text(
                  formatDuration(position.inMilliseconds),
                  style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                ),
              );
            },
          ),
          Expanded(
            child: ValueListenableBuilder<double?>(
              valueListenable: _drag,
              builder: (BuildContext context, double? drag, _) {
                return ValueListenableBuilder<Duration>(
                  valueListenable: _duration,
                  builder: (BuildContext context, Duration duration, _) {
                    final double total = duration.inMilliseconds.toDouble();
                    return ValueListenableBuilder<Duration>(
                      valueListenable: _position,
                      builder: (BuildContext context, Duration position, _) {
                        final double value =
                            (drag ?? position.inMilliseconds.toDouble()).clamp(
                              0,
                              total <= 0 ? 1 : total,
                            );
                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppColors.primary,
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 13,
                            ),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5.5,
                            ),
                          ),
                          child: Slider(
                            padding: EdgeInsets.zero,
                            value: value.toDouble(),
                            max: total <= 0 ? 1 : total,
                            onChanged: total <= 0
                                ? null
                                : (double next) => _drag.value = next,
                            onChangeEnd: (double next) async {
                              await _player.seek(
                                Duration(milliseconds: next.round()),
                              );
                              _drag.value = null;
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          ValueListenableBuilder<Duration>(
            valueListenable: _duration,
            builder: (BuildContext context, Duration duration, _) {
              return SizedBox(
                width: 46,
                child: Text(
                  formatDuration(duration.inMilliseconds),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
