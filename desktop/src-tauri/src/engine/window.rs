/// Active window focus listener — placeholder for Phase 2.3 / Phase 5.1
/// Will use platform-specific APIs to track foreground process (VS Code, OBS, etc.)
pub fn get_active_window_id() -> String {
    // TODO Phase 5.1: Implement via macOS NSWorkspace / Windows GetForegroundWindow
    "unknown".to_string()
}
