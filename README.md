# Flutter TVBox

多平台 TVBox。参考实现为 `../NovaTV-master`（原生 Android），
JS 引擎为 quickjs-ng 2026-06-04（与参考实现完全同源，bytecode 可直接复用）。

## 结构

```
packages/tvbox_core/    纯 Dart 共享层（零 Flutter 依赖）
  lib/src/js/           QuickJS 抽象：JsEngine（双实现并行：自建 FFI / flutter_qjs_next）
  lib/src/host/         JS 宿主能力：20 个全局函数、同步 HTTP、规则引擎、加解密
  lib/src/spider/       JsSpider（worker isolate）、采集站、模块加载器
  lib/src/config/       TVBox 配置解析
  lib/src/platform/     PlatformBridge：jar/py/路径等平台差异收敛点
apps/desktop/           桌面端（Windows / Linux / macOS），media_kit (libmpv)
apps/mobile/            移动端（暂未创建）
```

## 关键设计

- **同步 HTTP 是生死线**：JS 爬虫的 `req()` 是同步调用，Dart 没有同步 HTTP，
  所以 JS 引擎跑在独立 worker isolate（`SpiderRunner`），同步请求由
  `SyncHttpClient`（计划 libcurl FFI）在 native 层完成。
- **宿主 API 契约不可破坏**：`JsHostApi` 里每个函数都标注了参考实现出处，
  改名、改参数顺序、改默认值都会让现成爬虫静默失效。
- **bytecode 直通**：`//bb` 与 `//DRPY` 前缀的 base64 bytecode 原样透传给
  引擎，与参考实现共享同一套模块缓存格式。

## 状态

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 抽象层 + 组装骨架 | ✅ |
| P1 | 同步 HTTP（libcurl FFI） | ✅ 真实网络 8/8 通过 |
| P1 | QuickJS 引擎（C shim + dart:ffi） | ✅ 代码完成，CI 运行时验证 |
| P1 | JsCrypto / TextConverter | ⏳ |
| P2 | jsoup 规则引擎移植（pdfh/pd/pdfa/pdfla） | ⏳ |
| P3 | 桌面 UI、配置加载、本地代理服务 | ⏳ |
| P6 | jar（内嵌 JVM）、python（内嵌 libpython） | ⏳ |

## QuickJS 引擎层

- `native/quickjs_bridge.c`：稳定 ABI 层。所有 JSValue 走堆指针，Dart 回调全部
  void 签名（返回值经输出参数写回），宿主函数的 Dart 异常转成 JS Error。
- `packages/tvbox_native/lib/src/quickjs/`：FFI 绑定 + `QuickjsEngine`
  （实现 `JsEngine`），支持 evaluate / module / bytecode / 宿主函数注册 /
  模块加载器（bytecode 优先，源码现编译）。
- 验证方式：`native/build_bridge.sh` 编出动态库后
  `TVBOX_QJS_LIB=<so/dll> dart test --directory packages/tvbox_native`
  会跑完整 conformance 套件；CI（`.github/workflows/engine.yml`）
  在 ubuntu/windows 上自动编译并执行。

## 开发

```bash
cd apps/desktop
flutter create . --platforms=windows,linux,macos   # 首次生成平台工程
flutter run -d windows
```

引擎一致性测试（两条绑定路线跑同一套用例）：

```bash
cd packages/tvbox_core
dart test
```
