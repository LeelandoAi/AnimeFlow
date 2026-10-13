import 'dart:async';
import 'dart:io';

import 'package:anime_flow/core/logger/logger.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart' as linux;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows;

/// 各平台网页视图、加载状态和资源生命周期。
class BrowserWebviewController extends ChangeNotifier {
  BrowserWebviewController({required String url, required this.title})
      : _url = url;

  final String title;
  String _url;
  WebViewController? _native;
  windows.WebviewController? _windows;
  linux.Webview? _linux;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;

  String get url => _url;
  bool get isLoading => _loading;
  bool get hasError => _failed;
  bool get isWindowOpen => _linux != null;

  /// Linux 使用独立窗口，其他平台返回可嵌入的网页组件。
  Widget? buildView() {
    if (_windows != null) return windows.Webview(_windows!);
    if (_native != null) return WebViewWidget(controller: _native!);
    return null;
  }

  Future<void> load() async {
    if (_disposed) return;
    _setLoading(true);
    try {
      if (Platform.isLinux) {
        if (_linux == null) {
          final window = await linux.WebviewWindow.create(
            configuration: linux.CreateConfiguration(title: title),
          );
          if (_disposed) {
            window.close();
            return;
          }
          _linux = window;
          window.setOnUrlRequestCallback((url) {
            _rememberUrl(url);
            return true;
          });
          unawaited(window.onClose.then((_) {
            if (_disposed) return;
            _linux = null;
            notifyListeners();
          }));
        }
        _linux!.launch(_url);
        _setLoading(false);
      } else if (Platform.isWindows) {
        if (_windows == null) {
          final controller = windows.WebviewController();
          await controller.initialize();
          // 初始化期间释放控制器时，立即清理刚创建的视图。
          if (_disposed) {
            await controller.dispose();
            return;
          }
          _windows = controller;
          _subscriptions.addAll([
            controller.url.listen(_rememberUrl),
            controller.loadingState.listen((state) {
              _setLoading(state != windows.LoadingState.navigationCompleted);
            }),
            controller.onLoadError.listen(_showError),
          ]);
          notifyListeners();
          await controller.setPopupWindowPolicy(
            windows.WebviewPopupWindowPolicy.sameWindow,
          );
        }
        if (!_disposed) await _windows!.loadUrl(_url);
      } else {
        if (_native == null) {
          final controller = WebViewController();
          await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
          await controller.setNavigationDelegate(NavigationDelegate(
            onPageStarted: (_) => _setLoading(true),
            onPageFinished: (_) => _setLoading(false),
            onUrlChange: (change) => _rememberUrl(change.url),
            onWebResourceError: (error) {
              if (error.isForMainFrame == true) _showError(error.description);
            },
          ));
          if (_disposed) return;
          _native = controller;
          notifyListeners();
        }
        if (!_disposed) await _native!.loadRequest(Uri.parse(_url));
      }
    } catch (error, stackTrace) {
      _showError(error, stackTrace);
    }
  }

  void _rememberUrl(String? url) {
    if (_disposed) return;
    final uri = Uri.tryParse(url ?? '');
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final next = uri.toString();
      if (next == _url) return;
      _url = next;
      notifyListeners();
    }
  }

  void _setLoading(bool loading) {
    if (_disposed) return;
    _loading = loading;
    if (loading) _failed = false;
    notifyListeners();
  }

  void _showError(Object error, [StackTrace? stackTrace]) {
    LiggLogger().e('加载网页失败', error: error, stackTrace: stackTrace);
    if (_disposed) return;
    _loading = false;
    _failed = true;
    notifyListeners();
  }

  Future<bool> openInBrowser() async {
    if (_disposed) return false;
    try {
      return await launchUrl(Uri.parse(_url),
          mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      LiggLogger().e('打开浏览器失败', error: error, stackTrace: stackTrace);
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(
        _windows?.dispose().catchError((Object error, StackTrace stackTrace) {
      LiggLogger().e('释放网页视图失败', error: error, stackTrace: stackTrace);
    }));
    _linux?.close();
    super.dispose();
  }
}
