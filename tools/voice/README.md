# Voice

Voice is private, local dictation for the keyboard you already use. Position Voice over your
keyboard's microphone, tap once to record, and tap again to insert the transcript into the focused
field.

The product is built around a simple pipeline:

`capture audio -> transcribe with Moonshine -> insert text`

## Structure

- `android/` contains the Android product UI and existing-keyboard microphone overlay.

Android is the first supported platform. iOS, macOS, Linux, and Windows versions are coming soon.

## Development

```shell
cd tools/voice/android
./gradlew :app:installDebug
```
