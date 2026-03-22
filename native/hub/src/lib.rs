mod actors;
mod bt_downloader;
mod dash_downloader;
mod db;
mod download_manager;
mod downloader;
mod file_association;
mod ftp_downloader;
mod hls_downloader;
mod logger;
mod meta_prober;
mod native_messaging;
mod nmh_registry;
mod protocol_registry;
mod proxy_config;
mod segment_advisor;
mod segment_coordinator;
mod signals;
mod speed_limiter;
mod updater;

use actors::create_actors;
use rinf::{dart_shutdown, write_interface};
use tokio::spawn;

write_interface!();

#[tokio::main(flavor = "current_thread")]
async fn main() {
    logger::init();
    spawn(create_actors());
    dart_shutdown().await;
}
