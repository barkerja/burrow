use anyhow::Result;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use reqwest::Client;
use std::str::FromStr;
use std::sync::OnceLock;

/// Shared HTTP client for connection pooling and reuse
static HTTP_CLIENT: OnceLock<Client> = OnceLock::new();

/// Get or create the shared HTTP client
fn get_client() -> &'static Client {
    HTTP_CLIENT.get_or_init(|| {
        Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .pool_max_idle_per_host(10)
            .build()
            .expect("failed to create HTTP client")
    })
}

/// Forward an HTTP request to the local service
pub async fn forward_http_request(
    local_host: &str,
    local_port: u16,
    method: &str,
    path: &str,
    query_string: &str,
    headers: Vec<(String, String)>,
    body: Option<Vec<u8>>,
) -> Result<(u16, Vec<(String, String)>, Option<Vec<u8>>)> {
    let client = get_client();

    // Build URL
    let url = if query_string.is_empty() {
        format!("http://{}:{}{}", local_host, local_port, path)
    } else {
        format!(
            "http://{}:{}{}?{}",
            local_host, local_port, path, query_string
        )
    };

    // Build request
    let method = reqwest::Method::from_str(method)?;
    let mut request = client.request(method, &url);

    // Add headers (skip hop-by-hop headers)
    let mut header_map = HeaderMap::with_capacity(headers.len());
    for (name, value) in headers {
        let name_lower = name.to_lowercase();

        // Skip hop-by-hop headers
        if matches!(
            name_lower.as_str(),
            "connection"
                | "keep-alive"
                | "proxy-authenticate"
                | "proxy-authorization"
                | "te"
                | "trailers"
                | "transfer-encoding"
                | "upgrade"
                | "host"
        ) {
            continue;
        }

        if let (Ok(header_name), Ok(header_value)) =
            (HeaderName::from_str(&name), HeaderValue::from_str(&value))
        {
            header_map.insert(header_name, header_value);
        }
    }
    request = request.headers(header_map);

    // Add body
    if let Some(body_data) = body {
        request = request.body(body_data);
    }

    // Send request
    let response = request.send().await?;

    // Extract response
    let status = response.status().as_u16();

    let response_headers: Vec<(String, String)> = response
        .headers()
        .iter()
        .filter_map(|(name, value)| {
            let name_str = name.as_str().to_lowercase();

            // Skip hop-by-hop headers
            if matches!(
                name_str.as_str(),
                "connection"
                    | "keep-alive"
                    | "proxy-authenticate"
                    | "proxy-authorization"
                    | "te"
                    | "trailers"
                    | "transfer-encoding"
                    | "upgrade"
            ) {
                return None;
            }

            value
                .to_str()
                .ok()
                .map(|v| (name.as_str().to_string(), v.to_string()))
        })
        .collect();

    let body = response.bytes().await.ok().map(|b| b.to_vec());
    let body = if body.as_ref().map(|b| b.is_empty()).unwrap_or(true) {
        None
    } else {
        body
    };

    Ok((status, response_headers, body))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_forward_request_not_running() {
        // This should fail since there's no server running
        let result =
            forward_http_request("localhost", 19999, "GET", "/test", "", vec![], None).await;

        assert!(result.is_err());
    }
}
