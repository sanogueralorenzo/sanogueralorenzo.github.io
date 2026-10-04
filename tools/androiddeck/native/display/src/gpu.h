#ifndef ANDROIDDECK_GPU_H
#define ANDROIDDECK_GPU_H
#define VK_NO_PROTOTYPES
#define VK_USE_PLATFORM_ANDROID_KHR
#include <android/native_window.h>
#include <vulkan/vulkan.h>
#include <stdbool.h>
#include <stddef.h>

#define DECK_INSTANCE_FUNCTIONS(X) \
    X(DestroyInstance) X(EnumeratePhysicalDevices) X(GetPhysicalDeviceProperties2) \
    X(GetPhysicalDeviceQueueFamilyProperties) X(EnumerateDeviceExtensionProperties) \
    X(GetPhysicalDeviceFormatProperties2) X(GetPhysicalDeviceImageFormatProperties2) \
    X(GetPhysicalDeviceExternalSemaphoreProperties) \
    X(CreateDevice) X(GetDeviceProcAddr) X(CreateAndroidSurfaceKHR) X(DestroySurfaceKHR) \
    X(GetPhysicalDeviceSurfaceSupportKHR) X(GetPhysicalDeviceSurfaceCapabilitiesKHR) \
    X(GetPhysicalDeviceSurfaceFormatsKHR)
#define DECK_DEVICE_FUNCTIONS(X) \
    X(DestroyDevice) X(GetDeviceQueue) X(DeviceWaitIdle) X(CreateImage) X(DestroyImage) \
    X(GetImageMemoryRequirements) X(GetMemoryFdPropertiesKHR) X(AllocateMemory) \
    X(FreeMemory) X(BindImageMemory) X(CreateSwapchainKHR) X(DestroySwapchainKHR) \
    X(GetSwapchainImagesKHR) X(AcquireNextImageKHR) X(QueuePresentKHR) X(QueueSubmit) \
    X(CreateCommandPool) X(DestroyCommandPool) X(AllocateCommandBuffers) \
    X(ResetCommandBuffer) X(BeginCommandBuffer) X(EndCommandBuffer) \
    X(CmdPipelineBarrier) X(CmdBlitImage) X(CreateFence) X(DestroyFence) \
    X(WaitForFences) X(ResetFences) X(CreateSemaphore) X(DestroySemaphore) \
    X(ImportSemaphoreFdKHR)
struct deck_gpu {
    VkInstance instance;
    VkPhysicalDevice physical;
    VkDevice device;
    VkQueue queue;
    uint32_t queue_family;
    VkSurfaceKHR surface;
    ANativeWindow *window; // Borrowed while the display owns the native window.
    VkSwapchainKHR swapchain;
    VkImage *images;
    VkSemaphore *ready;
    uint32_t image_count;
    VkExtent2D extent;
    VkFormat format;
    VkSemaphore acquired, source_ready;
    VkCommandPool commands;
    VkCommandBuffer command;
    VkFence fence;
    char error[256];
    char device_name[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];
    struct {
#define DECLARE(name) PFN_vk##name name;
        DECK_INSTANCE_FUNCTIONS(DECLARE)
        DECK_DEVICE_FUNCTIONS(DECLARE)
#undef DECLARE
    } vk;
};
struct deck_gpu_image {
    struct deck_gpu *gpu;
    VkImage image;
    VkDeviceMemory memory;
    uint32_t width, height;
};
bool deck_gpu_open(struct deck_gpu *gpu, const char *driver, const char *libraries);
void deck_gpu_close(struct deck_gpu *gpu);
bool deck_gpu_error(struct deck_gpu *gpu, const char *operation, VkResult result);
bool deck_gpu_attach(struct deck_gpu *gpu, ANativeWindow *window);
void deck_gpu_detach(struct deck_gpu *gpu);
size_t deck_gpu_modifiers(struct deck_gpu *gpu, uint64_t *out, size_t capacity);
struct deck_gpu_image *deck_gpu_import(struct deck_gpu *gpu, int fd, uint64_t modifier, int width, int height, uint32_t stride, uint32_t offset);
void deck_gpu_image_destroy(struct deck_gpu_image *image);
bool deck_gpu_present(struct deck_gpu *gpu, struct deck_gpu_image *image, int acquire_fd);
#endif
