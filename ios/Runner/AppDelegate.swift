import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// 必须持有引用，否则方法通道会被释放。
  private var biliCookieChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 供内嵌 B 站登录页读取 / 清理 WebView Cookie：
    // SESSDATA 是 HttpOnly，JavaScript 读不到，只能从 WKWebsiteDataStore 取。
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BiliCookieBridge") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "lumiplayer/bili_cookie",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "cookies":
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
          let matched = cookies
            .filter { $0.domain.hasSuffix("bilibili.com") }
            .sorted { lhs, rhs in
              // .bilibili.com 优先，避免子域同名 Cookie 覆盖主域
              (lhs.domain == ".bilibili.com" ? 0 : 1) < (rhs.domain == ".bilibili.com" ? 0 : 1)
            }
          var seen = Set<String>()
          var parts: [String] = []
          for cookie in matched where !seen.contains(cookie.name) {
            seen.insert(cookie.name)
            parts.append("\(cookie.name)=\(cookie.value)")
          }
          result(parts.joined(separator: "; "))
        }
      case "clear":
        WKWebsiteDataStore.default().removeData(
          ofTypes: [WKWebsiteDataTypeCookies],
          modifiedSince: Date.distantPast
        ) {
          result(true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    biliCookieChannel = channel
  }
}
