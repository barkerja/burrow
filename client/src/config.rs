//! Configuration management for the Burrow client.
//!
//! Handles loading and saving configuration from `~/.burrow/config.toml`.

use anyhow::{Context, Result};
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fmt;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub auth: AuthConfig,
}

#[derive(Default, Serialize, Deserialize)]
pub struct AuthConfig {
    pub token: Option<String>,
    pub server: Option<String>,
}

impl fmt::Debug for AuthConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AuthConfig")
            .field("token", &self.token.as_ref().map(|_| "[REDACTED]"))
            .field("server", &self.server)
            .finish()
    }
}

impl Config {
    pub fn load() -> Result<Self> {
        let path = Self::config_path()?;

        if !path.exists() {
            return Ok(Self::default());
        }

        let contents = fs::read_to_string(&path)
            .with_context(|| format!("Failed to read config file: {}", path.display()))?;

        toml::from_str(&contents)
            .with_context(|| format!("Failed to parse config file: {}", path.display()))
    }

    pub fn save(&self) -> Result<()> {
        let path = Self::config_path()?;

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).with_context(|| {
                format!("Failed to create config directory: {}", parent.display())
            })?;
        }

        let contents = toml::to_string_pretty(self).context("Failed to serialize config")?;

        fs::write(&path, contents)
            .with_context(|| format!("Failed to write config file: {}", path.display()))?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
                .with_context(|| format!("Failed to set config file permissions: {}", path.display()))?;
        }

        Ok(())
    }

    pub fn config_path() -> Result<PathBuf> {
        let proj_dirs =
            ProjectDirs::from("", "", "burrow").context("Could not determine config directory")?;

        Ok(proj_dirs.config_dir().join("config.toml"))
    }
}
