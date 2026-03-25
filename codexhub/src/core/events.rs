use serde_json::Value;

pub fn parse_thread_id_from_events(events: &str) -> Option<String> {
    for line in events.lines() {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if let Some(found) = find_key_recursively(&value, "thread_id") {
            return Some(found);
        }
    }
    None
}

pub fn parse_last_agent_message_from_events(events: &str) -> Option<String> {
    let mut last_message: Option<String> = None;
    for line in events.lines() {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(item) = value.get("item") else {
            continue;
        };
        if item.get("type").and_then(Value::as_str) != Some("agent_message") {
            continue;
        }
        if let Some(text) = item.get("text").and_then(Value::as_str) {
            last_message = Some(text.to_string());
        }
    }
    last_message
}

fn find_key_recursively(value: &Value, key: &str) -> Option<String> {
    match value {
        Value::Object(map) => {
            if let Some(direct) = map.get(key).and_then(Value::as_str) {
                return Some(direct.to_string());
            }
            for child in map.values() {
                if let Some(found) = find_key_recursively(child, key) {
                    return Some(found);
                }
            }
            None
        }
        Value::Array(items) => {
            for item in items {
                if let Some(found) = find_key_recursively(item, key) {
                    return Some(found);
                }
            }
            None
        }
        _ => None,
    }
}
