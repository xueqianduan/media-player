// -------------------------------------------------------------------------
// 功能：B 站账号状态控制器
//
// 主要内容：
// - 启动时恢复已保存登录态
// - 提供账号资料、刷新、退出，供首页账号模块与画质面板共用
// -------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bili_cookie_bridge.dart';
import '../data/bili_session.dart';

class BiliAccountState {
  const BiliAccountState({this.checking = true, this.account, this.error});

  final bool checking;
  final BiliAccount? account;
  final String? error;

  bool get loggedIn => account != null;

  BiliAccountState copyWith({
    bool? checking,
    BiliAccount? account,
    bool clearAccount = false,
    String? error,
    bool clearError = false,
  }) {
    return BiliAccountState(
      checking: checking ?? this.checking,
      account: clearAccount ? null : (account ?? this.account),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final Provider<BiliSessionService> biliSessionProvider =
    Provider<BiliSessionService>((Ref ref) {
      final BiliSessionService service = BiliSessionService();
      ref.onDispose(service.close);
      return service;
    });

class BiliAccountController extends Notifier<BiliAccountState> {
  @override
  BiliAccountState build() {
    Future<void>.microtask(refresh);
    return const BiliAccountState();
  }

  BiliSessionService get _session => ref.read(biliSessionProvider);

  Future<void> refresh() async {
    state = state.copyWith(checking: true, clearError: true);
    try {
      final BiliAccount? account = await _session.restore();
      state = BiliAccountState(
        checking: false,
        account: account,
        error: account == null && _session.isLoggedIn ? '账号状态检查失败' : null,
      );
    } on Object catch (error) {
      state = BiliAccountState(
        checking: false,
        account: state.account,
        error: '$error',
      );
    }
  }

  void applyLogin(BiliAccount account) {
    state = BiliAccountState(checking: false, account: account);
  }

  Future<void> logout() async {
    await _session.logout();
    // 同时清掉内嵌浏览器的 Cookie，否则下次打开登录页会被旧账号直接带进去。
    await BiliCookieBridge.clear();
    state = const BiliAccountState(checking: false);
  }
}

final NotifierProvider<BiliAccountController, BiliAccountState>
biliAccountProvider = NotifierProvider<BiliAccountController, BiliAccountState>(
  BiliAccountController.new,
);
