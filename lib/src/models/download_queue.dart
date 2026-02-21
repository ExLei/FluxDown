import '../bindings/bindings.dart';

/// 命名下载队列的 Dart 侧模型（对应 Rust QueueInfo）
class DownloadQueue {
  final String queueId;
  final String name;

  /// 速度限制（KB/s），0 = 不限制
  final int speedLimitKbps;

  /// 最大并发数，0 = 使用全局设置
  final int maxConcurrent;

  /// 默认保存目录，空 = 使用全局设置
  final String defaultSaveDir;

  /// 显示顺序（从小到大）
  final int position;

  const DownloadQueue({
    required this.queueId,
    required this.name,
    required this.speedLimitKbps,
    required this.maxConcurrent,
    required this.defaultSaveDir,
    required this.position,
  });

  factory DownloadQueue.fromQueueInfo(QueueInfo info) {
    return DownloadQueue(
      queueId: info.queueId,
      name: info.name,
      speedLimitKbps: info.speedLimitKbps,
      maxConcurrent: info.maxConcurrent,
      defaultSaveDir: info.defaultSaveDir,
      position: info.position,
    );
  }

  DownloadQueue copyWith({
    String? queueId,
    String? name,
    int? speedLimitKbps,
    int? maxConcurrent,
    String? defaultSaveDir,
    int? position,
  }) {
    return DownloadQueue(
      queueId: queueId ?? this.queueId,
      name: name ?? this.name,
      speedLimitKbps: speedLimitKbps ?? this.speedLimitKbps,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      defaultSaveDir: defaultSaveDir ?? this.defaultSaveDir,
      position: position ?? this.position,
    );
  }
}
