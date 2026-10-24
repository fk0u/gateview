//! gateview-core — the platform-agnostic engine shared by the future Windows/Linux
//! (Tauri 2) shells. The Swift macOS app mirrors these modules; `theme.json` keeps
//! the same schema everywhere. Ports must stay behaviour-identical to
//! `GateView/Services/*.swift` (see docs/CROSSPLATFORM.md, milestone M0).

pub mod config;
pub mod countdown;
pub mod hijri;
pub mod l10n;
pub mod mood;
pub mod prayer;
pub mod weather;
