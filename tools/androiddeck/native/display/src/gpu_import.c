#include "gpu.h"
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

static bool importable(struct deck_gpu *gpu, uint64_t modifier) {
    VkPhysicalDeviceExternalImageFormatInfo external = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO,
        .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT };
    VkPhysicalDeviceImageDrmFormatModifierInfoEXT drm = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT,
        .pNext = &external, .drmFormatModifier = modifier, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
    VkPhysicalDeviceImageFormatInfo2 info = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2, .pNext = &drm,
        .format = VK_FORMAT_B8G8R8A8_UNORM, .type = VK_IMAGE_TYPE_2D, .tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT,
        .usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT };
    VkExternalImageFormatProperties properties = { .sType = VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES };
    VkImageFormatProperties2 result = { .sType = VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2, .pNext = &properties };
    return gpu->vk.GetPhysicalDeviceImageFormatProperties2(gpu->physical, &info, &result) == VK_SUCCESS &&
        (properties.externalMemoryProperties.externalMemoryFeatures & VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT);
}
size_t deck_gpu_modifiers(struct deck_gpu *gpu, uint64_t *out, size_t capacity) {
    VkDrmFormatModifierPropertiesListEXT modifiers = { .sType = VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT };
    VkFormatProperties2 properties = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2, .pNext = &modifiers };
    gpu->vk.GetPhysicalDeviceFormatProperties2(gpu->physical, VK_FORMAT_B8G8R8A8_UNORM, &properties);
    if (!modifiers.drmFormatModifierCount || modifiers.drmFormatModifierCount > 256) return 0;
    modifiers.pDrmFormatModifierProperties = calloc(modifiers.drmFormatModifierCount, sizeof(*modifiers.pDrmFormatModifierProperties));
    if (!modifiers.pDrmFormatModifierProperties) return 0;
    gpu->vk.GetPhysicalDeviceFormatProperties2(gpu->physical, VK_FORMAT_B8G8R8A8_UNORM, &properties);
    size_t count = 0;
    for (uint32_t i = 0; i < modifiers.drmFormatModifierCount && count < capacity; i++) {
        VkDrmFormatModifierPropertiesEXT *modifier = &modifiers.pDrmFormatModifierProperties[i];
        if (modifier->drmFormatModifierPlaneCount == 1 && (modifier->drmFormatModifierTilingFeatures & VK_FORMAT_FEATURE_BLIT_SRC_BIT) &&
            importable(gpu, modifier->drmFormatModifier)) out[count++] = modifier->drmFormatModifier;
    }
    free(modifiers.pDrmFormatModifierProperties);
    return count;
}
struct deck_gpu_image *deck_gpu_import(struct deck_gpu *gpu, int fd, uint64_t modifier, int width, int height, uint32_t stride, uint32_t offset) {
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192 || stride < (uint32_t)width * 4 || !importable(gpu, modifier)) return NULL;
    struct deck_gpu_image *image = calloc(1, sizeof(*image));
    if (!image) { deck_gpu_error(gpu, "Linux frame allocation", VK_ERROR_OUT_OF_HOST_MEMORY); return NULL; }
    image->gpu = gpu; image->fd = fd; image->width = width; image->height = height;
    VkSubresourceLayout plane = { .offset = offset, .rowPitch = stride };
    VkImageDrmFormatModifierExplicitCreateInfoEXT drm = { .sType = VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_EXPLICIT_CREATE_INFO_EXT,
        .drmFormatModifier = modifier, .drmFormatModifierPlaneCount = 1, .pPlaneLayouts = &plane };
    VkExternalMemoryImageCreateInfo external = { .sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO, .pNext = &drm,
        .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT };
    VkImageCreateInfo info = { .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .pNext = &external,
        .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_B8G8R8A8_UNORM, .extent = { width, height, 1 },
        .mipLevels = 1, .arrayLayers = 1, .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT,
        .usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT, .sharingMode = VK_SHARING_MODE_EXCLUSIVE, .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED };
    VkResult result = gpu->vk.CreateImage(gpu->device, &info, NULL, &image->image);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Linux frame image", result); goto failed; }
    VkMemoryRequirements requirements;
    gpu->vk.GetImageMemoryRequirements(gpu->device, image->image, &requirements);
    VkMemoryFdPropertiesKHR properties = { .sType = VK_STRUCTURE_TYPE_MEMORY_FD_PROPERTIES_KHR };
    result = gpu->vk.GetMemoryFdPropertiesKHR(gpu->device, VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, fd, &properties);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Linux frame memory properties", result); goto failed; }
    uint32_t allowed = properties.memoryTypeBits & requirements.memoryTypeBits;
    if (!allowed) { deck_gpu_error(gpu, "Linux frame memory type", VK_ERROR_INVALID_EXTERNAL_HANDLE); goto failed; }
    int owned = fcntl(fd, F_DUPFD_CLOEXEC, 0);
    if (owned < 0) { deck_gpu_error(gpu, "Linux frame descriptor", VK_ERROR_INVALID_EXTERNAL_HANDLE); goto failed; }
    VkImportMemoryFdInfoKHR import = { .sType = VK_STRUCTURE_TYPE_IMPORT_MEMORY_FD_INFO_KHR,
        .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, .fd = owned };
    VkMemoryDedicatedAllocateInfo dedicated = { .sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO, .pNext = &import, .image = image->image };
    VkMemoryAllocateInfo memory = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = &dedicated,
        .allocationSize = requirements.size, .memoryTypeIndex = (uint32_t)__builtin_ctz(allowed) };
    result = gpu->vk.AllocateMemory(gpu->device, &memory, NULL, &image->memory);
    if (result != VK_SUCCESS) { close(owned); deck_gpu_error(gpu, "Linux frame memory import", result); goto failed; }
    // Successful import transfers the duplicated descriptor to Vulkan.
    result = gpu->vk.BindImageMemory(gpu->device, image->image, image->memory, 0);
    if (result != VK_SUCCESS) { deck_gpu_error(gpu, "Linux frame memory binding", result); goto failed; }
    return image;
failed:
    deck_gpu_image_destroy(image);
    return NULL;
}
void deck_gpu_image_destroy(struct deck_gpu_image *image) {
    if (!image) return;
    if (image->image) image->gpu->vk.DestroyImage(image->gpu->device, image->image, NULL);
    if (image->memory) image->gpu->vk.FreeMemory(image->gpu->device, image->memory, NULL);
    free(image);
}
