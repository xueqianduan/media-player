// -------------------------------------------------------------------------
// 功能：B 站官方网页登录页
//
// 主要内容：
// - 用 WebView 打开 passport.bilibili.com 官方登录页（账号密码 / 短信验证码都在官方页面完成）
// - 登录过程中轮询系统 Cookie，拿到 SESSDATA 后交给 BiliSessionService 建立会话
// - 加载进度、失败重试、返回键交给页面内历史处理
//
// 说明：密码不经过本应用；B 站的极验滑块与风控由官方页面自己处理。
// -------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/bili_account_controller.dart';
import '../data/bili_cookie_bridge.dart';
import '../data/bili_session.dart';

/// 打开 B 站官方登录页，登录成功返回 true。
Future<bool?> showBiliLoginPage(BuildContext context) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (BuildContext _) => const BiliLoginPage()),
  );
}

class BiliLoginPage extends ConsumerStatefulWidget {
  const BiliLoginPage({super.key});

  @override
  ConsumerState<BiliLoginPage> createState() => _BiliLoginPageState();
}

class _BiliLoginPageState extends ConsumerState<BiliLoginPage> {
  static const String _loginUrl = 'https://passport.bilibili.com/login';

  /// 去掉 UA 里的 "; wv" 标记：部分站点的风控会把 WebView 与浏览器区别对待。
  static const String _androidUa =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  late final WebViewController _controller;
  Timer? _timer;

  int _progress = 0;
  bool _pageError = false;
  bool _finishing = false;
  String? _message;

  /// 上一次已尝试过的 Cookie：同一条凭证失败后不再重复请求，等它变化（用户真正登录）。
  String _lastTried = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageFinished: (String _) => _probe(),
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _pageError = true);
            }
          },
        ),
      );
    _boot();
    // 登录成功时 B 站不一定跳回我们能监听的地址，直接轮询 Cookie 最稳。
    _timer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (Timer _) => _probe(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    if (Platform.isAndroid) {
      await _controller.setUserAgent(_androidUa);
    }
    await _controller.loadRequest(Uri.parse(_loginUrl));
  }

  /// 读取系统 Cookie，出现 SESSDATA 就建立会话。
  Future<void> _probe() async {
    if (_finishing || !mounted) return;
    final String raw = await BiliCookieBridge.read();
    if (!mounted || !raw.contains('SESSDATA=')) return;
    if (raw == _lastTried) return;

    _finishing = true;
    _lastTried = raw;
    setState(() => _message = '正在确认登录状态…');
    try {
      final BiliAccount account = await ref
          .read(biliSessionProvider)
          .loginWithCookie(raw);
      if (!mounted) return;
      ref.read(biliAccountProvider.notifier).applyLogin(account);
      showToast(context, '已登录：${account.name}');
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      final bool retryable = error is BiliSessionException && error.retryable;
      setState(() {
        _finishing = false;
        // WebView 里残留的旧 Cookie 还没生效属于正常过程，不打扰用户；
        // 只有网络类错误需要提示。
        _message = retryable ? '$error' : null;
      });
      // 无论哪种失败，8 秒后允许用同一份 Cookie 再试一次：
      // 网络抖动会恢复，B 站也可能在跳转后才真正让会话生效。
      Timer(const Duration(seconds: 8), () {
        if (mounted) _lastTried = '';
      });
    }
  }

  void _close() => Navigator.of(context).pop(false);

  Future<void> _back() async {
    bool canGoBack = false;
    try {
      canGoBack = await _controller.canGoBack();
    } on Object {
      // WebView 还没挂载时可能抛错，直接退出页面。
      canGoBack = false;
    }
    if (canGoBack) {
      await _controller.goBack();
      return;
    }
    if (mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _buildHeader(context),
              if (_progress < 100)
                LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  backgroundColor: const Color(0xFFEDEFF6),
                  color: AppColors.primary,
                ),
              if (_message != null) _buildMessage(context),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    WebViewWidget(controller: _controller),
                    if (_pageError) _buildError(context),
                  ],
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: _back,
            icon: Icon(
              Icons.close_rounded,
              size: 22,
              color: context.textPrimary,
            ),
          ),
          Expanded(
            child: Text(
              '登录 B 站',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() => _pageError = false);
              _controller.reload();
            },
            icon: Icon(
              Icons.refresh_rounded,
              size: 20,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(BuildContext context) {
    final bool busy = _finishing;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: busy
          ? AppColors.primary.withValues(alpha: 0.06)
          : const Color(0xFFFDECEC),
      child: Row(
        children: <Widget>[
          if (busy)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            )
          else
            const Icon(
              Icons.info_outline_rounded,
              size: 13,
              color: Color(0xFFE24B4A),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: busy ? context.textSecondary : const Color(0xFFE24B4A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: context.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              '登录页加载失败，请检查网络',
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _pageError = false;
                  _progress = 0;
                });
                _controller.reload();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Text(
        '账号密码只在 B 站官方页面输入，LumiPlayer 不接触也不保存你的密码；'
        '登录后仅保存平台下发的凭证，用于请求更高画质的直播流。',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.6,
          color: context.textSecondary.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
