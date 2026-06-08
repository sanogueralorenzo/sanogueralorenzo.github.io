pub fn normalize_chat_tool_call_id(id: &str) -> String {
    let call_id = id.split_once('|').map(|(call_id, _)| call_id).unwrap_or(id);
    normalize_id_part(call_id, 40, "call")
}

pub struct ResponsesToolCallId {
    pub call_id: String,
    pub item_id: Option<String>,
}

pub fn normalize_responses_tool_call_id(id: &str) -> ResponsesToolCallId {
    let Some((call_id, item_id)) = id.split_once('|') else {
        return ResponsesToolCallId {
            call_id: normalize_id_part(id, 64, "call"),
            item_id: None,
        };
    };

    ResponsesToolCallId {
        call_id: normalize_id_part(call_id, 64, "call"),
        item_id: Some(normalize_responses_item_id(item_id)),
    }
}

pub fn combine_responses_tool_call_id(call_id: String, item_id: Option<String>) -> String {
    match item_id {
        Some(item_id) if !item_id.is_empty() => format!("{call_id}|{item_id}"),
        _ => call_id,
    }
}

fn normalize_responses_item_id(item_id: &str) -> String {
    let normalized = normalize_id_part(item_id, 64, "fc");
    if normalized == item_id && normalized.starts_with("fc_") {
        return normalized;
    }

    let hashed = format!("fc_{}", short_hash(item_id));
    normalize_id_part(&hashed, 64, "fc")
}

fn normalize_id_part(part: &str, max_len: usize, fallback: &str) -> String {
    let mut normalized = String::new();
    for ch in part.chars() {
        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' {
            normalized.push(ch);
        } else {
            normalized.push('_');
        }
    }

    let mut normalized: String = normalized.chars().take(max_len).collect();
    while normalized.ends_with('_') {
        normalized.pop();
    }

    if normalized.is_empty() {
        fallback.to_owned()
    } else {
        normalized
    }
}

fn short_hash(value: &str) -> String {
    let mut h1 = 0xdead_beefu32;
    let mut h2 = 0x41c6_ce57u32;

    for ch in value.encode_utf16() {
        let ch = u32::from(ch);
        h1 = (h1 ^ ch).wrapping_mul(2_654_435_761);
        h2 = (h2 ^ ch).wrapping_mul(1_597_334_677);
    }

    h1 = (h1 ^ (h1 >> 16)).wrapping_mul(2_246_822_507)
        ^ (h2 ^ (h2 >> 13)).wrapping_mul(3_266_489_909);
    h2 = (h2 ^ (h2 >> 16)).wrapping_mul(2_246_822_507)
        ^ (h1 ^ (h1 >> 13)).wrapping_mul(3_266_489_909);

    format!("{}{}", base36(h2), base36(h1))
}

fn base36(mut value: u32) -> String {
    if value == 0 {
        return "0".to_owned();
    }

    let mut output = Vec::new();
    while value > 0 {
        let digit = value % 36;
        let ch = if digit < 10 {
            char::from(b'0' + digit as u8)
        } else {
            char::from(b'a' + (digit - 10) as u8)
        };
        output.push(ch);
        value /= 36;
    }
    output.iter().rev().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_chat_ids_from_responses_pipe_ids() {
        let id = normalize_chat_tool_call_id("call_abc|very/long+item==");

        assert_eq!(id, "call_abc");
    }

    #[test]
    fn preserves_valid_responses_item_ids() {
        let id = normalize_responses_tool_call_id("call_abc|fc_123");

        assert_eq!(id.call_id, "call_abc");
        assert_eq!(id.item_id, Some("fc_123".to_owned()));
    }

    #[test]
    fn hashes_foreign_responses_item_ids() {
        let id = normalize_responses_tool_call_id("call_abc|unsafe/item+id==");
        let item_id = id.item_id.unwrap();

        assert_eq!(id.call_id, "call_abc");
        assert_eq!(item_id, "fc_s7y0p7y00ulr");
        assert!(item_id.starts_with("fc_"));
        assert!(item_id.len() <= 64);
        assert!(
            item_id
                .chars()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
        );
    }
}
