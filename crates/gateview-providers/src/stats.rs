//! CPU / RAM sampling via sysinfo — works on Windows, macOS and Linux.

use sysinfo::System;

pub struct Stats {
    system: System,
}

impl Stats {
    pub fn new() -> Self {
        let mut system = System::new();
        system.refresh_cpu_usage();
        system.refresh_memory();
        Stats { system }
    }

    /// Call at most a couple of times per second; the first call after a refresh returns stale CPU.
    pub fn sample(&mut self) -> Sample {
        self.system.refresh_cpu_usage();
        self.system.refresh_memory();
        Sample {
            cpu: self.system.global_cpu_usage(),
            ram_percent: self.system.used_memory() as f64 / self.system.total_memory().max(1) as f64 * 100.0,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct Sample {
    pub cpu: f32,
    pub ram_percent: f64,
}
