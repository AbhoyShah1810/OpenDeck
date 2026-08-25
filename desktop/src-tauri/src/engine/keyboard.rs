// ─────────────────────────────────────────────────────────────────────────────
// OpenDeck Engine — Keyboard Automation & Modifier Translation Layer
// ─────────────────────────────────────────────────────────────────────────────
// Maps abstract logical modifiers (e.g. PRIMARY_MOD) to OS-specific physical keys:
//  • macOS:   PRIMARY_MOD -> Cmd (Meta), ALT -> Option, CTRL -> Control, SHIFT -> Shift
//  • Windows: PRIMARY_MOD -> Control,    ALT -> Alt,    CTRL -> Control, SHIFT -> Shift
//  • Linux:   PRIMARY_MOD -> Control,    ALT -> Alt,    CTRL -> Control, SHIFT -> Shift

use enigo::{Direction, Enigo, Key, Keyboard, Settings};

/// Abstract modifier keys passed in ActionPayload
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AbstractModifier {
    PrimaryMod, // Cmd on macOS, Ctrl on Win/Linux
    Control,    // Ctrl on all OSes
    Alt,        // Alt / Option
    Shift,      // Shift
    Meta,       // Win key on Windows, Cmd on macOS
}

impl AbstractModifier {
    pub fn parse(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "PRIMARY_MOD" | "PRIMARY" | "CMD_OR_CTRL" => Some(Self::PrimaryMod),
            "CTRL" | "CONTROL" => Some(Self::Control),
            "ALT" | "OPTION" => Some(Self::Alt),
            "SHIFT" => Some(Self::Shift),
            "META" | "SUPER" | "WIN" | "CMD" | "COMMAND" => Some(Self::Meta),
            _ => None,
        }
    }

    /// Map abstract modifier to enigo::Key for current host operating system
    pub fn to_enigo_key(self) -> Key {
        match self {
            #[cfg(target_os = "macos")]
            Self::PrimaryMod => Key::Meta,
            #[cfg(not(target_os = "macos"))]
            Self::PrimaryMod => Key::Control,

            Self::Control => Key::Control,
            Self::Alt => Key::Alt,
            Self::Shift => Key::Shift,

            #[cfg(target_os = "macos")]
            Self::Meta => Key::Meta,
            #[cfg(not(target_os = "macos"))]
            Self::Meta => Key::Meta,
        }
    }
}

/// Parse string key representation into enigo::Key
pub fn parse_key(key_str: &str) -> Key {
    match key_str.to_lowercase().as_str() {
        "enter" | "return" => Key::Return,
        "tab" => Key::Tab,
        "space" | " " => Key::Space,
        "backspace" => Key::Backspace,
        "delete" | "del" => Key::Delete,
        "escape" | "esc" => Key::Escape,
        "up" | "arrowup" => Key::UpArrow,
        "down" | "arrowdown" => Key::DownArrow,
        "left" | "arrowleft" => Key::LeftArrow,
        "right" | "arrowright" => Key::RightArrow,
        "home" => Key::Home,
        "end" => Key::End,
        "pageup" | "pgup" => Key::PageUp,
        "pagedown" | "pgdn" => Key::PageDown,
        "f1" => Key::F1,
        "f2" => Key::F2,
        "f3" => Key::F3,
        "f4" => Key::F4,
        "f5" => Key::F5,
        "f6" => Key::F6,
        "f7" => Key::F7,
        "f8" => Key::F8,
        "f9" => Key::F9,
        "f10" => Key::F10,
        "f11" => Key::F11,
        "f12" => Key::F12,
        s if s.chars().count() == 1 => Key::Unicode(s.chars().next().unwrap()),
        _ => Key::Unicode(key_str.chars().next().unwrap_or(' ')),
    }
}

/// Synthesizes a key combination (modifiers down -> key click -> modifiers up)
pub fn simulate_hotkey(modifiers: &[String], key_str: &str) -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default()).map_err(|e| format!("Failed to init Enigo: {:?}", e))?;

    let parsed_mods: Vec<Key> = modifiers
        .iter()
        .filter_map(|m| AbstractModifier::parse(m))
        .map(|m| m.to_enigo_key())
        .collect();

    // Press all modifiers down
    for &m in &parsed_mods {
        let _ = enigo.key(m, Direction::Press);
    }

    // Click target key
    let target_key = parse_key(key_str);
    let _ = enigo.key(target_key, Direction::Click);

    // Release modifiers in reverse order
    for &m in parsed_mods.iter().rev() {
        let _ = enigo.key(m, Direction::Release);
    }

    log::info!("[engine/keyboard] Executed hotkey: {:?} + {}", modifiers, key_str);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_abstract_modifier_parsing() {
        assert_eq!(AbstractModifier::parse("PRIMARY_MOD"), Some(AbstractModifier::PrimaryMod));
        assert_eq!(AbstractModifier::parse("PRIMARY"), Some(AbstractModifier::PrimaryMod));
        assert_eq!(AbstractModifier::parse("ALT"), Some(AbstractModifier::Alt));
        assert_eq!(AbstractModifier::parse("OPTION"), Some(AbstractModifier::Alt));
        assert_eq!(AbstractModifier::parse("SHIFT"), Some(AbstractModifier::Shift));
        assert_eq!(AbstractModifier::parse("CTRL"), Some(AbstractModifier::Control));
        assert_eq!(AbstractModifier::parse("INVALID"), None);
    }

    #[test]
    fn test_modifier_host_mapping() {
        let primary = AbstractModifier::PrimaryMod.to_enigo_key();
        if cfg!(target_os = "macos") {
            assert_eq!(primary, Key::Meta);
        } else {
            assert_eq!(primary, Key::Control);
        }
    }
}

