// Debug-only GNU/Linux client: exercise Mesa's real Wayland Vulkan WSI.
#define VK_NO_PROTOTYPES
#define VK_USE_PLATFORM_WAYLAND_KHR
#include <vulkan/vulkan.h>
#include <wayland-client.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

int probe_vulkan(struct wl_display *display, struct wl_surface *window) {
    void *library = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "Linux Vulkan loader: %s\n", dlerror()); return 4; }
    PFN_vkGetInstanceProcAddr get = (PFN_vkGetInstanceProcAddr)dlsym(library, "vkGetInstanceProcAddr");
    if (!get) { dlclose(library); return 4; }
    VkInstance instance = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    VkSemaphore acquired = VK_NULL_HANDLE;
    VkImage *images = NULL;
    VkSemaphore *ready = NULL;
    uint32_t count = 0;
    int status = 4;
    VkResult result;
#define INSTANCE_FUNCTIONS(X) X(DestroyInstance) X(CreateWaylandSurfaceKHR) X(DestroySurfaceKHR) \
    X(EnumeratePhysicalDevices) X(GetPhysicalDeviceProperties2) X(GetPhysicalDeviceQueueFamilyProperties) \
    X(GetPhysicalDeviceSurfaceSupportKHR) X(GetPhysicalDeviceSurfaceCapabilitiesKHR) \
    X(GetPhysicalDeviceSurfaceFormatsKHR) X(CreateDevice) X(GetDeviceProcAddr)
#define DEVICE_FUNCTIONS(X) X(DestroyDevice) X(DeviceWaitIdle) X(GetDeviceQueue) X(CreateSwapchainKHR) \
    X(DestroySwapchainKHR) X(GetSwapchainImagesKHR) X(AcquireNextImageKHR) X(QueuePresentKHR) \
    X(CreateCommandPool) X(DestroyCommandPool) X(AllocateCommandBuffers) X(ResetCommandBuffer) \
    X(BeginCommandBuffer) X(EndCommandBuffer) X(CmdPipelineBarrier) X(CmdClearColorImage) \
    X(CreateFence) X(DestroyFence) X(WaitForFences) X(ResetFences) X(CreateSemaphore) X(DestroySemaphore) X(QueueSubmit)
#define DECLARE(name) PFN_vk##name name = NULL;
    INSTANCE_FUNCTIONS(DECLARE)
    DEVICE_FUNCTIONS(DECLARE)
#undef DECLARE
#define CHECK(operation) do { result = (operation); if (result != VK_SUCCESS) { fprintf(stderr, "%s: Vulkan %d\n", #operation, result); goto done; } } while (0)
    PFN_vkCreateInstance create = (PFN_vkCreateInstance)get(NULL, "vkCreateInstance");
    if (!create) goto done;
    const char *extensions[] = { VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME };
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_2 };
    VkInstanceCreateInfo info = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app,
        .enabledExtensionCount = 2, .ppEnabledExtensionNames = extensions };
    CHECK(create(&info, NULL, &instance));
#define LOAD(name) name = (PFN_vk##name)get(instance, "vk" #name); if (!name) { fprintf(stderr, "Missing vk%s\n", #name); goto done; }
    INSTANCE_FUNCTIONS(LOAD)
#undef LOAD
    VkWaylandSurfaceCreateInfoKHR wayland = { .sType = VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR, .display = display, .surface = window };
    CHECK(CreateWaylandSurfaceKHR(instance, &wayland, NULL, &surface));
    VkPhysicalDevice physical;
    uint32_t physical_count = 1;
    CHECK(EnumeratePhysicalDevices(instance, &physical_count, &physical));
    if (physical_count != 1) goto done;
    VkPhysicalDeviceDriverProperties driver = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES };
    VkPhysicalDeviceProperties2 properties = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &driver };
    GetPhysicalDeviceProperties2(physical, &properties);
    if (driver.driverID != VK_DRIVER_ID_MESA_TURNIP) { fputs("Linux did not select the Turnip driver\n", stderr); goto done; }
    uint32_t queues = 0;
    GetPhysicalDeviceQueueFamilyProperties(physical, &queues, NULL);
    VkQueueFamilyProperties *families = calloc(queues, sizeof(*families));
    if (!families) goto done;
    GetPhysicalDeviceQueueFamilyProperties(physical, &queues, families);
    uint32_t family = UINT32_MAX;
    for (uint32_t i = 0; i < queues; i++) {
        VkBool32 supported = false;
        if (GetPhysicalDeviceSurfaceSupportKHR(physical, i, surface, &supported) == VK_SUCCESS && supported &&
            families[i].queueCount && (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) { family = i; break; }
    }
    free(families);
    if (family == UINT32_MAX) goto done;
    float priority = 1;
    VkDeviceQueueCreateInfo queue_info = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = family,
        .queueCount = 1, .pQueuePriorities = &priority };
    const char *swapchain_extension = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    VkDeviceCreateInfo device_info = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_info, .enabledExtensionCount = 1, .ppEnabledExtensionNames = &swapchain_extension };
    CHECK(CreateDevice(physical, &device_info, NULL, &device));
#define LOAD(name) name = (PFN_vk##name)GetDeviceProcAddr(device, "vk" #name); if (!name) { fprintf(stderr, "Missing vk%s\n", #name); goto done; }
    DEVICE_FUNCTIONS(LOAD)
#undef LOAD
    VkQueue queue;
    GetDeviceQueue(device, family, 0, &queue);
    VkSurfaceCapabilitiesKHR caps;
    CHECK(GetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &caps));
    if (!(caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT)) goto done;
    uint32_t format_count = 0;
    CHECK(GetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &format_count, NULL));
    VkSurfaceFormatKHR *formats = calloc(format_count, sizeof(*formats));
    if (!formats) goto done;
    result = GetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &format_count, formats);
    VkFormat format = VK_FORMAT_UNDEFINED;
    for (uint32_t i = 0; result == VK_SUCCESS && i < format_count; i++) if (formats[i].format == VK_FORMAT_B8G8R8A8_UNORM &&
        formats[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) { format = formats[i].format; break; }
    free(formats);
    if (format == VK_FORMAT_UNDEFINED) goto done;
    VkExtent2D extent = caps.currentExtent;
    if (extent.width == UINT32_MAX) extent = (VkExtent2D){320, 200};
    uint32_t requested = caps.minImageCount + 1;
    if (caps.maxImageCount && requested > caps.maxImageCount) requested = caps.maxImageCount;
    VkSwapchainCreateInfoKHR swapchain_info = { .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, .surface = surface,
        .minImageCount = requested, .imageFormat = format, .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        .imageExtent = extent, .imageArrayLayers = 1, .imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE, .preTransform = caps.currentTransform,
        .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR, .presentMode = VK_PRESENT_MODE_FIFO_KHR, .clipped = true };
    CHECK(CreateSwapchainKHR(device, &swapchain_info, NULL, &swapchain));
    CHECK(GetSwapchainImagesKHR(device, swapchain, &count, NULL));
    images = calloc(count, sizeof(*images)); ready = calloc(count, sizeof(*ready));
    if (!images || !ready) goto done;
    uint32_t retrieved = count;
    CHECK(GetSwapchainImagesKHR(device, swapchain, &retrieved, images));
    count = retrieved;
    VkSemaphoreCreateInfo semaphore = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    CHECK(CreateSemaphore(device, &semaphore, NULL, &acquired));
    for (uint32_t i = 0; i < count; i++) CHECK(CreateSemaphore(device, &semaphore, NULL, &ready[i]));
    VkCommandPoolCreateInfo pool_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = family,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT };
    CHECK(CreateCommandPool(device, &pool_info, NULL, &pool));
    VkCommandBuffer command;
    VkCommandBufferAllocateInfo command_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    CHECK(AllocateCommandBuffers(device, &command_info, &command));
    VkFenceCreateInfo fence_info = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT };
    CHECK(CreateFence(device, &fence_info, NULL, &fence));
    for (uint32_t frame = 0; frame < 3; frame++) {
        CHECK(WaitForFences(device, 1, &fence, true, 2000000000));
        uint32_t index;
        CHECK(AcquireNextImageKHR(device, swapchain, 2000000000, acquired, VK_NULL_HANDLE, &index));
        CHECK(ResetCommandBuffer(command, 0));
        VkCommandBufferBeginInfo begin = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
        CHECK(BeginCommandBuffer(command, &begin));
        VkImageSubresourceRange range = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
        VkImageMemoryBarrier barrier = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = images[index], .subresourceRange = range, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT };
        CmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &barrier);
        VkClearColorValue color = { .float32 = {0, 0, 0, 1} }; color.float32[frame] = 1;
        CmdClearColorImage(command, images[index], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1, &range);
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; barrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; barrier.dstAccessMask = 0;
        CmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1, &barrier);
        CHECK(EndCommandBuffer(command));
        CHECK(ResetFences(device, 1, &fence));
        VkPipelineStageFlags stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
        VkSubmitInfo submit = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .waitSemaphoreCount = 1, .pWaitSemaphores = &acquired,
            .pWaitDstStageMask = &stage, .commandBufferCount = 1, .pCommandBuffers = &command,
            .signalSemaphoreCount = 1, .pSignalSemaphores = &ready[index] };
        CHECK(QueueSubmit(queue, 1, &submit, fence));
        VkPresentInfoKHR present = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, .waitSemaphoreCount = 1,
            .pWaitSemaphores = &ready[index], .swapchainCount = 1, .pSwapchains = &swapchain, .pImageIndices = &index };
        CHECK(QueuePresentKHR(queue, &present));
    }
    CHECK(DeviceWaitIdle(device));
    if (wl_display_roundtrip(display) < 0) goto done;
    printf("linux-vulkan-ok: 3 frames, %ux%u, %s\n", extent.width, extent.height, properties.properties.deviceName);
    status = 0;
done:
    if (device && DeviceWaitIdle) DeviceWaitIdle(device);
    if (pool) DestroyCommandPool(device, pool, NULL);
    if (fence) DestroyFence(device, fence, NULL);
    if (acquired) DestroySemaphore(device, acquired, NULL);
    if (ready) for (uint32_t i = 0; i < count; i++) if (ready[i]) DestroySemaphore(device, ready[i], NULL);
    if (swapchain) DestroySwapchainKHR(device, swapchain, NULL);
    if (device && DestroyDevice) DestroyDevice(device, NULL);
    if (surface) DestroySurfaceKHR(instance, surface, NULL);
    if (instance && DestroyInstance) DestroyInstance(instance, NULL);
    free(images); free(ready); dlclose(library);
    return status;
}
