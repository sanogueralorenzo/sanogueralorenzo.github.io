#include "display/display.h"
#include <android/native_window_jni.h>
#include <jni.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

static pthread_mutex_t ownership = PTHREAD_MUTEX_INITIALIZER;
static struct amarchy_display *display;
static void fail(JNIEnv *env, const char *message) {
    (*env)->ThrowNew(env, (*env)->FindClass(env, "java/lang/IllegalStateException"), message);
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_start(JNIEnv *env, jobject self, jstring socket, jobject surface, jint refresh) {
    pthread_mutex_lock(&ownership);
    if (display) { fail(env, "Display is already running"); goto done; }
    ANativeWindow *window = surface ? ANativeWindow_fromSurface(env, surface) : NULL;
    if (!window) { fail(env, "Android rendering surface is unavailable"); goto done; }
    const char *path = (*env)->GetStringUTFChars(env, socket, NULL);
    if (!path) { ANativeWindow_release(window); goto done; }
    display = amarchy_start(path, window, refresh);
    (*env)->ReleaseStringUTFChars(env, socket, path);
    if (!display) fail(env, strerror(errno));
done:
    pthread_mutex_unlock(&ownership);
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_attach(JNIEnv *env, jobject self, jobject surface) {
    pthread_mutex_lock(&ownership);
    if (display && !amarchy_attach(display, surface ? ANativeWindow_fromSurface(env, surface) : NULL)) fail(env, "Cannot reattach the Android surface");
    pthread_mutex_unlock(&ownership);
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_stop(JNIEnv *env, jobject self) {
    pthread_mutex_lock(&ownership);
    if (display) { amarchy_stop(display); display = NULL; }
    pthread_mutex_unlock(&ownership);
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_resize(JNIEnv *env, jobject self, jint width, jint height) {
    pthread_mutex_lock(&ownership);
    if (display) amarchy_resize(display, width, height);
    pthread_mutex_unlock(&ownership);
}
JNIEXPORT jlongArray JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_snapshot(JNIEnv *env, jobject self) {
    jlong values[3] = {0};
    pthread_mutex_lock(&ownership);
    if (display) {
        pthread_mutex_lock(&display->window_mutex);
        values[0] = display->frames; values[1] = display->frame_width; values[2] = display->frame_height;
        pthread_mutex_unlock(&display->window_mutex);
    }
    pthread_mutex_unlock(&ownership);
    jlongArray array = (*env)->NewLongArray(env, 3);
    if (array) (*env)->SetLongArrayRegion(env, array, 0, 3, values);
    return array;
}

static void enqueue(struct amarchy_input_event event) {
    pthread_mutex_lock(&ownership);
    if (display) amarchy_input_enqueue(display, event);
    pthread_mutex_unlock(&ownership);
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_pointer(JNIEnv *env, jobject self,
        jfloat x, jfloat y, jint button, jboolean pressed) {
    enqueue((struct amarchy_input_event){ AMARCHY_POINTER, button, pressed, x, y });
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_scroll(JNIEnv *env, jobject self, jfloat x, jfloat y) {
    enqueue((struct amarchy_input_event){ AMARCHY_SCROLL, 0, 0, x, y });
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_key(JNIEnv *env, jobject self, jint code, jboolean pressed) {
    enqueue((struct amarchy_input_event){ .type = AMARCHY_KEY, .code = code, .action = pressed });
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_touch(JNIEnv *env, jobject self,
        jint id, jint action, jfloat x, jfloat y) {
    enqueue((struct amarchy_input_event){ AMARCHY_TOUCH, id, action, x, y });
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_amarchy_display_NativeDisplay_releaseInput(JNIEnv *env, jobject self) {
    enqueue((struct amarchy_input_event){ .type = AMARCHY_RESET });
}
