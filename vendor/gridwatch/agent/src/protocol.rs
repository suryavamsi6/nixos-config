use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub const VERSION: u8 = 1;
pub const MAX_REQUEST_BYTES: usize = 64 * 1024;
pub const MAX_REQUEST_ID_BYTES: usize = 80;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub version: u8,
    pub kind: String,
    #[serde(default, rename = "requestId")]
    pub request_id: Option<String>,
    #[serde(default = "empty_object")]
    pub payload: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct Response {
    pub version: u8,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none", rename = "requestId")]
    pub request_id: Option<String>,
    pub payload: Value,
}

fn empty_object() -> Value {
    json!({})
}

impl Request {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.version != VERSION {
            return Err("protocol-version");
        }
        if self
            .request_id
            .as_ref()
            .is_some_and(|id| id.len() > MAX_REQUEST_ID_BYTES)
        {
            return Err("request-id-too-long");
        }
        if !self.payload.is_object() {
            return Err("invalid-payload");
        }
        Ok(())
    }
}

pub fn response(kind: &str, payload: Value, request_id: Option<String>) -> Response {
    Response {
        version: VERSION,
        kind: kind.to_owned(),
        request_id,
        payload,
    }
}

pub fn error(code: &str, message: &str, request_id: Option<String>) -> Response {
    response(
        "error",
        json!({ "code": code, "message": message }),
        request_id,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_camel_case_request_id() {
        let request: Request = serde_json::from_value(json!({
            "version": 1,
            "kind": "ping",
            "requestId": "abc",
            "payload": {}
        }))
        .unwrap();
        assert_eq!(request.request_id.as_deref(), Some("abc"));
        let encoded =
            serde_json::to_value(response("status", json!({}), request.request_id)).unwrap();
        assert_eq!(encoded["requestId"], "abc");
        assert!(encoded.get("request_id").is_none());
    }

    #[test]
    fn rejects_non_object_payloads() {
        let request: Request = serde_json::from_value(json!({
            "version": 1,
            "kind": "ping",
            "payload": []
        }))
        .unwrap();
        assert_eq!(request.validate(), Err("invalid-payload"));
    }
}
