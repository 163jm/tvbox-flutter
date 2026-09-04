import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// libcurl 的 dart:ffi 绑定。
///
/// 只绑定 easy 接口所需的子集——同步 HTTP 在 worker isolate 里
/// 串行执行，用不上 multi 接口。
///
/// `curl_easy_setopt` 是 varargs 函数，FFI 无法直接声明。
/// 做法是把同一个符号按两种实参形态（int64 / 指针）各 lookup 一次，
/// 再 asFunction 成具体签名——在 x64 / arm64 调用约定下整型与指针
/// 实参落在同一参数寄存器，这种处理是安全的，也是各语言绑定的通行做法。
class CurlLib {
  CurlLib._(this._lib) {
    _globalInit = _lib
        .lookupFunction<Int32 Function(Int32), int Function(int)>(
          'curl_global_init',
        );
    _versionFn = _lib.lookupFunction<Pointer<Utf8> Function(),
        Pointer<Utf8> Function()>('curl_version');
    _easyInit = _lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'curl_easy_init',
        );
    _easyCleanupFn = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('curl_easy_cleanup');
    _performFn = _lib.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('curl_easy_perform');
    _strerrorFn = _lib.lookupFunction<Pointer<Utf8> Function(Int32),
        Pointer<Utf8> Function(int)>('curl_easy_strerror');
    _slistAppendFn = _lib.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(
            Pointer<Void>, Pointer<Utf8>)>('curl_slist_append');
    _slistFreeAllFn = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('curl_slist_free_all');

    // setopt：同一符号按两种实参形态 lookup
    final setoptLongNp = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32, Int64)>>(
          'curl_easy_setopt',
        );
    final setoptPtrNp = _lib.lookup<
        NativeFunction<Int32 Function(Pointer<Void>, Int32, Pointer<Void>)>>(
      'curl_easy_setopt',
    );
    _setoptLong = setoptLongNp.asFunction<int Function(Pointer<Void>, int, int)>();
    _setoptPtr = setoptPtrNp
        .asFunction<int Function(Pointer<Void>, int, Pointer<Void>)>();

    final code = _globalInit(0);
    if (code != 0) throw StateError('curl_global_init 失败: $code');
  }

  final DynamicLibrary _lib;

  late final int Function(int) _globalInit;
  late final Pointer<Utf8> Function() _versionFn;
  late final Pointer<Void> Function() _easyInit;
  late final void Function(Pointer<Void>) _easyCleanupFn;
  late final int Function(Pointer<Void>) _performFn;
  late final Pointer<Utf8> Function(int) _strerrorFn;
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>) _slistAppendFn;
  late final void Function(Pointer<Void>) _slistFreeAllFn;

  late final int Function(Pointer<Void>, int, int) _setoptLong;
  late final int Function(Pointer<Void>, int, Pointer<Void>) _setoptPtr;

  static CurlLib? _instance;

  /// 打开 libcurl（进程内单例）。
  ///
  /// [path] 显式指定动态库路径；否则按各平台常见名字逐个尝试。
  /// Windows 分发时请把官方构建的 `libcurl-x64.dll` 放进应用目录。
  static CurlLib open({String? path}) {
    return _instance ??= CurlLib._(_open(path));
  }

  static DynamicLibrary _open(String? path) {
    if (path != null) return DynamicLibrary.open(path);
    if (Platform.isWindows) {
      for (final name in const ['libcurl-x64.dll', 'libcurl-4.dll']) {
        try {
          return DynamicLibrary.open(name);
        } catch (_) {
          continue;
        }
      }
      throw StateError(
        '未找到 libcurl。请将 libcurl-x64.dll 随应用分发到可执行目录，'
        '或通过 CurlLib.open(path: ...) 显式指定。',
      );
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('/usr/lib/libcurl.dylib');
    }
    // Linux 发行版均自带
    return DynamicLibrary.open('libcurl.so.4');
  }

  String get version => _versionFn().toDartString();

  Pointer<Void> easyInit() => _easyInit();

  void easyCleanup(Pointer<Void> easy) => _easyCleanupFn(easy);

  /// 同步执行。返回 CURLcode，0 = CURLE_OK。
  int perform(Pointer<Void> easy) => _performFn(easy);

  String strerror(int code) => _strerrorFn(code).toDartString();

  /// libcurl 7.17.0 起，字符串选项在 setopt 时即被复制，
  /// 因此这里的 native 副本用完即弃是安全的。
  void setoptLong(Pointer<Void> easy, int option, int value) {
    _check(_setoptLong(easy, option, value), option);
  }

  void setoptPtr(Pointer<Void> easy, int option, Pointer<Void> value) {
    _check(_setoptPtr(easy, option, value), option);
  }

  void setoptString(Pointer<Void> easy, int option, String value) {
    final ptr = value.toNativeUtf8();
    try {
      _check(_setoptPtr(easy, option, ptr.cast()), option);
    } finally {
      malloc.free(ptr);
    }
  }

  void _check(int code, int option) {
    if (code != 0) {
      throw StateError('curl_easy_setopt($option) 失败: ${strerror(code)}');
    }
  }
}

/// slist 的安全封装：Dart 字符串 → native 副本的生命周期一起管。
class CurlHeaderList {
  CurlHeaderList(this._curl, List<String> lines) {
    for (final line in lines) {
      final ptr = line.toNativeUtf8();
      try {
        final node = _curl._slistAppendFn(_head ?? nullptr, ptr);
        if (node == nullptr) throw StateError('curl_slist_append 失败');
        _head = node;
      } finally {
        malloc.free(ptr);
      }
    }
  }

  final CurlLib _curl;
  Pointer<Void>? _head;

  Pointer<Void>? get raw => _head;

  void dispose() {
    final h = _head;
    if (h != null) _curl._slistFreeAllFn(h);
    _head = null;
  }
}

/// 响应缓冲收集。
class CurlResponseBuffer {
  final BytesBuilder body = BytesBuilder();
  final List<int> headerBytes = <int>[];
}
