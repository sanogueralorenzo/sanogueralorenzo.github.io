use ::jni::objects::{JClass, JString};
use ::jni::sys::{jboolean, jstring};
use ::jni::JNIEnv;

use super::*;

fn jni_string_to_rust(env: &mut JNIEnv, input: &JString) -> String {
    env.get_string(&input)
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn rust_string_to_jni(env: &mut JNIEnv, output: String) -> jstring {
    env.new_string(output)
        .expect("failed to allocate JNI string")
        .into_raw()
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativePreprocessText(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, preprocess(&text).text)
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativePreprocessRuleIds(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    let result = preprocess(&text).applied_rules.join("|");
    rust_string_to_jni(&mut env, result)
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeNormalizeComposeInput(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, normalize_compose_input(&text))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeNormalizeInstructionInput(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, normalize_instruction_input(&text))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeCleanModelOutput(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
    bullet_mode: jboolean,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, clean_model_output(&text, bullet_mode != 0))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeNormalizeComposeOutputText(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, normalize_compose_output_text(&text))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeFinalizeComposeOutput(
    mut env: JNIEnv,
    _class: JClass,
    original_text: JString,
    model_output: JString,
    list_mode: jboolean,
) -> jstring {
    let original = jni_string_to_rust(&mut env, &original_text);
    let output = jni_string_to_rust(&mut env, &model_output);
    rust_string_to_jni(&mut env, postprocess(&original, &output, list_mode != 0))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeAnalyzeInstruction(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    let analysis = analyze_instruction(&text);
    rust_string_to_jni(
        &mut env,
        format!(
            "{}{FIELD_SEPARATOR}{}",
            sanitize_field(&analysis.normalized_instruction),
            analysis.intent.as_str()
        ),
    )
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeIsStrictEditCommand(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jboolean {
    let text = jni_string_to_rust(&mut env, &input);
    if is_strict_edit_command(&text) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeTryApplyDeterministicEdit(
    mut env: JNIEnv,
    _class: JClass,
    source_text: JString,
    instruction_text: JString,
) -> jstring {
    let source = jni_string_to_rust(&mut env, &source_text);
    let instruction = jni_string_to_rust(&mut env, &instruction_text);
    let encoded = try_apply_deterministic_edit(&source, &instruction)
        .map(|result| {
            format!(
                "{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}",
                sanitize_field(&result.output),
                result.applied,
                result.intent.as_str(),
                result.scope.as_str(),
                result.command_kind.as_str(),
                result.matched_count,
                result.rule_confidence.as_str(),
                result.no_match_detected
            )
        })
        .unwrap_or_default();
    rust_string_to_jni(&mut env, encoded)
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeLooksLikeList(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jboolean {
    let text = jni_string_to_rust(&mut env, &input);
    if looks_like_list(&text) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativePostReplaceCapitalization(
    mut env: JNIEnv,
    _class: JClass,
    source_text: JString,
    instruction_text: JString,
    edited_output: JString,
) -> jstring {
    let source = jni_string_to_rust(&mut env, &source_text);
    let instruction = jni_string_to_rust(&mut env, &instruction_text);
    let output = jni_string_to_rust(&mut env, &edited_output);
    rust_string_to_jni(
        &mut env,
        post_replace_capitalization(&source, &instruction, &output),
    )
}

pub(crate) fn sanitize_field(value: &str) -> String {
    value.replace(FIELD_SEPARATOR, " ")
}
