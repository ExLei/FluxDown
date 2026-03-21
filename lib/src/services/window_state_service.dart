import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'log_service.dart';

const _tag = 'WindowState';

// SharedPreferences 存储 key（原生层 first_frame_cb 显示窗口前，
// Dart 侧在 runApp 之前直接 await 读取并应用）
const _kWindowX = 'window_state_x';
const _kWindowY = 'window_state_y';
const _kWindowWidth = 'window_state_width';
const _kWindowHeight = 'window_state_height';
const _kWindowMaximized = 'window_state_maximized';

/// 窗口最小尺寸限制
const _kMinWidth = 900.0;
const _kMinHeight = 500.0;

/// 窗口状态持久化服务。
///
/// ## 启动阶段（解决闪烁问题的关键）
///
/// `waitUntilReadyToShow` 的回调参数类型是 `VoidCallback`（不是 `Future`），
/// 内部通过 `callback()` 同步调用，async 回调中的 `await` 操作全部变成
/// fire-and-forget，与原生层 `first_frame_cb` 的 `gtk_widget_show` 竞争，
/// 导致窗口以默认 1280×720 先显示再跳变。
///
/// 解决方案：**完全不依赖回调**，在 `runApp` 之前直接 `await` 调用
/// `loadState()` → `applyState()`，所有 method-channel 调用同步完成后
/// 才进入 Flutter 渲染循环。当 `first_frame_cb` 触发 show 时，
/// 窗口属性已经就位。
///
/// ## 运行时
///
/// 通过 WindowListener 回调持久化窗口位置、大小、最大化状态，
/// 使用 500ms 防抖避免拖拽/调整大小时频繁写入。
class WindowStateService {
  WindowStateService._();

  static final WindowStateService instance = WindowStateService._();

  // ---------------------------------------------------------------------------
  // 启动阶段加载的窗口状态
  // ---------------------------------------------------------------------------

  double? _savedX;
  double? _savedY;
  double? _savedWidth;
  double? _savedHeight;
  bool _savedMaximized = false;

  /// 是否成功从 SharedPreferences 读取到了有效的宽高
  bool get hasSavedSize => _savedWidth != null && _savedHeight != null;

  /// 是否成功从 SharedPreferences 读取到了有效的位置
  bool get hasSavedPosition => _savedX != null && _savedY != null;

  /// 保存的窗口宽度（经过 clamp，至少 [_kMinWidth]）
  double get savedWidth =>
      (_savedWidth ?? 1280).clamp(_kMinWidth, double.infinity);

  /// 保存的窗口高度（经过 clamp，至少 [_kMinHeight]）
  double get savedHeight =>
      (_savedHeight ?? 720).clamp(_kMinHeight, double.infinity);

  // ---------------------------------------------------------------------------
  // 运行时状态
  // ---------------------------------------------------------------------------

  /// 防抖定时器
  Timer? _debounceTimer;

  /// 防抖延迟
  static const _debounceDuration = Duration(milliseconds: 500);

  /// 当前是否处于最大化状态
  bool _isMaximized = false;

  /// 最大化前的窗口位置和大小（最大化时保留正常尺寸用于持久化）
  Rect? _normalBounds;

  // ---------------------------------------------------------------------------
  // 启动阶段：加载 & 应用
  // ---------------------------------------------------------------------------

  /// 从 SharedPreferences 读取保存的窗口状态。
  ///
  /// 纯读取操作，不调用任何 windowManager API。
  /// 应在 `windowManager.ensureInitialized()` 之后调用。
  Future<void> loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedX = prefs.getDouble(_kWindowX);
      _savedY = prefs.getDouble(_kWindowY);
      _savedWidth = prefs.getDouble(_kWindowWidth);
      _savedHeight = prefs.getDouble(_kWindowHeight);
      _savedMaximized = prefs.getBool(_kWindowMaximized) ?? false;

      _isMaximized = _savedMaximized;

      // 初始化 _normalBounds 供后续最大化场景使用
      if (hasSavedSize) {
        _normalBounds = Rect.fromLTWH(
          _savedX ?? 0,
          _savedY ?? 0,
          savedWidth,
          savedHeight,
        );
      }

      logInfo(
        _tag,
        'loaded: position=($_savedX, $_savedY), '
        'size=(${_savedWidth}x$_savedHeight), '
        'maximized=$_savedMaximized',
      );
    } catch (e, stack) {
      logError(_tag, 'failed to load window state', e, stack);
    }
  }

  /// 在 `runApp` 之前调用，直接 `await` 设置窗口属性。
  ///
  /// 按严格顺序执行：setSize → setPosition/center → maximize。
  /// 所有操作通过 method-channel 同步完成后才返回，
  /// 确保后续 `first_frame_cb` show 窗口时属性已就位。
  ///
  /// **不调用 show / focus** — 窗口显示由原生层 `first_frame_cb`
  /// （非 silentStart）或后续 `windowManager.show()`（从托盘恢复）控制。
  Future<void> applyState() async {
    try {
      // 1) 设置窗口大小
      if (hasSavedSize) {
        await windowManager.setSize(Size(savedWidth, savedHeight));
        logInfo(_tag, 'applied size: ${savedWidth}x$savedHeight');
      } else {
        // 首次启动：使用默认大小
        await windowManager.setSize(const Size(1280, 720));
        logInfo(_tag, 'applied default size: 1280x720');
      }

      // 2) 设置窗口位置
      if (hasSavedPosition) {
        await windowManager.setPosition(Offset(_savedX!, _savedY!));
        logInfo(_tag, 'applied position: ($_savedX, $_savedY)');
      } else {
        // 没有保存的位置 → 居中
        await windowManager.setAlignment(Alignment.center);
        logInfo(_tag, 'applied center alignment (no saved position)');
      }

      // 3) 最大化（在 setSize/setPosition 之后）
      if (_savedMaximized) {
        await windowManager.maximize();
        logInfo(_tag, 'applied maximized');
      }
    } catch (e, stack) {
      logError(_tag, 'failed to apply window state', e, stack);
    }
  }

  // ---------------------------------------------------------------------------
  // 运行时：WindowListener 回调
  // ---------------------------------------------------------------------------

  /// 窗口移动时调用（防抖保存）
  void onMoved() {
    _debounceSave();
  }

  /// 窗口调整大小时调用（防抖保存）
  void onResized() {
    _debounceSave();
  }

  /// 窗口最大化时调用
  void onMaximized() {
    _isMaximized = true;
    _debounceSave();
  }

  /// 窗口从最大化恢复时调用
  void onUnmaximized() {
    _isMaximized = false;
    _debounceSave();
  }

  /// 立即保存当前窗口状态（用于退出/隐藏前确保状态持久化）
  Future<void> saveNow() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _save();
  }

  /// 释放资源
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  // ---------------------------------------------------------------------------
  // 内部方法
  // ---------------------------------------------------------------------------

  void _debounceSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, _save);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(_kWindowMaximized, _isMaximized);

      // 最大化状态下不更新位置和大小（保留正常状态的值，
      // 以便恢复时使用正确的窗口尺寸而非全屏尺寸）
      if (_isMaximized) {
        if (_normalBounds != null) {
          await prefs.setDouble(_kWindowX, _normalBounds!.left);
          await prefs.setDouble(_kWindowY, _normalBounds!.top);
          await prefs.setDouble(_kWindowWidth, _normalBounds!.width);
          await prefs.setDouble(_kWindowHeight, _normalBounds!.height);
          logInfo(
            _tag,
            'saved (maximized=true, normal bounds='
            '${_normalBounds!.left},${_normalBounds!.top} '
            '${_normalBounds!.width}x${_normalBounds!.height})',
          );
        } else {
          logInfo(_tag, 'saved (maximized=true, no normal bounds)');
        }
        return;
      }

      // 非最大化 → 获取当前窗口位置和大小
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();

      _normalBounds = Rect.fromLTWH(
        position.dx,
        position.dy,
        size.width,
        size.height,
      );

      await prefs.setDouble(_kWindowX, position.dx);
      await prefs.setDouble(_kWindowY, position.dy);
      await prefs.setDouble(_kWindowWidth, size.width);
      await prefs.setDouble(_kWindowHeight, size.height);

      logInfo(
        _tag,
        'saved: position=(${position.dx}, ${position.dy}), '
        'size=(${size.width}x${size.height}), maximized=false',
      );
    } catch (e, stack) {
      logError(_tag, 'failed to save window state', e, stack);
    }
  }
}
