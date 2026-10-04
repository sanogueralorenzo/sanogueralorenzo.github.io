#include "gpu.h"
#include <stdlib.h>

void deck_gpu_detach(struct deck_gpu *gpu) {
    gpu->generation++;
    if (gpu->swapchain) {
        gpu->vk.DeviceWaitIdle(gpu->device);
        for (uint32_t i = 0; i < gpu->image_count; i++) if (gpu->ready && gpu->ready[i]) gpu->vk.DestroySemaphore(gpu->device, gpu->ready[i], NULL);
        gpu->vk.DestroySwapchainKHR(gpu->device, gpu->swapchain, NULL);
    }
    free(gpu->images); free(gpu->ready);
    gpu->images = NULL; gpu->ready = NULL; gpu->image_count = 0; gpu->swapchain = VK_NULL_HANDLE;
    if (gpu->surface) gpu->vk.DestroySurfaceKHR(gpu->instance, gpu->surface, NULL);
    gpu->surface = VK_NULL_HANDLE;
    gpu->window = NULL;
}
bool deck_gpu_attach(struct deck_gpu *gpu, ANativeWindow *window) {
    deck_gpu_detach(gpu);
    if (!window) return true;
    VkAndroidSurfaceCreateInfoKHR surface = { .sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR, .window = window };
    VkResult result = gpu->vk.CreateAndroidSurfaceKHR(gpu->instance, &surface, NULL, &gpu->surface);
    if (result != VK_SUCCESS) return deck_gpu_error(gpu, "Android Vulkan surface", result);
    VkBool32 supported = false;
    result = gpu->vk.GetPhysicalDeviceSurfaceSupportKHR(gpu->physical, gpu->queue_family, gpu->surface, &supported);
    if (result != VK_SUCCESS || !supported) { deck_gpu_error(gpu, "Android presentation queue", result == VK_SUCCESS ? VK_ERROR_FEATURE_NOT_PRESENT : result); goto failed; }
    VkSurfaceCapabilitiesKHR caps;
    result = gpu->vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(gpu->physical, gpu->surface, &caps);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Android surface capabilities", result); goto failed; }
    if (!(caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT)) { deck_gpu_error(gpu, "Android transfer presentation", VK_ERROR_FEATURE_NOT_PRESENT); goto failed; }
    uint32_t count = 0;
    result = gpu->vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu->physical, gpu->surface, &count, NULL);
    if (result != VK_SUCCESS || !count) { deck_gpu_error(gpu, "Android surface format query", result == VK_SUCCESS ? VK_ERROR_FORMAT_NOT_SUPPORTED : result); goto failed; }
    VkSurfaceFormatKHR *formats = calloc(count, sizeof(*formats));
    if (!formats) { deck_gpu_error(gpu, "Surface format allocation", VK_ERROR_OUT_OF_HOST_MEMORY); goto failed; }
    result = gpu->vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu->physical, gpu->surface, &count, formats);
    gpu->format = VK_FORMAT_UNDEFINED;
    for (uint32_t i = 0; result == VK_SUCCESS && i < count; i++) {
        if (formats[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR &&
            (formats[i].format == VK_FORMAT_R8G8B8A8_UNORM || formats[i].format == VK_FORMAT_B8G8R8A8_UNORM)) { gpu->format = formats[i].format; break; }
    }
    free(formats);
    if (gpu->format == VK_FORMAT_UNDEFINED) { deck_gpu_error(gpu, "Android 8-bit surface format", VK_ERROR_FORMAT_NOT_SUPPORTED); goto failed; }
    VkFormatProperties2 properties = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2 };
    gpu->vk.GetPhysicalDeviceFormatProperties2(gpu->physical, gpu->format, &properties);
    if (!(properties.formatProperties.optimalTilingFeatures & VK_FORMAT_FEATURE_BLIT_DST_BIT)) { deck_gpu_error(gpu, "Android frame copy format", VK_ERROR_FORMAT_NOT_SUPPORTED); goto failed; }
    gpu->extent = caps.currentExtent;
    if (gpu->extent.width == UINT32_MAX) {
        gpu->extent.width = (uint32_t)ANativeWindow_getWidth(window);
        gpu->extent.height = (uint32_t)ANativeWindow_getHeight(window);
        if (gpu->extent.width < caps.minImageExtent.width) gpu->extent.width = caps.minImageExtent.width;
        if (gpu->extent.width > caps.maxImageExtent.width) gpu->extent.width = caps.maxImageExtent.width;
        if (gpu->extent.height < caps.minImageExtent.height) gpu->extent.height = caps.minImageExtent.height;
        if (gpu->extent.height > caps.maxImageExtent.height) gpu->extent.height = caps.maxImageExtent.height;
    }
    if (!gpu->extent.width || !gpu->extent.height) { deck_gpu_error(gpu, "Android surface dimensions", VK_ERROR_INITIALIZATION_FAILED); goto failed; }
    uint32_t images = caps.minImageCount + 1;
    if (caps.maxImageCount && images > caps.maxImageCount) images = caps.maxImageCount;
    VkCompositeAlphaFlagBitsKHR alpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    if (!(caps.supportedCompositeAlpha & alpha)) alpha = (VkCompositeAlphaFlagBitsKHR)(caps.supportedCompositeAlpha & (0u - caps.supportedCompositeAlpha));
    VkSwapchainCreateInfoKHR swapchain = { .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = gpu->surface, .minImageCount = images, .imageFormat = gpu->format,
        .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, .imageExtent = gpu->extent,
        .imageArrayLayers = 1, .imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE, .preTransform = caps.currentTransform,
        .compositeAlpha = alpha, .presentMode = VK_PRESENT_MODE_FIFO_KHR, .clipped = true };
    result = gpu->vk.CreateSwapchainKHR(gpu->device, &swapchain, NULL, &gpu->swapchain);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Android swapchain", result); goto failed; }
    result = gpu->vk.GetSwapchainImagesKHR(gpu->device, gpu->swapchain, &gpu->image_count, NULL);
    if (result != VK_SUCCESS || !gpu->image_count) { deck_gpu_error(gpu, "Android swapchain images", result); goto failed; }
    gpu->images = calloc(gpu->image_count, sizeof(*gpu->images));
    gpu->ready = calloc(gpu->image_count, sizeof(*gpu->ready));
    if (!gpu->images || !gpu->ready) { deck_gpu_error(gpu, "Swapchain image allocation", VK_ERROR_OUT_OF_HOST_MEMORY); goto failed; }
    uint32_t retrieved = gpu->image_count;
    result = gpu->vk.GetSwapchainImagesKHR(gpu->device, gpu->swapchain, &retrieved, gpu->images);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Android swapchain image retrieval", result); goto failed; }
    gpu->image_count = retrieved;
    VkSemaphoreCreateInfo semaphore = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    for (uint32_t i = 0; i < gpu->image_count; i++) {
        result = gpu->vk.CreateSemaphore(gpu->device, &semaphore, NULL, &gpu->ready[i]);
        if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Android presentation semaphore", result); goto failed; }
    }
    gpu->window = window;
    return true;
failed:
    deck_gpu_detach(gpu);
    return false;
}
