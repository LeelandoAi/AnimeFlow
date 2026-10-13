import 'dart:async';
import 'dart:typed_data';

import 'package:anime_flow/core/logger/logger.dart';
import 'package:anime_flow/features/play/domain/player/playback_source.dart';
import 'package:anime_flow/features/play/domain/player/player_capabilities.dart';
import 'package:anime_flow/features/play/domain/player/player_engine.dart';
import 'package:anime_flow/features/play/domain/player/player_event.dart';
import 'package:anime_flow/features/play/domain/player/player_kernel.dart';
import 'package:anime_flow/features/play/domain/player/player_snapshot.dart';
import 'package:anime_flow/features/play/infrastructure/player/player_engine_factory.dart';
import 'package:anime_flow/features/play/infrastructure/player/player_operation_queue.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 播放器基础协调层。
class PlaybackCoordinator with WidgetsBindingObserver {
  PlaybackCoordinator({
    required this.engineFactory,
    required this.adBlocker,
  });

  final PlayerEngineFactory engineFactory;
  final bool adBlocker;
  Future<void>? _wakelockUpdates;
  bool _playing = false;
  bool _requestedWakelock = false;
  final StreamController<PlayerEvent> _events =
      StreamController<PlayerEvent>.broadcast();
  StreamSubscription<PlayerEvent>? _engineSubscription;
  PlayerEngine? _engine;
  bool _disposed = false;
  late final _operations = PlayerOperationQueue(ensureReady: _ensureReady);
  Future<void>? _disposal;
  Future<void>? _initialization;

  PlayerEngine get _activeEngine =>
      _engine ?? (throw StateError('PlaybackCoordinator has no active engine'));
  bool get _keepScreenOn =>
      !_disposed &&
      _playing &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  PlayerKernel get kernel => _activeEngine.kernel;
  Stream<PlayerEvent> get events => _events.stream;
  PlayerCapabilities get capabilities => _activeEngine.capabilities;

  Future<void> initialize({PlayerKernel kernel = PlayerKernel.mediaKit}) {
    if (_disposed) {
      return Future<void>.error(StateError('PlaybackCoordinator is disposed'));
    }
    return _initialization ??= _initialize(kernel);
  }

  Future<void> _initialize(PlayerKernel kernel) async {
    final engine = engineFactory.create(kernel, adBlocker: adBlocker);
    _engine = engine;
    await engine.initialize();
    if (_disposed) return;
    _subscribeToEngine(engine);
    WidgetsBinding.instance.addObserver(this);
  }

  Widget buildVideoSurface({required BoxFit fit}) {
    // 首次构建可能早于初始化完成，由已经创建的内核检查画面是否就绪。
    return _activeEngine.buildVideoSurface(fit: fit);
  }

  Future<void> open(
    PlaybackSource source, {
    Duration? startPosition,
    bool autoPlay = false,
  }) =>
      _run(() => _activeEngine.open(
            source,
            startPosition: startPosition,
            autoPlay: autoPlay,
          ));

  Future<void> play() => _run(() => _activeEngine.play());
  Future<void> pause() => _run(() => _activeEngine.pause());
  Future<void> stop() => _run(() => _activeEngine.stop());
  Future<void> seek(Duration position) => _run(() => _activeEngine.seek(position));
  Future<void> setVolume(double volume) => _run(() => _activeEngine.setVolume(volume));
  Future<void> setRate(double rate) => _run(() => _activeEngine.setRate(rate));
  Future<Uint8List?> screenshot() => _run<Uint8List?>(() => _activeEngine.screenshot());
  Future<void> setShaders(String shaderList) => _run(() => _activeEngine.setShaders(shaderList));

  Future<T?> _run<T>(Future<T> Function() command) async {
    try {
      return await _operations.run(command);
    } catch (_) {
      // 页面退出后，静默取消尚未执行的控制命令。
      if (!_disposed) rethrow;
      return null;
    }
  }

  /// 切换内核并恢复快照；提交前失败时保留原内核，提交后由新内核承接异常。
  Future<bool> switchKernel(PlayerKernel target, PlayerSnapshot snapshot,
          {bool force = false, String? shaders}) async =>
      await _run(() async {
        if (!force && target == _activeEngine.kernel) return true;

        final current = _activeEngine;
        final source = snapshot.source;
        PlayerEngine? next;
        try {
          if (source != null) await current.pause();
          _ensureReady();
          next = engineFactory.create(target, adBlocker: adBlocker);
          await next.initialize();
          _ensureReady();
          if (source != null) {
            await next.open(
              source,
              startPosition: snapshot.position,
              autoPlay: false,
            );
            _ensureReady();
          }
          await next.setVolume(snapshot.volume);
          _ensureReady();
          await next.setRate(snapshot.rate);
          if (shaders != null && next.capabilities.supportsShader) {
            await next.setShaders(shaders);
          }
          _ensureReady();
        } catch (error, stackTrace) {
          await _cleanup(next?.dispose);
          if (_disposed) return false;
          LiggLogger().e('准备播放器内核失败', error: error, stackTrace: stackTrace);
          next = null;
        }

        if (next != null) {
          // 提交后只清理旧内核；准备失败时继续保留原内核。
          final previousSubscription = _engineSubscription;
          _engine = next;
          _subscribeToEngine(next);
          await _cleanup(previousSubscription?.cancel);
          await _cleanup(current.dispose);
        }
        if (!_disposed && source != null && snapshot.wasPlaying) {
          try {
            await _activeEngine.play();
          } catch (error, stackTrace) {
            if (!_disposed) _events.add(PlayerError(error, stackTrace));
          }
        }
        return !_disposed && next != null;
      }) ??
      false;

  Future<void> _cleanup(Future<void> Function()? action) async {
    try {
      await action?.call();
    } catch (error, stackTrace) {
      LiggLogger().e('清理播放器资源失败', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _updateWakelock();
    try {
      // 初始化异常由调用方处理，清理仍等待初始化和已提交的原生操作完成。
      if (_engineSubscription == null) {
        await _initialization?.catchError((Object _) {});
      }
      await _operations.drained;
      await _cleanup(_engineSubscription?.cancel);
      await _cleanup(_engine?.dispose);
      _engine = null;
      await _cleanup(_events.close);
    } finally {
      await _wakelockUpdates;
    }
  }

  void _subscribeToEngine(PlayerEngine engine) {
    _playing = false;
    _updateWakelock();
    _engineSubscription = engine.events.listen((event) {
      if (_disposed || engine != _engine || _events.isClosed) return;
      if (event is PlayerPlayingChanged) {
        _playing = event.playing;
        _updateWakelock();
      } else if (event is PlayerCompleted || event is PlayerError) {
        _playing = false;
        _updateWakelock();
      }
      _events.add(event);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    // 返回前台时，可能需要重新启用原生屏幕常亮。
    _updateWakelock(force: state == AppLifecycleState.resumed && _playing);
  }

  void _updateWakelock({bool force = false}) {
    final enabled = _keepScreenOn;
    if (!force && enabled == _requestedWakelock) return;
    _requestedWakelock = enabled;
    // 按顺序执行原生调用，避免延迟的启用请求在释放后生效。
    _wakelockUpdates =
        (_wakelockUpdates ?? Future<void>.value()).then((_) async {
      if (enabled && !_keepScreenOn) return;
      try {
        await WakelockPlus.toggle(enable: enabled);
      } catch (error, stackTrace) {
        if (_requestedWakelock == enabled) _requestedWakelock = !enabled;
        LiggLogger().e('设置播放屏幕常亮失败', error: error, stackTrace: stackTrace);
      }
    });
  }

  void _ensureReady() {
    if (_engineSubscription == null || _disposed) {
      throw StateError('PlaybackCoordinator is not initialized');
    }
  }
}
