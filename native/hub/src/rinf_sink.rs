//! `EventSink` 实现 —— 把 `EngineEvent` 变体转发为具体 Dart 信号。
//!
//! 这是现状 hub 内 22 处 `.send_signal_to_dart()` 调用点的收敛,内容是搬移
//! 而非新写业务逻辑。
//!
//! 附带维护 aria2 兼容层 `ApiHost::live_speeds()` 所需的实时速率表:监听
//! `EngineEvent::TaskProgress`,活跃状态(pending/downloading/preparing)写入
//! 当前速率,终态(paused/completed/error)移除条目。任务删除也走这条路径——
//! `DownloadManager::delete_task`/`delete_tasks_batch` 会经 `progress_reporter`
//! 补发一条 `status=4` 的终态 `TaskProgress`(用于清理其自身内部状态表),
//! 因此无需在各删除命令处理点单独清理本表。

use std::collections::HashMap;

use fluxdown_api::service::LiveSpeed;
use fluxdown_engine::events::{EngineEvent, EventSink};
use rinf::RustSignal;

use crate::api_host::{LiveSpeedMap, lock_or_recover};
use crate::signals;

/// 桥接 `EngineEvent` 到 `hub::signals::*` 具体信号类型的 `EventSink` 实现。
pub struct RinfEventSink {
    /// `task_id → 实时速率`。与注入 `HubApiHost` 的是同一个 `Arc`
    /// (构造点见 `download_actor::run`),供 `ApiHost::live_speeds()` 读取。
    live_speeds: LiveSpeedMap,
}

impl RinfEventSink {
    /// `live_speeds`:必须与传给 `HubApiHost::new` 的是同一个 `Arc`。
    pub fn new(live_speeds: LiveSpeedMap) -> Self {
        Self { live_speeds }
    }
}

/// 按任务进度状态更新/清除实时速率表条目:活跃状态(0=pending/1=downloading/
/// 5=preparing)写入当前速率;其余(2=paused/3=completed/4=error,含删除的
/// 终态补发)移除——这些状态之后引擎不会再为该任务发送 `TaskProgress`,残留
/// 的旧速率值若不清理会一直 stale。纯函数,便于单测覆盖每个状态码分支。
///
/// 引擎目前只在 `TaskProgress` 里上报单一 `speed`(下载速率);BT 任务的
/// 上传速率尚未经 `EngineEvent` 透传(仅存在于 `bt_downloader.rs` 内部日志
/// 变量,未接入任何事件),故 `upload_bps` 暂恒为 0——待引擎侧补上对应字段
/// 后再接线,不在本次改动范围内。
fn apply_task_progress_speed(
    map: &mut HashMap<String, LiveSpeed>,
    task_id: &str,
    status: i32,
    speed: i64,
) {
    match status {
        0 | 1 | 5 => {
            map.insert(
                task_id.to_string(),
                LiveSpeed {
                    download_bps: speed,
                    upload_bps: 0,
                },
            );
        }
        _ => {
            map.remove(task_id);
        }
    }
}

impl EventSink for RinfEventSink {
    fn emit(&self, event: EngineEvent) {
        match event {
            EngineEvent::TaskProgress {
                task_id,
                status,
                downloaded_bytes,
                total_bytes,
                speed,
                file_name,
                save_dir,
                url,
                error_message,
            } => {
                {
                    let mut speeds = lock_or_recover(&self.live_speeds);
                    apply_task_progress_speed(&mut speeds, &task_id, status, speed);
                }
                signals::TaskProgress {
                    task_id,
                    status,
                    downloaded_bytes,
                    total_bytes,
                    speed,
                    file_name,
                    save_dir,
                    url,
                    error_message,
                }
                .send_signal_to_dart();
            }
            EngineEvent::TasksSnapshot(tasks) => {
                signals::AllTasks {
                    tasks: tasks.into_iter().map(Into::into).collect(),
                }
                .send_signal_to_dart();
            }
            EngineEvent::SegmentProgress {
                task_id,
                total_bytes,
                segment_count,
                segments,
            } => {
                signals::SegmentProgress {
                    task_id,
                    total_bytes,
                    segment_count,
                    segments: segments.into_iter().map(Into::into).collect(),
                }
                .send_signal_to_dart();
            }
            EngineEvent::TaskMetaProbed {
                task_id,
                file_name,
                total_bytes,
            } => {
                signals::TaskMetaProbed {
                    task_id,
                    file_name,
                    total_bytes,
                }
                .send_signal_to_dart();
            }
            EngineEvent::QueuePositionsChanged(positions) => {
                signals::QueuePositionsUpdate {
                    positions: positions.into_iter().map(Into::into).collect(),
                }
                .send_signal_to_dart();
            }
            EngineEvent::QueuesChanged(queues) => {
                signals::AllQueues {
                    queues: queues.into_iter().map(Into::into).collect(),
                }
                .send_signal_to_dart();
            }
            EngineEvent::PriorityTaskChanged {
                priority_task_id,
                auto_paused_count,
            } => {
                signals::PriorityTaskChanged {
                    priority_task_id,
                    auto_paused_count,
                }
                .send_signal_to_dart();
            }
            EngineEvent::SegmentSplit {
                task_id,
                parent_index,
                parent_new_end,
                child_index,
                child_start,
                child_end,
                is_proactive,
                total_segments,
            } => {
                signals::SegmentSplitEvent {
                    task_id,
                    parent_index,
                    parent_new_end,
                    child_index,
                    child_start,
                    child_end,
                    is_proactive,
                    total_segments,
                }
                .send_signal_to_dart();
            }
            EngineEvent::FileMissingChanged(updates) => {
                signals::FileMissingChanged {
                    updates: updates
                        .into_iter()
                        .map(|(task_id, missing)| signals::FileMissingUpdate { task_id, missing })
                        .collect(),
                }
                .send_signal_to_dart();
            }
            // `#[non_exhaustive]`：未来新增变体默认丢弃并记录日志，而非编译失败。
            _ => {
                crate::logger::log_info!(
                    "[rinf-sink] unhandled EngineEvent variant (added after this match was written)"
                );
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use fluxdown_api::service::LiveSpeed;

    use super::apply_task_progress_speed;

    #[test]
    fn downloading_status_upserts_speed() {
        let mut map = HashMap::new();
        apply_task_progress_speed(&mut map, "t1", 1, 1024);
        assert_eq!(
            map.get("t1"),
            Some(&LiveSpeed {
                download_bps: 1024,
                upload_bps: 0
            })
        );
    }

    #[test]
    fn pending_and_preparing_also_upsert() {
        let mut map = HashMap::new();
        apply_task_progress_speed(&mut map, "t1", 0, 10);
        assert!(map.contains_key("t1"));
        apply_task_progress_speed(&mut map, "t2", 5, 20);
        assert!(map.contains_key("t2"));
    }

    #[test]
    fn completed_status_removes_entry() {
        let mut map = HashMap::new();
        apply_task_progress_speed(&mut map, "t1", 1, 1024);
        apply_task_progress_speed(&mut map, "t1", 3, 0);
        assert!(!map.contains_key("t1"));
    }

    #[test]
    fn paused_status_removes_entry() {
        let mut map = HashMap::new();
        apply_task_progress_speed(&mut map, "t1", 1, 1024);
        apply_task_progress_speed(&mut map, "t1", 2, 0);
        assert!(!map.contains_key("t1"));
    }

    #[test]
    fn error_status_removes_entry_covers_delete_path() {
        // status=4 也是 delete_task/delete_tasks_batch 补发的终态标记,
        // 覆盖“删除后不留残余速率”这条路径。
        let mut map = HashMap::new();
        apply_task_progress_speed(&mut map, "t1", 1, 1024);
        apply_task_progress_speed(&mut map, "t1", 4, 0);
        assert!(!map.contains_key("t1"));
    }

    #[test]
    fn removing_absent_entry_is_noop() {
        let mut map: HashMap<String, LiveSpeed> = HashMap::new();
        apply_task_progress_speed(&mut map, "ghost", 3, 0);
        assert!(map.is_empty());
    }
}
