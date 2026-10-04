#include "display.h"
#include <android/native_window_jni.h>
#include <jni.h>
#include <errno.h>
#include <string.h>

static pthread_mutex_t ownership = PTHREAD_MUTEX_INITIALIZER;
static struct deck_display *display;
static void fail(JNIEnv *env, const char *message) {
    (*env)->ThrowNew(env, (*env)->FindClass(env, "java/lang/IllegalStateException"), message);
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_androiddeck_display_NativeDisplay_start(JNIEnv *env, jobject self, jstring socket, jobject surface, jint refresh) {
    pthread_mutex_lock(&ownership);
    if (display) { fail(env, "Display is already running"); goto done; }
    ANativeWindow *window = surface ? ANativeWindow_fromSurface(env, surface) : NULL;
    if (!window) { fail(env, "Android rendering surface is unavailable"); goto done; }
    const char *path = (*env)->GetStringUTFChars(env, socket, NULL);
    if (!path) { ANativeWindow_release(window); goto done; }
    display = deck_start(path, window, refresh);
    (*env)->ReleaseStringUTFChars(env, socket, path);
    if (!display) fail(env, strerror(errno));
done:
    pthread_mutex_unlock(&ownership);
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_androiddeck_display_NativeDisplay_attach(JNIEnv *env, jobject self, jobject surface) {
    pthread_mutex_lock(&ownership);
    if (display) deck_attach(display, surface ? ANativeWindow_fromSurface(env, surface) : NULL);
    pthread_mutex_unlock(&ownership);
}
JNIEXPORT void JNICALL Java_com_sanogueralorenzo_androiddeck_display_NativeDisplay_stop(JNIEnv *env, jobject self) {
    pthread_mutex_lock(&ownership);
    if (display) { deck_stop(display); display = NULL; }
    pthread_mutex_unlock(&ownership);
}
JNIEXPORT jlongArray JNICALL Java_com_sanogueralorenzo_androiddeck_display_NativeDisplay_snapshot(JNIEnv *env, jobject self) {
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
