# Voice

Voice is private, local dictation through either the keyboard you already use or the optional
compact Voice keyboard.

The product is built around a simple pipeline:

`capture audio -> transcribe with Moonshine -> insert text`

## Structure

- `android/` contains the Android product UI, existing-keyboard microphone overlay, and compact
  voice keyboard.

Android is the first supported platform. iOS, macOS, Linux, and Windows versions are coming soon.

## Development

```shell
cd tools/voice/android
./gradlew :app:installDebug
```
