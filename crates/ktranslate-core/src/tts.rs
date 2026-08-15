//! Pronunciation through the operating system's own speech synthesiser.
//!
//! A free-tier feature precisely because it costs nothing per use: every
//! supported platform already ships a voice, so there is no API to pay for.

use std::process::{Command, Stdio};

#[derive(Debug, thiserror::Error)]
pub enum TtsError {
    #[error("nothing to speak")]
    Empty,

    #[error("no speech synthesiser available on this system")]
    Unavailable,

    #[error("could not start the speech synthesiser: {0}")]
    Spawn(String),
}

/// Whether this system can speak.
///
/// Always true on macOS (`say` is part of the OS) and Windows (PowerShell +
/// System.Speech). On Linux it depends on what is installed, which is why the
/// UI must gate the button on this rather than assume — a button that silently
/// does nothing is worse than no button.
pub fn is_available() -> bool {
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
        true
    }

    #[cfg(target_os = "linux")]
    {
        linux_command().is_some()
    }
}

#[cfg(target_os = "linux")]
fn linux_command() -> Option<&'static str> {
    ["spd-say", "espeak-ng", "espeak"].into_iter().find(|bin| {
        Command::new("sh")
            .arg("-c")
            .arg(format!("command -v {bin}"))
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    })
}

/// Speak `text`, returning as soon as the synthesiser has started.
///
/// Spawns rather than waiting: a long phrase takes seconds to read aloud, and
/// blocking on it would freeze the popup for the whole duration.
pub fn speak(text: &str) -> Result<(), TtsError> {
    let text = text.trim();
    if text.is_empty() {
        return Err(TtsError::Empty);
    }

    // The text is passed as an argument, never interpolated into a shell
    // string. It comes from an arbitrary selection, so a shell would happily
    // execute whatever punctuation it happens to contain.
    let mut command = platform_command(text)?;

    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|e| TtsError::Spawn(e.to_string()))
}

#[cfg(target_os = "macos")]
fn platform_command(text: &str) -> Result<Command, TtsError> {
    let mut c = Command::new("say");
    c.arg("--").arg(text);
    Ok(c)
}

#[cfg(target_os = "windows")]
fn platform_command(text: &str) -> Result<Command, TtsError> {
    // Single quotes are the PowerShell string delimiter, and doubling one is
    // how it is escaped. Without this a selection containing an apostrophe
    // breaks the script.
    let escaped = text.replace('\'', "''");
    let mut c = Command::new("powershell");
    c.arg("-NoProfile").arg("-Command").arg(format!(
        "Add-Type -AssemblyName System.Speech; \
         (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('{escaped}')"
    ));
    Ok(c)
}

#[cfg(target_os = "linux")]
fn platform_command(text: &str) -> Result<Command, TtsError> {
    let bin = linux_command().ok_or(TtsError::Unavailable)?;
    let mut c = Command::new(bin);
    c.arg("--").arg(text);
    Ok(c)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn speaking_empty_text_is_rejected_without_spawning_anything() {
        assert!(matches!(speak(""), Err(TtsError::Empty)));
        assert!(matches!(speak("   \n\t "), Err(TtsError::Empty)));
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn apostrophes_are_escaped_for_powershell() {
        // "don't" would otherwise terminate the PowerShell string early.
        let c = platform_command("don't").unwrap();
        let args: Vec<_> = c
            .get_args()
            .map(|a| a.to_string_lossy().into_owned())
            .collect();
        assert!(args.iter().any(|a| a.contains("don''t")));
    }

    #[test]
    #[cfg(not(target_os = "linux"))]
    fn tts_is_always_available_on_macos_and_windows() {
        assert!(is_available());
    }
}
