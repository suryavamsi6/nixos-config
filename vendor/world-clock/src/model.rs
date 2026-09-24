use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct CityInput {
    pub id: String,
    pub place: String,
    #[serde(default)]
    pub label: Option<String>,
    pub timezone: String,
    #[serde(default)]
    pub latitude: Option<f64>,
    #[serde(default)]
    pub longitude: Option<f64>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ClockOutput {
    pub id: String,
    pub place: String,
    pub label: String,
    pub timezone: String,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub time: String,
    pub date: String,
    pub day_delta: i64,
    pub day_label: String,
    pub abbreviation: String,
    pub utc_offset_seconds: i32,
}

#[derive(Clone, Debug, Serialize)]
pub struct SnapshotError {
    pub id: String,
    pub timezone: String,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct SnapshotPayload {
    pub schema_version: u8,
    pub generated_at: String,
    pub local_timezone: String,
    pub clocks: Vec<ClockOutput>,
    pub errors: Vec<SnapshotError>,
}

#[derive(Clone, Debug, Serialize)]
pub struct SearchResult {
    pub source: String,
    pub place: String,
    pub subtitle: String,
    pub timezone: String,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub time: String,
    pub date: String,
    pub day_delta: i64,
    pub day_label: String,
    pub abbreviation: String,
}

#[derive(Debug, Serialize)]
pub struct SearchPayload {
    pub schema_version: u8,
    pub query: String,
    pub source: String,
    pub online_attempted: bool,
    pub results: Vec<SearchResult>,
    pub error: Option<String>,
}
