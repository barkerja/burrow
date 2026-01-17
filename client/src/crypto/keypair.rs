use base64::Engine;
use ed25519_dalek::{SigningKey, VerifyingKey};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::error::{BurrowError, Result};

#[derive(Serialize, Deserialize)]
struct KeypairFile {
    public_key: String,
    secret_key: String,
}

pub struct Keypair {
    pub signing_key: SigningKey,
    pub verifying_key: VerifyingKey,
}

impl Keypair {
    /// Generate a new random keypair
    pub fn generate() -> Self {
        let signing_key = SigningKey::generate(&mut OsRng);
        let verifying_key = signing_key.verifying_key();
        Keypair {
            signing_key,
            verifying_key,
        }
    }

    /// Load keypair from file, or generate and save if it doesn't exist
    pub fn load_or_generate(path: &Path) -> Result<Self> {
        if path.exists() {
            Self::load(path)
        } else {
            let keypair = Self::generate();
            keypair.save(path)?;
            Ok(keypair)
        }
    }

    /// Load keypair from file
    pub fn load(path: &Path) -> Result<Self> {
        let contents = std::fs::read_to_string(path)?;
        let file: KeypairFile = serde_json::from_str(&contents)?;

        let secret_bytes = base64::engine::general_purpose::STANDARD
            .decode(&file.secret_key)
            .map_err(|e| BurrowError::Crypto(format!("Invalid secret key encoding: {}", e)))?;

        let secret_array: [u8; 64] = secret_bytes
            .try_into()
            .map_err(|_| BurrowError::Crypto("Invalid secret key length".to_string()))?;

        // ed25519-dalek stores the 32-byte seed in the first 32 bytes of the 64-byte secret
        let seed: [u8; 32] = secret_array[..32]
            .try_into()
            .map_err(|_| BurrowError::Crypto("Invalid seed length".to_string()))?;

        let signing_key = SigningKey::from_bytes(&seed);
        let verifying_key = signing_key.verifying_key();

        // Verify public key matches
        let expected_public = base64::engine::general_purpose::STANDARD
            .decode(&file.public_key)
            .map_err(|e| BurrowError::Crypto(format!("Invalid public key encoding: {}", e)))?;

        if verifying_key.as_bytes() != expected_public.as_slice() {
            return Err(BurrowError::Crypto(
                "Public key doesn't match secret key".to_string(),
            ));
        }

        Ok(Keypair {
            signing_key,
            verifying_key,
        })
    }

    /// Save keypair to file
    pub fn save(&self, path: &Path) -> Result<()> {
        // Create parent directories if they don't exist
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        // Build the 64-byte secret key format (seed || public)
        let mut secret_bytes = [0u8; 64];
        secret_bytes[..32].copy_from_slice(self.signing_key.as_bytes());
        secret_bytes[32..].copy_from_slice(self.verifying_key.as_bytes());

        let file = KeypairFile {
            public_key: base64::engine::general_purpose::STANDARD
                .encode(self.verifying_key.as_bytes()),
            secret_key: base64::engine::general_purpose::STANDARD.encode(secret_bytes),
        };

        let contents = serde_json::to_string_pretty(&file)?;
        std::fs::write(path, contents)?;

        Ok(())
    }

    /// Get base64-encoded public key
    pub fn public_key_base64(&self) -> String {
        base64::engine::general_purpose::STANDARD.encode(self.verifying_key.as_bytes())
    }

    /// Sign a message
    pub fn sign(&self, message: &[u8]) -> [u8; 64] {
        use ed25519_dalek::Signer;
        self.signing_key.sign(message).to_bytes()
    }
}

/// Get default keypair path (~/.burrow/keypair.json on all platforms)
pub fn default_keypair_path() -> std::path::PathBuf {
    directories::UserDirs::new()
        .map(|u| u.home_dir().to_path_buf())
        .unwrap_or_else(|| {
            // Fallback to current directory if home can't be determined
            std::path::PathBuf::from(".")
        })
        .join(".burrow")
        .join("keypair.json")
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_keypair_generate() {
        let keypair = Keypair::generate();
        assert_eq!(keypair.verifying_key.as_bytes().len(), 32);
    }

    #[test]
    fn test_keypair_save_load() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test_keypair.json");

        let original = Keypair::generate();
        original.save(&path).unwrap();

        let loaded = Keypair::load(&path).unwrap();

        assert_eq!(
            original.verifying_key.as_bytes(),
            loaded.verifying_key.as_bytes()
        );
    }
}
