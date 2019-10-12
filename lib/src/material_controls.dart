import 'dart:async';

import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/material_progress_bar.dart';
import 'package:chewie/src/utils.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MaterialControls extends StatefulWidget {
  const MaterialControls({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _MaterialControlsState();
  }
}

class _MaterialControlsState extends State<MaterialControls> {
  VideoPlayerValue _latestValue;
  double _latestVolume;
  bool _hideStuff = true;
  Timer _hideTimer;
  Timer _showTimer;
  Timer _showAfterExpandCollapseTimer;
  bool _dragging = false;

  bool _isInitComplete = false; // 是否正初始化完成
  bool _isLoadBuffer = false; // 是否正在加载缓存
  int _loadCount = 0; // 加载缓存判断次数，累计5次以上，正在加载
  bool _isPlayComplete = false; //是否播放完成

  final barHeight = 48.0;
  final marginSize = 5.0;

  VideoPlayerController controller;
  ChewieController chewieController;

  @override
  Widget build(BuildContext context) {
    return _latestValue.hasError ? _buildErrorView() : _buildPlayControlView();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    controller.removeListener(_updateState);
    _hideTimer?.cancel();
    _showTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    final _oldController = chewieController;
    chewieController = ChewieController.of(context);
    controller = chewieController.videoPlayerController;

    if (_oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  // 加载失败界面
  Widget _buildErrorView() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      child: chewieController.errorBuilder != null
          ? chewieController.errorBuilder(context, chewieController.videoPlayerController.value.errorDescription)
          : Center(
              child: Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 42,
              ),
            ),
      onTap: () {
        setState(() {
          controller.value = VideoPlayerValue(
            duration: null,
            isPlaying: false,
            isBuffering: controller.value.isBuffering,
            errorDescription: null,
            isLooping: controller.value.isLooping,
            position: Duration.zero,
          );
          _isInitComplete = false;
        });
        controller.initialize().then((_) async {
          await controller.play();
        });
      },
    );
  }

  // 视频播放界面（控制）
  Widget _buildPlayControlView() {
    return GestureDetector(
      child: AbsorbPointer(
        absorbing: _hideStuff,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            _buildProgressIndicatorView(),
            _buildBufferMemoryView(),
            _buildHitArea(),
            _buildBottomBar(context),
          ],
        ),
      ),
      onTap: () => _cancelAndRestartTimer(),
    );
  }

  Widget _buildProgressIndicatorView() {
    return Offstage(
      offstage: _isInitComplete ? true : false,
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildHitArea() {
    return GestureDetector(
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: AnimatedOpacity(
            opacity: _latestValue != null && !_latestValue.isPlaying && !_dragging && _isInitComplete ? 1.0 : 0.0,
            duration: Duration(milliseconds: 300),
            child: GestureDetector(
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0x66000000),
                  borderRadius: BorderRadius.circular(48.0),
                ),
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.play_arrow,
                    size: 28.0,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      onTap: _latestValue != null && _latestValue.isPlaying
          ? _cancelAndRestartTimer
          : () {
              _playPause();
              setState(() {
                _hideStuff = true;
              });
            },
    );
  }

  Widget _buildBufferMemoryView() {
    return Opacity(
      opacity: _isLoadBuffer ? 1.0 : 0.0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            Padding(
              padding: EdgeInsets.only(top: 5.0),
              child: Text(
                '加载进度中...',
                style: TextStyle(color: Colors.white, fontSize: 12.0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final iconColor = Theme.of(context).textTheme.button.color;
    return AnimatedOpacity(
      opacity: _hideStuff || !_isInitComplete ? 0.0 : 1.0,
      duration: Duration(milliseconds: 300),
      child: Column(
        children: <Widget>[
          Opacity(
            opacity: chewieController.isFullScreen ? 1.0 : 0.0,
            child: Container(
              height: barHeight,
              color: Color(0x66000000),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  _buildFullScreenBackView(),
                  _buildFullScreenTitleView(),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(),
          ),
          Container(
            height: barHeight,
            color: Color(0x66000000),
            child: Row(
              children: <Widget>[
                _buildPlayPause(controller),
                chewieController.isLive ? Expanded(child: const Text('LIVE')) : _buildPosition(iconColor),
                chewieController.isLive ? const SizedBox() : _buildProgressBar(),
                chewieController.allowMuting ? _buildMuteButton(controller) : Container(),
                chewieController.allowFullScreen ? _buildExpandButton() : Container(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenBackView() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        width: barHeight,
        height: barHeight,
        child: Icon(
          Icons.arrow_back_ios,
          color: Colors.white,
        ),
      ),
      onTap: _onExpandCollapse,
    );
  }

  Expanded _buildFullScreenTitleView() {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(left: 5.0, right: 16.0),
        child: Text(
          chewieController?.videoTitle ?? '',
          style: TextStyle(color: Colors.white, fontSize: 18.0),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  GestureDetector _buildExpandButton() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _onExpandCollapse,
      child: AnimatedOpacity(
        opacity: _hideStuff ? 0.0 : 1.0,
        duration: Duration(milliseconds: 300),
        child: Container(
          height: barHeight,
          padding: EdgeInsets.only(left: 6.0, right: 12.0),
          child: Center(
            child: Icon(
              chewieController.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  GestureDetector _buildMuteButton(VideoPlayerController controller) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _cancelAndRestartTimer();

        if (_latestValue.volume == 0) {
          controller.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = controller.value.volume;
          controller.setVolume(0.0);
        }
      },
      child: AnimatedOpacity(
        opacity: _hideStuff ? 0.0 : 1.0,
        duration: Duration(milliseconds: 300),
        child: ClipRect(
          child: Container(
            height: barHeight,
            padding: EdgeInsets.only(left: 12.0, right: 6.0),
            child: Icon(
              (_latestValue != null && _latestValue.volume > 0) ? Icons.volume_up : Icons.volume_off,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  GestureDetector _buildPlayPause(VideoPlayerController controller) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _playPause();
      },
      child: Container(
        height: barHeight,
        width: barHeight,
        child: Icon(
          controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPosition(Color iconColor) {
    final position = _latestValue != null && _latestValue.position != null ? _latestValue.position : Duration.zero;
    final duration = _latestValue != null && _latestValue.duration != null ? _latestValue.duration : Duration.zero;

    return Container(
      height: barHeight,
      child: Center(
        child: Text(
          '${formatDuration(position)} / ${formatDuration(duration)}',
          style: TextStyle(fontSize: 14.0, color: Colors.white),
        ),
      ),
    );
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      _hideStuff = false;
    });
  }

  Future<Null> _initialize() async {
    controller.addListener(_updateState);

    _updateState();

    if ((controller.value != null && controller.value.isPlaying) || chewieController.autoPlay) {
      _startHideTimer();
    }

    _showTimer = Timer(Duration(milliseconds: 200), () {
      setState(() {
        _hideStuff = false;
      });
    });
  }

  void _onExpandCollapse() {
    setState(() {
      _hideStuff = true;

      chewieController.toggleFullScreen();
      _showAfterExpandCollapseTimer = Timer(Duration(milliseconds: 300), () {
        setState(() {
          _cancelAndRestartTimer();
        });
      });
    });
  }

  Future<void> _playPause() async {
    if (controller.value.isPlaying) {
      _hideStuff = false;
      _hideTimer?.cancel();
      controller.pause();
    } else {
      _cancelAndRestartTimer();
      if (!controller.value.initialized) {
        controller.initialize().then((_) {
          controller.play();
        });
      } else {
        if (_isPlayComplete) {
          await controller.seekTo(Duration.zero);
        }
        _isPlayComplete = false;
        controller.play();
      }
    }
    setState(() {});
  }

  void _startHideTimer() {
    _hideTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        _hideStuff = true;
      });
    });
  }

  void _updateState() {
    setState(() {
      VideoPlayerValue playerValue = controller.value;
      // 判断是否初始化完成
      if (playerValue.duration != null) {
        _isInitComplete = true;
      }
      // 判断是否在加载中
      _isLoadBuffer = false;
      if (playerValue.isPlaying) {
        if (playerValue.buffered.length != 0 && playerValue.duration >= playerValue.buffered[0].end) {
          if (playerValue.position == _latestValue?.position) {
            _loadCount++;
            if (_loadCount >= 4) {
              _isLoadBuffer = true;
            }
          } else {
            // 清空累计次数
            _loadCount = 0;
          }
        }
      }
      // 判断是否播放完成
      if (!playerValue.isLooping && playerValue.duration != null) {
        if (playerValue.position >= playerValue.duration) {
          _isPlayComplete = true;
        }
      }
      _latestValue = playerValue;
      debugPrint(_latestValue.toString());
    });
  }

  Widget _buildProgressBar() {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(left: 14.0),
        child: MaterialVideoProgressBar(
          controller,
          onDragStart: () {
            setState(() {
              _dragging = true;
            });

            _hideTimer?.cancel();
          },
          onDragEnd: () {
            setState(() {
              _dragging = false;
            });

            _startHideTimer();
          },
          colors: chewieController.materialProgressColors ??
              ChewieProgressColors(
                  playedColor: Colors.white,
                  handleColor: Theme.of(context).primaryColor,
                  bufferedColor: Color(0xAAAAAAAA),
                  backgroundColor: Color(0x66222222)),
        ),
      ),
    );
  }
}
