// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck Engine — Shell & Command Execution Handler
// ─────────────────────────────────────────────────────────────────────────────
// Safely parses and executes direct shell scripts and terminal commands with
// argument parsing via `shell-words`.

use std::process::Command;

/// Execution result of a shell command
#[derive(Debug, Clone)]
pub struct ShellResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// Executes a command line payload string safely.
/// Example payload: "open -a 'Visual Studio Code'" or "obs --startstreaming"
pub fn execute_shell_command(cmd_payload: &str) -> Result<ShellResult, String> {
    if cmd_payload.trim().is_empty() {
        return Err("Empty command payload".into());
    }

    // Split command into executable and args via shell-words
    let words = shell_words::split(cmd_payload)
        .map_err(|e| format!("Failed to parse shell command arguments: {}", e))?;

    if words.is_empty() {
        return Err("No executable command found in payload".into());
    }

    let program = &words[0];
    let args = &words[1..];

    log::info!("[engine/shell] Executing: program='{}', args={:?}", program, args);

    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|e| format!("Failed to launch process '{}': {}", program, e))?;

    let exit_code = output.status.code().unwrap_or(-1);
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        log::warn!("[engine/shell] Command exit code {}: stderr={}", exit_code, stderr);
    } else {
        log::info!("[engine/shell] Command executed successfully");
    }

    Ok(ShellResult {
        exit_code,
        stdout,
        stderr,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_echo_command() {
        let res = execute_shell_command("echo 'OpenDeck Test'").unwrap();
        assert_eq!(res.exit_code, 0);
        assert!(res.stdout.contains("OpenDeck Test"));
    }

    #[test]
    fn test_empty_command() {
        assert!(execute_shell_command("").is_err());
    }
}

