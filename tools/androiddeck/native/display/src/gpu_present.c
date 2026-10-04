#include "gpu.h"
#include <unistd.h>

bool deck_gpu_present(struct deck_gpu *gpu, struct deck_gpu_image *image, int acquire_fd) {
    VkResult result = VK_ERROR_SURFACE_LOST_KHR;
    if (!gpu->swapchain) goto failed;
    result = gpu->vk.WaitForFences(gpu->device, 1, &gpu->fence, true, 1000000000);
    if (result != VK_SUCCESS) goto failed;
    uint32_t index;
    result = gpu->vk.AcquireNextImageKHR(gpu->device, gpu->swapchain, 1000000000, gpu->acquired, VK_NULL_HANDLE, &index);
    if (result == VK_ERROR_OUT_OF_DATE_KHR) {
        ANativeWindow *window = gpu->window;
        if (!deck_gpu_attach(gpu, window)) { if (acquire_fd >= 0) close(acquire_fd); return false; }
        result = gpu->vk.AcquireNextImageKHR(gpu->device, gpu->swapchain, 1000000000, gpu->acquired, VK_NULL_HANDLE, &index);
    }
    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR) goto failed;
    const bool explicit_sync = acquire_fd >= 0;
    if (explicit_sync) {
        VkImportSemaphoreFdInfoKHR import = { .sType = VK_STRUCTURE_TYPE_IMPORT_SEMAPHORE_FD_INFO_KHR,
            .semaphore = gpu->source_ready, .flags = VK_SEMAPHORE_IMPORT_TEMPORARY_BIT,
            .handleType = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT, .fd = acquire_fd };
        result = gpu->vk.ImportSemaphoreFdKHR(gpu->device, &import);
        if (result != VK_SUCCESS) goto failed;
        acquire_fd = -1; // Vulkan owns the descriptor after a successful import.
    }
    result = gpu->vk.ResetCommandBuffer(gpu->command, 0);
    if (result != VK_SUCCESS) goto failed;
    VkCommandBufferBeginInfo begin = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    result = gpu->vk.BeginCommandBuffer(gpu->command, &begin);
    if (result != VK_SUCCESS) goto failed;
    VkImageSubresourceRange range = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
    // The foreign dma-buf acquisition follows the Turnip compositor import
    // path. Its modifier describes the shared storage; Android owns no producer layout.
    VkImageMemoryBarrier barriers[2] = {
        { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
          .newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_FOREIGN_EXT,
          .dstQueueFamilyIndex = gpu->queue_family, .image = image->image, .subresourceRange = range,
          .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT },
        { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
          .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = gpu->images[index], .subresourceRange = range,
          .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT }
    };
    gpu->vk.CmdPipelineBarrier(gpu->command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, NULL, 0, NULL, 2, barriers);
    VkImageBlit copy = { .srcSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
        .srcOffsets = { {0, 0, 0}, {image->width, image->height, 1} },
        .dstSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
        .dstOffsets = { {0, 0, 0}, {gpu->extent.width, gpu->extent.height, 1} } };
    gpu->vk.CmdBlitImage(gpu->command, image->image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        gpu->images[index], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy, VK_FILTER_NEAREST);
    barriers[0].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    barriers[0].newLayout = VK_IMAGE_LAYOUT_GENERAL;
    barriers[0].srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT; barriers[0].dstAccessMask = 0;
    barriers[0].srcQueueFamilyIndex = gpu->queue_family; barriers[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_FOREIGN_EXT;
    barriers[1].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barriers[1].newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    barriers[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; barriers[1].dstAccessMask = 0;
    gpu->vk.CmdPipelineBarrier(gpu->command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        0, 0, NULL, 0, NULL, 2, barriers);
    result = gpu->vk.EndCommandBuffer(gpu->command);
    if (result != VK_SUCCESS) goto failed;
    VkSemaphore waits[2] = { gpu->acquired, gpu->source_ready };
    VkPipelineStageFlags stages[2] = { VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT };
    VkSubmitInfo submit = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .waitSemaphoreCount = explicit_sync ? 2 : 1,
        .pWaitSemaphores = waits, .pWaitDstStageMask = stages, .commandBufferCount = 1, .pCommandBuffers = &gpu->command,
        .signalSemaphoreCount = 1, .pSignalSemaphores = &gpu->ready[index] };
    result = gpu->vk.ResetFences(gpu->device, 1, &gpu->fence);
    if (result != VK_SUCCESS) goto failed;
    result = gpu->vk.QueueSubmit(gpu->queue, 1, &submit, gpu->fence);
    if (result != VK_SUCCESS) goto failed;
    VkPresentInfoKHR present = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, .waitSemaphoreCount = 1,
        .pWaitSemaphores = &gpu->ready[index], .swapchainCount = 1, .pSwapchains = &gpu->swapchain, .pImageIndices = &index };
    VkResult presented = gpu->vk.QueuePresentKHR(gpu->queue, &present);
    result = gpu->vk.WaitForFences(gpu->device, 1, &gpu->fence, true, 1000000000);
    if (result != VK_SUCCESS) goto failed;
    // A completed submission has finished reading the Linux buffer. Release
    // it now; presentation semaphores stay associated with swapchain images.
    if (presented == VK_ERROR_OUT_OF_DATE_KHR) {
        ANativeWindow *window = gpu->window;
        return deck_gpu_attach(gpu, window);
    }
    if (presented == VK_SUCCESS || presented == VK_SUBOPTIMAL_KHR) return true;
    result = presented;
failed:
    if (acquire_fd >= 0) close(acquire_fd);
    return deck_gpu_error(gpu, "Linux frame presentation", result);
}
