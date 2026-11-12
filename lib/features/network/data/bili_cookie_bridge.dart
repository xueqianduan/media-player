// -------------------------------------------------------------------------
// 功能：读取 WebView 里的 B 站登录 Cookie
//
// 主要内容：
// - 内嵌官方登录页登录完成后，从系统 CookieManager / WKWebsiteDataStore 取回凭证
// - 平台通道 lumiplayer/bili_cookie：cookies / clear
// - 非 Android / iOS 或通道不可用时返回空字符串，由调用方降级处理
//
// 说明：SESSDATA 是 HttpOnly Cookie，JavaScript 读不到，只能走原生侧读取。
// -------------------------------------------------------------------------

import 'package:flutter/services.dart';

/// 平台 Cookie 读取桥。
class BiliCookieBridge {
  const BiliCookieBridge._();

  static const MethodChannel _channel = MethodChannel('lumiplayer/bili_cookie');

  /// 读取 B 站域名下的 Cookie 头（形如 `SESSDATA=xxx; bili_jct=yyy`）。
  ///
  /// 未登录、无 WebView 数据或平台不支持时返回空字符串。
  static Future<String> read() async {
    try {
      final String? value = await _channel.invokeMethod<String>(
        'cookies',
        <String, dynamic>{
          // 主域与 passport 都读一次：SESSDATA 正常挂在 .bilibili.com，
          // 但个别流程会先写成子域 Cookie，合并读取更稳。
          'urls': <String>[
            'https://www.bilibili.com',
            'https://passport.bilibili.com',
          ],
        },
      );
      return value ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// 清空 WebView 的 Cookie（用于「切换账号」时强制回到登录页）。
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      // 清理失败不影响主流程：登录页里仍可手动退出账号。
    } on MissingPluginException {
      // 平台未实现，忽略。
    }
  }
}
