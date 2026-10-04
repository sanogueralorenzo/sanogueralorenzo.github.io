#include "gpu.h"
#include <adrenotools/driver.h>
#include <android/log.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Android linker namespaces cannot be deleted. Load the fixed driver once per
// process; every session still owns and destroys its Vulkan objects.
static void *driver_handle;
static bool loader_attempted;
static PFN_vkGetInstanceProcAddr get_proc;

bool deck_gpu_error(struct deck_gpu *gpu, const char *operation, VkResult result) {
    snprintf(gpu->error, sizeof(gpu->error), "%s failed (Vulkan %d). Stop the session and retry.", operation, result);
    __android_log_print(ANDROID_LOG_ERROR, "AndroidSteam", "%s", gpu->error);
    return false;
}
static bool loader(struct deck_gpu *gpu, const char *driver, const char *libraries) {
    if (access("/dev/kgsl-3d0", R_OK | W_OK) != 0) {
        snprintf(gpu->error, sizeof(gpu->error), "An accessible Adreno GPU is required. Connect the supported Android device.");
        return false;
    }
    if (!loader_attempted) {
        char *directory = NULL;
        if (asprintf(&directory, "%s/", driver) < 0) return deck_gpu_error(gpu, "Driver path allocation", VK_ERROR_OUT_OF_HOST_MEMORY);
        char *library = NULL;
        if (asprintf(&library, "%slibvulkan_freedreno.so", directory) < 0) { free(directory); return deck_gpu_error(gpu, "Driver path allocation", VK_ERROR_OUT_OF_HOST_MEMORY); }
        bool installed = access(library, R_OK) == 0;
        free(library);
        if (!installed) { free(directory); snprintf(gpu->error, sizeof(gpu->error), "Install the matched graphics driver before starting the session."); return false; }
        loader_attempted = true;
        driver_handle = adrenotools_open_libvulkan(RTLD_NOW | RTLD_LOCAL, ADRENOTOOLS_DRIVER_CUSTOM,
            NULL, libraries, directory, "libvulkan_freedreno.so", NULL, NULL);
        free(directory);
        if (driver_handle) get_proc = (PFN_vkGetInstanceProcAddr)dlsym(driver_handle, "vkGetInstanceProcAddr");
    }
    if (!get_proc) {
        snprintf(gpu->error, sizeof(gpu->error), "The matched Adreno driver could not load. Restart Android Steam and retry setup.");
        return false;
    }
    return true;
}
static bool extensions(struct deck_gpu *gpu, const char **required, uint32_t count) {
    uint32_t available = 0;
    VkResult result = gpu->vk.EnumerateDeviceExtensionProperties(gpu->physical, NULL, &available, NULL);
    if (result != VK_SUCCESS) return deck_gpu_error(gpu, "GPU extension query", result);
    VkExtensionProperties *properties = calloc(available, sizeof(*properties));
    if (!properties) return deck_gpu_error(gpu, "GPU extension allocation", VK_ERROR_OUT_OF_HOST_MEMORY);
    result = gpu->vk.EnumerateDeviceExtensionProperties(gpu->physical, NULL, &available, properties);
    bool complete = result == VK_SUCCESS;
    if (!complete) deck_gpu_error(gpu, "GPU extension retrieval", result);
    for (uint32_t i = 0; complete && i < count; i++) {
        bool found = false;
        for (uint32_t j = 0; j < available; j++) if (!strcmp(required[i], properties[j].extensionName)) { found = true; break; }
        if (!found) { snprintf(gpu->error, sizeof(gpu->error), "The GPU driver is missing %s. Reinstall the matched driver pair.", required[i]); complete = false; }
    }
    free(properties);
    return complete;
}
bool deck_gpu_open(struct deck_gpu *gpu, const char *driver, const char *libraries) {
    if (!loader(gpu, driver, libraries)) return false;
    PFN_vkCreateInstance create = (PFN_vkCreateInstance)get_proc(NULL, "vkCreateInstance");
    if (!create) return deck_gpu_error(gpu, "Vulkan entry point", VK_ERROR_INITIALIZATION_FAILED);
    const char *instance_extensions[] = { VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_ANDROID_SURFACE_EXTENSION_NAME };
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .pApplicationName = "Android Steam", .apiVersion = VK_API_VERSION_1_2 };
    VkInstanceCreateInfo instance = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app,
        .enabledExtensionCount = 2, .ppEnabledExtensionNames = instance_extensions };
    VkResult result = create(&instance, NULL, &gpu->instance);
    if (result != VK_SUCCESS) return deck_gpu_error(gpu, "Adreno instance creation", result);
#define LOAD(name) gpu->vk.name = (PFN_vk##name)get_proc(gpu->instance, "vk" #name); \
    if (!gpu->vk.name) { deck_gpu_error(gpu, "vk" #name, VK_ERROR_EXTENSION_NOT_PRESENT); goto failed; }
    DECK_INSTANCE_FUNCTIONS(LOAD)
#undef LOAD
    uint32_t count = 1;
    result = gpu->vk.EnumeratePhysicalDevices(gpu->instance, &count, &gpu->physical);
    if (result != VK_SUCCESS || count != 1) { deck_gpu_error(gpu, "Adreno device discovery", result == VK_SUCCESS ? VK_ERROR_INITIALIZATION_FAILED : result); goto failed; }
    VkPhysicalDeviceDriverProperties driver_info = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES };
    VkPhysicalDeviceProperties2 properties = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &driver_info };
    gpu->vk.GetPhysicalDeviceProperties2(gpu->physical, &properties);
    if (driver_info.driverID != VK_DRIVER_ID_MESA_TURNIP || !strstr(driver_info.driverInfo, "e5f0687")) {
        snprintf(gpu->error, sizeof(gpu->error), "The pinned Turnip driver did not load. Reinstall graphics and restart Android Steam."); goto failed;
    }
    memcpy(gpu->device_name, properties.properties.deviceName, sizeof(gpu->device_name));
    uint32_t queues = 0;
    gpu->vk.GetPhysicalDeviceQueueFamilyProperties(gpu->physical, &queues, NULL);
    VkQueueFamilyProperties *families = calloc(queues, sizeof(*families));
    if (!families) { deck_gpu_error(gpu, "GPU queue allocation", VK_ERROR_OUT_OF_HOST_MEMORY); goto failed; }
    gpu->vk.GetPhysicalDeviceQueueFamilyProperties(gpu->physical, &queues, families);
    gpu->queue_family = UINT32_MAX;
    for (uint32_t i = 0; i < queues; i++) if (families[i].queueCount && (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) { gpu->queue_family = i; break; }
    free(families);
    if (gpu->queue_family == UINT32_MAX) { deck_gpu_error(gpu, "GPU graphics queue", VK_ERROR_INITIALIZATION_FAILED); goto failed; }
    const char *device_extensions[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME, VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME,
        VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME, VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME,
        VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME, VK_KHR_EXTERNAL_SEMAPHORE_FD_EXTENSION_NAME,
        VK_GOOGLE_DISPLAY_TIMING_EXTENSION_NAME };
    const uint32_t extension_count = sizeof(device_extensions) / sizeof(device_extensions[0]);
    if (!extensions(gpu, device_extensions, extension_count)) goto failed;
    VkPhysicalDeviceExternalSemaphoreInfo sync = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_SEMAPHORE_INFO,
        .handleType = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT };
    VkExternalSemaphoreProperties sync_properties = { .sType = VK_STRUCTURE_TYPE_EXTERNAL_SEMAPHORE_PROPERTIES };
    gpu->vk.GetPhysicalDeviceExternalSemaphoreProperties(gpu->physical, &sync, &sync_properties);
    if (!(sync_properties.externalSemaphoreFeatures & VK_EXTERNAL_SEMAPHORE_FEATURE_IMPORTABLE_BIT)) {
        deck_gpu_error(gpu, "Linux acquire fence support", VK_ERROR_FEATURE_NOT_PRESENT); goto failed;
    }
    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = gpu->queue_family,
        .queueCount = 1, .pQueuePriorities = &priority };
    VkDeviceCreateInfo device = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &queue,
        .enabledExtensionCount = extension_count, .ppEnabledExtensionNames = device_extensions };
    result = gpu->vk.CreateDevice(gpu->physical, &device, NULL, &gpu->device);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Adreno device creation", result); goto failed; }
#define LOAD(name) gpu->vk.name = (PFN_vk##name)gpu->vk.GetDeviceProcAddr(gpu->device, "vk" #name); \
    if (!gpu->vk.name) { deck_gpu_error(gpu, "vk" #name, VK_ERROR_EXTENSION_NOT_PRESENT); goto failed; }
    DECK_DEVICE_FUNCTIONS(LOAD)
#undef LOAD
    gpu->vk.GetDeviceQueue(gpu->device, gpu->queue_family, 0, &gpu->queue);
    VkCommandPoolCreateInfo pool = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = gpu->queue_family,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT };
    result = gpu->vk.CreateCommandPool(gpu->device, &pool, NULL, &gpu->commands);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "GPU command pool", result); goto failed; }
    VkCommandBufferAllocateInfo command = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = gpu->commands,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    result = gpu->vk.AllocateCommandBuffers(gpu->device, &command, &gpu->command);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "GPU command buffer", result); goto failed; }
    VkFenceCreateInfo fence = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT };
    result = gpu->vk.CreateFence(gpu->device, &fence, NULL, &gpu->fence);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "GPU completion fence", result); goto failed; }
    VkSemaphoreCreateInfo semaphore = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    result = gpu->vk.CreateSemaphore(gpu->device, &semaphore, NULL, &gpu->acquired);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Display acquire semaphore", result); goto failed; }
    result = gpu->vk.CreateSemaphore(gpu->device, &semaphore, NULL, &gpu->source_ready);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Linux acquire semaphore", result); goto failed; }
    return true;
failed:
    deck_gpu_close(gpu);
    return false;
}
void deck_gpu_close(struct deck_gpu *gpu) {
    if (gpu->device && gpu->vk.DestroyDevice) {
        if (gpu->vk.DeviceWaitIdle) gpu->vk.DeviceWaitIdle(gpu->device);
        deck_gpu_detach(gpu);
        if (gpu->commands) gpu->vk.DestroyCommandPool(gpu->device, gpu->commands, NULL);
        if (gpu->fence) gpu->vk.DestroyFence(gpu->device, gpu->fence, NULL);
        if (gpu->acquired) gpu->vk.DestroySemaphore(gpu->device, gpu->acquired, NULL);
        if (gpu->source_ready) gpu->vk.DestroySemaphore(gpu->device, gpu->source_ready, NULL);
        gpu->vk.DestroyDevice(gpu->device, NULL);
    }
    if (gpu->instance && gpu->vk.DestroyInstance) gpu->vk.DestroyInstance(gpu->instance, NULL);
    gpu->instance = VK_NULL_HANDLE; gpu->device = VK_NULL_HANDLE;
    gpu->commands = VK_NULL_HANDLE; gpu->fence = VK_NULL_HANDLE;
    gpu->acquired = VK_NULL_HANDLE; gpu->source_ready = VK_NULL_HANDLE;
}
