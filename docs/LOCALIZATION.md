# MaterialLocalizations 原理与本次本地化事故复盘

> 影响版本：v1.0.0 ~ v1.0.3　修复版本：v1.0.4
> 结论一句话：App 声明了 `locale: zh_CN`，但没有提供中文的 Material 资源。所有依赖 `MaterialLocalizations` 的组件在创建阶段抛错；release 包把异常静默掉，于是表现为「点了没反应 / 页面空白」。

---

## 一、现象清单

| 入口 | 用户看到的现象 | 出错阶段 |
| --- | --- | --- |
| 多选操作栏：收藏 / 分类 / 播放列表 / 更多 | 按下有反馈，面板不出现、无遮罩 | 路由创建前 |
| 帮助与反馈的 7 条 FAQ | 整块卡片空白 | build 阶段 |
| 添加直播源 / 视频链接 | 点击后没有任何弹窗 | 路由创建前 |
| 分类页、播放列表页的 ⋮ 菜单 | 图标位置是空白，点不到 | build 阶段 |
| 搜索框 / 输入框长按 | 没有剪切、复制、粘贴菜单 | 构建选择菜单时 |
| 删除确认、重命名、新建分类 | 对话框不出现 | 路由创建前 |

---

## 二、原理

### 2.1 三个角色，各司其职

| 角色 | 作用 | 本项目取值 |
| --- | --- | --- |
| `Locale` | 要哪种语言 | `zh_CN`（写死） |
| `LocalizationsDelegate` | 谁能提供某种语言的资源 | 修复后：Global Material / Widgets / Cupertino |
| `Localizations` | InheritedWidget，装一张 `Type → 资源对象` 的表 | 由 `MaterialApp` 在根节点创建 |

`Locale` 是「需求」，delegate 是「供应商」，`Localizations` 是「货架」。货架上有什么，取决于哪个供应商说自己能供货。

### 2.2 装载阶段：只有说自己支持当前语言的 delegate 才会被调用

`packages/flutter/lib/src/widgets/localizations.dart:50-66`

```dart
for (final delegate in allDelegates) {
  if (!types.contains(delegate.type) && delegate.isSupported(locale)) {
    types.add(delegate.type);
    delegates.add(delegate);
  }
}
```

两条关键规则：

1. **只装载 `isSupported(locale) == true` 的 delegate**——不支持就整类跳过，不报错；
2. **同一类型只取第一个**——所以用户传入的 delegate 排在前，会覆盖框架默认值。

`GlobalMaterialLocalizations.delegate.load()` 返回 `SynchronousFuture`（`flutter_localizations/lib/src/material_localizations.dart:790`），所以启动时没有「资源还没加载完」的空窗期。

### 2.3 查询阶段：查不到只返回 null，抛错的是上层包装

`widgets/localizations.dart:619-623`

```dart
static T? of<T>(BuildContext context, Type type) {
  final scope = context.dependOnInheritedWidgetOfExactType<_LocalizationsScope>();
  return scope?.localizationsState.resourcesFor<T?>(type);   // 没有就是 null
}
```

`material_localizations.dart` 里的包装函数负责抛错：

```dart
static MaterialLocalizations of(BuildContext context) {
  final result = Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  if (result == null) {
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('No MaterialLocalizations found.'),
      ErrorDescription('... widgets require MaterialLocalizations to be provided ...'),
    ]);
  }
  return result;
}
```

**这就是为什么错误不会在启动时报出来**：缺资源不是「初始化失败」，而是「查询返回 null」，只有真正去查的代码才会炸。

### 2.4 默认委托只认英文

`material_localizations.dart:726`

```dart
bool isSupported(Locale locale) => locale.languageCode == 'en';
```

`MaterialApp` 在用户 delegates 之后追加两个默认值（`material/app.dart:935-941`）：

```dart
return <LocalizationsDelegate<dynamic>>[
  ...?widget.localizationsDelegates,
  DefaultMaterialLocalizations.delegate,   // 只支持 en
  DefaultCupertinoLocalizations.delegate,  // 只支持 en
];
```

`WidgetsApp` 再追加一个（`widgets/localizations.dart:832-839`）：

```dart
return <LocalizationsDelegate<Object?>>[
  ...?_localizationsDelegates,
  DefaultWidgetsLocalizations.delegate,    // isSupported 恒为 true
];
```

所以 `zh_CN` 下的结果是：

| 资源类型 | 是否在货架上 |
| --- | --- |
| `WidgetsLocalizations` | 有（默认委托对所有语言都返回 true） |
| `MaterialLocalizations` | **没有** |
| `CupertinoLocalizations` | **没有** |

### 2.5 MaterialLocalizations 到底提供什么

四类内容，全部是「框架组件自己的话」，不含业务文案：

| 类别 | 代表字段 | 用在哪 |
| --- | --- | --- |
| 无障碍语义标签 | `scrimLabel`、`modalBarrierDismissLabel`、`bottomSheetLabel`、`alertDialogLabel`、`showMenuTooltip`、`expansionTileExpandedTapHint` | 读屏器朗读 |
| 内置按钮文案 | `cancelButtonLabel`、`okButtonLabel`、`copyButtonLabel`、`pasteButtonLabel`、`selectAllButtonLabel` | 框架自带按钮 |
| 日期时间格式 | `formatMediumDate`、`formatTimeOfDay`、`narrowWeekdays`、`firstDayOfWeekIndex` | 日期 / 时间选择器 |
| 文本方向 | `textDirection` | RTL 语言整页镜像 |

业务文案（「收藏」「播放列表」）是写死在代码里的，和它无关——**补了本地化，界面文字一个都不会变**。

### 2.6 为什么 release 包里完全无感

1. `assert(debugCheckHasMaterialLocalizations(context))` 只在 debug 生效，release 被裁掉；
2. 抛出的 `FlutterError` 发生在 build 或手势回调里，被框架错误处理器接住，只写进 logcat；
3. 如果发生在 **build 阶段**：出错子树被替换成 `ErrorWidget`（release 下就是一块空白）；
4. 如果发生在 **路由创建之前**：`navigator.push` 根本没执行，界面上什么都不会发生。

---

## 三、诱因（为什么会写出这样的代码）

1. **语义上像一件事，实现上是两件事。** `locale`（我要中文）和 `localizationsDelegates`（谁提供）在 `MaterialApp` 里是两个相邻参数，很容易认为「声明了支持就等于支持了」。
2. **框架不做一致性校验。** `supportedLocales` 只是 `List<Locale>`，没有任何编译期或启动期断言检查「每个 locale 是否都有 delegate 支持」。
3. **默认值偏向英文。** 英文环境下不写 delegates 也完全正常，所以这段配置在开发早期永远是对的。
4. **错误被延迟。** 缺资源不影响启动、不影响列表、不影响播放器，只影响「第一次有人去查表」。
5. **测试环境与生产不一致。** `test/helpers/test_harness.dart` 的 `_TestApp` 没设 locale，走英文默认 → 全部用例通过，掩盖了问题。
6. **异常被静默。** release 下回调里的异常不改变 UI，用户只能描述为「点了没反应」。

---

## 四、触发条件

### 4.1 三个必要条件（同时满足才复现）

1. **解析后的 locale 不被任何 delegate 支持**：本项目 `zh_CN`，而 Material/Cupertino 默认委托只支持 `en`；
2. **代码路径上有人调用 `MaterialLocalizations.of(context)`**：业务代码不一定直接调，框架组件内部会调；
3. **调用发生在 build、路由创建或语义树构建阶段**：这决定了是「整块空白」还是「点了没反应」。

### 4.2 会触发的组件（实测 + 源码位置）

| 组件 / API | 取什么 | 时机 | 源码 |
| --- | --- | --- | --- |
| `showModalBottomSheet` | `scrimLabel`、`scrimOnTapHint` | push 之前 | `bottom_sheet.dart:1311` |
| `showDialog` | `modalBarrierDismissLabel` | push 之前 | `dialog.dart:1852` |
| `PopupMenuButton` | `showMenuTooltip`、`menuDismissLabel` | build | `popup_menu.dart:1784` |
| `ExpansionTile` | `expansionTileExpandedTapHint` 等 | build | `expansion_tile.dart:633` |
| `TextField` 长按 | `cutButtonLabel`、`copyButtonLabel` 等 | 构建选择菜单 | `adaptive_text_selection_toolbar.dart` |
| `Drawer` | 关闭抽屉的语义标签 | build | `drawer.dart` |
| `DatePicker` / `TimePicker` | 星期名、日期格式 | build | `date_picker.dart` |
| `SnackBar`（仅 `showCloseIcon: true`） | `closeButtonTooltip` | build | `snack_bar.dart:709` |

### 4.3 不会触发的组件

`Container`、`Row`、`Column`、`Stack`、`Icon`、`Text`、`ListView`、`Scaffold`、`IconButton`、`ListTile`、`Slider`、`BackButton`——它们不产生需要本地化的文案，实测源码中 `MaterialLocalizations.of` 的引用数为 0。

> 这也是本项目 95% 的界面看起来「完全正常」的原因：它们根本不在触发路径上。

---

## 五、影响面（本项目实际受损功能）

- 全部底部弹层：收藏夹、分类、播放列表、批量更多、单条更多、排序、同步面板
- 全部对话框：删除确认、重命名、新建分类 / 收藏夹 / 播放列表、添加链接
- 折叠列表：帮助与反馈 FAQ
- 弹出菜单：分类页、播放列表页的 ⋮
- 输入框长按选择菜单

---

## 六、修复

```yaml
# pubspec.yaml
dependencies:
  flutter_localizations:
    sdk: flutter
```

```dart
// lib/app/app.dart
localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```

代价：APK 从 33.49 MB 增到 33.89 MB（+393 KB）。

**为什么不给每个按钮打补丁**：问题不在按钮，而在「货架」。给单个入口传 `barrierLabel` 也绕不过去——`showModalBottomSheet` 里 `final localizations = MaterialLocalizations.of(context);` 这一行是无条件执行的，在 `push` 之前就把异常抛出来了。

---

## 七、与「普通组件」的对比

这里的「普通组件」指项目里大量使用的自绘方案：`Container` + `Row/Column` + `Icon` + `Text`，配合 `context.textPrimary` 之类的主题扩展。

| 维度 | 自绘组件（Container 系） | 框架 Material 组件 |
| --- | --- | --- |
| 本地化依赖 | 无 | 需要 Material / Widgets / Cupertino 资源 |
| 缺失依赖时表现 | 不存在该问题 | build 抛错 → 空白；路由前抛错 → 无反应 |
| 无障碍（读屏） | 要手写 `Semantics`，多数项目会漏 | 自带标签、点击提示、焦点管理 |
| 标准交互 | 全部自己实现（遮罩、返回键、拖拽、键盘避让） | 自带 |
| 视觉可控性 | 完全可控，想怎么画怎么画 | 受组件 API 约束，定制要改 theme |
| 主题一致性 | 手动取色，容易漏改 | 自动跟随 `ThemeData` |
| 代码量 | 每个页面重复，100+ 行起 | 一个函数调用 |
| 出错面 | 布局 / 手势 / 层级都要自己保证 | 由框架保证，但依赖环境正确 |
| 体积 | 0 | 框架内置，几乎 0（本地化 +393 KB） |
| 测试 | 直接 pump 即可 | 需要 locale / delegates 环境正确 |

### 优势与劣势小结

**自绘的优势**：零依赖、零环境要求、视觉完全自由、能与播放器手势层共享坐标系。
**自绘的劣势**：交互细节全部自负；无障碍几乎必然缺失；同类弹层在多个页面重复实现，一处改样式要改多处。

**框架组件的优势**：无障碍、返回键、遮罩、拖拽、焦点、键盘避让全部免费；行为与系统一致，用户不需要重新学习。
**框架组件的劣势**：必须满足「环境契约」（locale + delegates + theme + Directionality）；默认视觉带 Material 痕迹；出问题时是空白而不是报错，调试成本高。

### 本项目的取舍规则

1. **有标准交互语义的**（弹出来、收起来、选一个、输入文字、确认）→ 用框架组件。
2. **纯内容展示或需要品牌化视觉的**（视频卡片、详情头图、统计条）→ 自绘。
3. **与播放器手势 / 视频坐标系强耦合的**（控制条、手势面板、倍速刻度）→ 自绘，因为框架组件拿不到播放器的手势上下文。
4. **无论选哪种**，根节点必须把 `locale` + `localizationsDelegates` + `theme` 配齐——这是整个 App 的「环境契约」，不是某个页面的局部问题。

---

## 八、防复发清单

1. **根节点自检**：只要 `locale` 不是英文，就必须同时存在 `flutter_localizations` 和三个 delegate。
2. **测试环境对齐生产**：`_TestApp` 应加上与 `app.dart` 相同的 `locale` + delegates，否则这类问题永远测不出来。
3. **新加浮层时在 debug 包点一次**：debug 的 assert 会直接把错误抛到脸上。
4. **回调不要静默吞异常**：`_openSheet()` 里的 try/catch + toast 值得保留，它把「静默失败」变成了「可观测失败」。
5. **升级 Flutter 后跑一次冒烟**：打开一个底部弹窗、一个对话框、一个折叠面板。

---

## 九、源码索引

| 内容 | 位置 |
| --- | --- |
| 加载逻辑 | `flutter/lib/src/widgets/localizations.dart:50` |
| 查表 API | `flutter/lib/src/widgets/localizations.dart:619` |
| Widgets 默认委托 | `widgets/localizations.dart:832` |
| Material 默认委托 | `material/material_localizations.dart:722` |
| MaterialApp 合并 delegates | `material/app.dart:935` |
| 底部弹窗取文案 | `material/bottom_sheet.dart:1311` |
| 遮罩语义 | `widgets/modal_barrier.dart:237` |
| 折叠面板取文案 | `material/expansion_tile.dart:633` |
| 弹出菜单取文案 | `material/popup_menu.dart:1784` |
| 本项目根配置 | `lib/app/app.dart:22` |
| 本项目弹窗入口 | `lib/features/library/presentation/video_actions.dart:17` |
