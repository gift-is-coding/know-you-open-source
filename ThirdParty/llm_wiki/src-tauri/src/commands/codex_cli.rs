//! Codex CLI subprocess transport.
//!
//! This mirrors the Claude Code CLI integration conceptually: the
//! webview cannot execute arbitrary commands. It can only ask Rust to
//! locate and run the hardcoded `codex` binary as a text-completion
//! backend. Codex's own auth comes from the user's existing ~/.codex
//! login.

use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use serde::Serialize;
use tokio::process::Command;
use uuid::Uuid;

#[derive(Serialize)]
pub struct DetectResult {
    installed: bool,
    version: Option<String>,
    path: Option<String>,
    error: Option<String>,
}

fn find_codex_command() -> Result<PathBuf, String> {
    if let Ok(path) = which::which("codex") {
        return Ok(path);
    }

    #[cfg(target_os = "macos")]
    {
        let bundled = PathBuf::from("/Applications/Codex.app/Contents/Resources/codex");
        if bundled.is_file() {
            return Ok(bundled);
        }
    }

    Err("`codex` not found on PATH".to_string())
}

#[tauri::command]
pub async fn codex_cli_detect() -> Result<DetectResult, String> {
    let path = match find_codex_command() {
        Ok(p) => p,
        Err(error) => {
            return Ok(DetectResult {
                installed: false,
                version: None,
                path: None,
                error: Some(error),
            });
        }
    };

    let path_str = path.to_string_lossy().to_string();
    let output = tokio::time::timeout(
        Duration::from_secs(3),
        Command::new(&path).arg("--version").output(),
    )
    .await;

    match output {
        Ok(Ok(out)) if out.status.success() => Ok(DetectResult {
            installed: true,
            version: Some(String::from_utf8_lossy(&out.stdout).trim().to_string()),
            path: Some(path_str),
            error: None,
        }),
        Ok(Ok(out)) => {
            let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
            Ok(DetectResult {
                installed: false,
                version: None,
                path: Some(path_str),
                error: Some(if stderr.is_empty() {
                    format!("`codex --version` exited with {}", out.status)
                } else {
                    stderr
                }),
            })
        }
        Ok(Err(e)) => Ok(DetectResult {
            installed: false,
            version: None,
            path: Some(path_str),
            error: Some(format!("Failed to spawn `codex`: {e}")),
        }),
        Err(_) => Ok(DetectResult {
            installed: false,
            version: None,
            path: Some(path_str),
            error: Some("`codex --version` timed out after 3s".to_string()),
        }),
    }
}

#[tauri::command]
pub async fn codex_cli_complete(model: String, prompt: String) -> Result<String, String> {
    let codex = find_codex_command()?;
    let output_path = std::env::temp_dir().join(format!("llm-wiki-codex-{}.txt", Uuid::new_v4()));

    let mut cmd = Command::new(&codex);
    cmd.arg("exec")
        .arg("--skip-git-repo-check")
        .arg("--ephemeral")
        .arg("--output-last-message")
        .arg(&output_path);

    if !model.trim().is_empty() {
        cmd.arg("--model").arg(model.trim());
    }

    cmd.arg(prompt)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let output = tokio::time::timeout(Duration::from_secs(30 * 60), cmd.output())
        .await
        .map_err(|_| "`codex exec` timed out after 30 minutes".to_string())?
        .map_err(|e| format!("Failed to spawn `codex`: {e}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        let detail = if !stderr.is_empty() { stderr } else { stdout };
        let hint = "If this is an authentication error, open Codex or run `codex` in a terminal to refresh ~/.codex login.";
        let _ = tokio::fs::remove_file(&output_path).await;
        return Err(if detail.is_empty() {
            format!("codex CLI exited with {}. {hint}", output.status)
        } else {
            format!("codex CLI exited with {}: {detail}\n{hint}", output.status)
        });
    }

    let text = tokio::fs::read_to_string(&output_path)
        .await
        .map_err(|e| format!("codex CLI did not write output file: {e}"))?;
    let _ = tokio::fs::remove_file(&output_path).await;

    let trimmed = text.trim().to_string();
    if trimmed.is_empty() {
        Err("codex CLI returned empty output".to_string())
    } else {
        Ok(trimmed)
    }
}
