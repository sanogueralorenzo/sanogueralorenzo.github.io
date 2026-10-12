/* SPDX-License-Identifier: GPL-3.0-only */
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <gbm.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void) {
    setbuf(stdout, NULL);
    int fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open software node"); return 1; }
    struct gbm_device *gbm = gbm_create_device(fd);
    if (!gbm) { perror("create GBM device"); return 2; }
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_display = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay display = get_display(EGL_PLATFORM_GBM_KHR, gbm, NULL);
    EGLint major, minor;
    if (!eglInitialize(display, &major, &minor)) { printf("eglInitialize failed: 0x%x\n", eglGetError()); return 3; }
    printf("egl-ready: %d.%d %s\n", major, minor, eglQueryString(display, EGL_VENDOR));
    eglBindAPI(EGL_OPENGL_ES_API);
    EGLint attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    EGLContext context = eglCreateContext(display, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attributes);
    if (context == EGL_NO_CONTEXT || !eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context)) {
        printf("create context failed: 0x%x\n", eglGetError()); return 4;
    }
    printf("gl-ready: %s / %s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));
    struct gbm_bo *buffer = gbm_bo_create(gbm, 64, 64, GBM_FORMAT_ARGB8888, GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT | GBM_BO_USE_LINEAR);
    if (!buffer) { perror("create GBM buffer"); return 5; }
    int memory = gbm_bo_get_fd(buffer);
    if (memory < 0) { perror("export GBM buffer"); return 6; }
    const EGLint image_attributes[] = {EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_LINUX_DRM_FOURCC_EXT, GBM_FORMAT_ARGB8888,
        EGL_DMA_BUF_PLANE0_FD_EXT, memory, EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0, EGL_DMA_BUF_PLANE0_PITCH_EXT, gbm_bo_get_stride(buffer), EGL_NONE};
    PFNEGLCREATEIMAGEKHRPROC create_image = (void *)eglGetProcAddress("eglCreateImageKHR");
    EGLImageKHR image = create_image(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, image_attributes);
    if (image == EGL_NO_IMAGE_KHR) { printf("import buffer failed: 0x%x\n", eglGetError()); return 7; }
    GLuint renderbuffer, framebuffer;
    glGenRenderbuffers(1, &renderbuffer); glBindRenderbuffer(GL_RENDERBUFFER, renderbuffer);
    PFNGLEGLIMAGETARGETRENDERBUFFERSTORAGEOESPROC target = (void *)eglGetProcAddress("glEGLImageTargetRenderbufferStorageOES");
    target(GL_RENDERBUFFER, image);
    glGenFramebuffers(1, &framebuffer); glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderbuffer);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) { puts("incomplete framebuffer"); return 8; }
    glViewport(0, 0, 64, 64); glClearColor(1.f, 0.f, 0.f, 1.f); glClear(GL_COLOR_BUFFER_BIT); glFinish();
    uint32_t *pixels = mmap(NULL, gbm_bo_get_stride(buffer) * 64, PROT_READ, MAP_SHARED, memory, 0);
    if (pixels == MAP_FAILED) { perror("map exported frame"); return 9; }
    printf("frame-ready: 0x%08x\n", pixels[0]);
    return pixels[0] == 0xffff0000 ? 0 : 10;
}
