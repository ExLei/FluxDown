//! API 宿主契约 —— [`ApiHost`] trait。
//!
//! HTTP 层（`server`/`jsonrpc` 模块）只依赖本 trait，不关心宿主形态：
//! - 桌面/手机 App（hub）：实现为「命令 + oneshot 回执」桥接到 download_actor
//! - 未来 headless server：实现为直接调用 `fluxdown_engine::Engine`
//!
//! 换宿主不换 HTTP 层，这是「一份 API 契约、多宿主复用」的核心边界。

use std::collections::HashMap;

use tokio::sync::broadcast;

use async_trait::async_trait;

use crate::types::{CreateTaskRequest, DownloadRequest, QueueDto, TaskDto};

/// 404 fallback 响应的 message —— 请求命中了未注册的路由（例如管理 API 分组
/// 未启用时访问 `/api/v1/*`）。server 侧 fallback 与 CLI/客户端共用此常量，
/// 使「路由未注册」与「资源不存在（[`ApiError::NotFound`]，message `"not found"`）」
/// 两种 404 可被客户端区分，避免跨 crate 硬编码字符串漂移。
pub const UNKNOWN_ENDPOINT_MESSAGE: &str = "unknown endpoint";

/// API 操作错误。由 HTTP 层映射为响应状态码。
///
/// # Examples
///
/// ```
/// use fluxdown_api::service::ApiError;
///
/// let e = ApiError::BadRequest("url is required".to_string());
/// assert_eq!(e.to_string(), "url is required");
/// assert_eq!(ApiError::NotFound.to_string(), "not found");
/// ```
#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    /// 资源不存在 → 404。
    #[error("not found")]
    NotFound,
    /// 请求参数非法 → 400。
    #[error("{0}")]
    BadRequest(String),
    /// 宿主正在关闭（命令通道已断）→ 503。
    #[error("app shutting down")]
    Unavailable,
    /// 其它内部错误 → 500。
    #[error("{0}")]
    Internal(String),
}

/// API 宿主能力契约。所有方法与 `/api/v1` 端点一一对应，
/// 外加 [`submit_external`](ApiHost::submit_external)（接管/aria2 兼容入口）。
#[async_trait]
pub trait ApiHost: Send + Sync {
    /// 列出全部任务。
    async fn list_tasks(&self) -> Result<Vec<TaskDto>, ApiError>;

    /// 按 ID 查询单个任务。
    async fn get_task(&self, task_id: &str) -> Result<Option<TaskDto>, ApiError>;

    /// 直接创建下载任务（不弹确认框），返回新任务 ID。
    async fn create_task(&self, req: CreateTaskRequest) -> Result<String, ApiError>;

    /// 删除任务。`delete_files = true` 时同时删除磁盘文件。
    async fn delete_task(&self, task_id: &str, delete_files: bool) -> Result<(), ApiError>;

    /// 暂停单个任务。
    async fn pause_task(&self, task_id: &str) -> Result<(), ApiError>;

    /// 恢复单个任务。
    async fn continue_task(&self, task_id: &str) -> Result<(), ApiError>;

    /// 暂停全部活跃任务。
    async fn pause_all(&self) -> Result<(), ApiError>;

    /// 恢复全部已暂停任务。
    async fn continue_all(&self) -> Result<(), ApiError>;

    /// 列出全部命名队列。
    async fn list_queues(&self) -> Result<Vec<QueueDto>, ApiError>;

    /// 提交一个外部下载请求（浏览器脚本接管 / aria2 兼容层）。
    ///
    /// 语义与浏览器扩展 NMH 一致：进入宿主的「外部下载」流程
    /// （桌面端会弹出快速下载确认框），**不**直接创建任务。
    async fn submit_external(&self, req: DownloadRequest) -> Result<(), ApiError>;

    /// 读取全局配置表快照（config key → value，FluxDown 原生键名）。
    ///
    /// aria2 兼容层（`getGlobalOption`）经此读取后翻译为 aria2 选项名。
    /// 默认实现返回空表（宿主未接线时兼容层按「无配置」降级）。
    async fn get_config(&self) -> Result<HashMap<String, String>, ApiError> {
        Ok(HashMap::new())
    }

    /// 写入并 live-apply 一组配置键（FluxDown 原生键名 → 值）。
    ///
    /// 语义：先持久化到 config 表，再按键名热应用到引擎
    /// （镜像桌面 `SaveConfig` / server `ActorCmd::ApplyConfig` 路径）。
    /// 默认实现返回不支持错误。
    async fn apply_config(&self, changes: HashMap<String, String>) -> Result<(), ApiError> {
        let _ = changes;
        Err(ApiError::Internal(
            "config change not supported by this host".to_string(),
        ))
    }

    /// 全部任务的实时速率快照（task_id → 速率）。
    ///
    /// 数据来自宿主对引擎进度事件的内存态缓存，不落库；
    /// 默认实现返回空表（兼容层按 0 速率降级）。
    async fn live_speeds(&self) -> Result<HashMap<String, LiveSpeed>, ApiError> {
        Ok(HashMap::new())
    }

    /// 订阅任务生命周期事件（aria2 WebSocket 通知源）。
    ///
    /// 宿主在自己的引擎事件槽（EventSink）里检测任务状态迁移并广播
    /// [`TaskEvent`]；jsonrpc 层把它翻译成 `aria2.onDownloadXxx` 通知帧。
    /// 默认实现返回 `None`（宿主未接线时 `/jsonrpc` 不提供 WS 通知）。
    fn subscribe_task_events(&self) -> Option<broadcast::Receiver<TaskEvent>> {
        None
    }
}

/// 任务生命周期事件类别，一一对应 aria2 的 6 种 WS 通知。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskEventKind {
    /// 任务开始/恢复下载 → `aria2.onDownloadStart`。
    Start,
    /// 任务被暂停 → `aria2.onDownloadPause`。
    Pause,
    /// 任务被用户删除/停止 → `aria2.onDownloadStop`。
    Stop,
    /// 任务下载完成 → `aria2.onDownloadComplete`。
    Complete,
    /// 任务出错 → `aria2.onDownloadError`。
    Error,
    /// BT 任务数据下载完成（可能仍在做种）→ `aria2.onBtDownloadComplete`。
    BtComplete,
}

/// 单条任务生命周期事件。见 [`ApiHost::subscribe_task_events`]。
#[derive(Debug, Clone)]
pub struct TaskEvent {
    /// FluxDown 任务 ID（UUID；jsonrpc 层负责转 GID）。
    pub task_id: String,
    /// 事件类别。
    pub kind: TaskEventKind,
}

/// 单任务实时速率（bytes/sec）。见 [`ApiHost::live_speeds`]。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct LiveSpeed {
    /// 下载速率（bytes/sec）。
    pub download_bps: i64,
    /// 上传速率（bytes/sec，仅 BT 任务非 0）。
    pub upload_bps: i64,
}
