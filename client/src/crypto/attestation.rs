use base64::Engine;
use std::time::{SystemTime, UNIX_EPOCH};

use super::Keypair;
use crate::protocol::Attestation;

/// Create an attestation signed by the keypair
pub fn create_attestation(keypair: &Keypair, requested_subdomain: Option<&str>) -> Attestation {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    // Build message to sign: "burrow:register:<timestamp>:<subdomain_or_empty>"
    // This must match the Elixir server's expected format
    let message = match requested_subdomain {
        Some(subdomain) => format!("burrow:register:{}:{}", timestamp, subdomain),
        None => format!("burrow:register:{}:", timestamp),
    };

    // Sign the message
    let signature = keypair.sign(message.as_bytes());

    Attestation {
        public_key: keypair.public_key_base64(),
        requested_subdomain: requested_subdomain.map(|s| s.to_string()),
        timestamp,
        signature: base64::engine::general_purpose::STANDARD.encode(signature),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_attestation() {
        let keypair = Keypair::generate();
        let attestation = create_attestation(&keypair, Some("myapp"));

        assert!(!attestation.public_key.is_empty());
        assert_eq!(attestation.requested_subdomain, Some("myapp".to_string()));
        assert!(attestation.timestamp > 0);
        assert!(!attestation.signature.is_empty());
    }

    #[test]
    fn test_create_attestation_no_subdomain() {
        let keypair = Keypair::generate();
        let attestation = create_attestation(&keypair, None);

        assert!(attestation.requested_subdomain.is_none());
    }
}
