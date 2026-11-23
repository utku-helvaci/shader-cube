// SPDX-License-Identifier: MIT
/*
 * Vulkan 1.3 backend: dynamic rendering, push descriptors, GLSL compiled to
 * SPIR-V at runtime with shaderc (so Shadertoy sources work unchanged).
 *
 * Every resource tracks its current image layout and the backend inserts
 * (conservative) barriers when a texture changes role.  Textures sampled by
 * a draw are transitioned before rendering begins; if a later draw in the
 * same pass needs a transition the rendering is split, which LOAD/STORE ops
 * make transparent.
 *
 * The physical device is the first one the loader reports that can do the
 * job, so prime-run / MESA_VK_DEVICE_SELECT / DRI_PRIME decide, not us.
 */
#include <vulkan/vulkan.h>
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>
#include <shaderc/shaderc.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gfx.h"

#define FRAMES 2
#define RING_BYTES (16u << 20)
#define MAX_SC 8
#define MAX_PIPES 12
#define MAX_TEMP 64

#define VKCHECK(x)                                                                       \
    do {                                                                                 \
        VkResult r_ = (x);                                                               \
        if (r_ < 0) {                                                                    \
            fprintf(stderr, "Vulkan error %d at %s:%d: %s\n", r_, __FILE__, __LINE__, #x); \
            exit(1);                                                                     \
        }                                                                                \
    } while (0)

struct GfxTex {
    GfxFormat fmt;
    VkFormat vkfmt;
    VkImage img;
    VkDeviceMemory mem;
    VkImageView view; /* sampling view, all levels */
    VkImageView *rt;  /* attachment views: one per slice of a 3D texture, else one */
    int nrt;
    int w, h, d, levels, samples;
    VkImageAspectFlags aspect;
    VkImageLayout layout;
    int owned; /* 0 for swapchain images */
};

struct GfxBuf {
    VkBuffer buf;
    VkDeviceMemory mem;
};

typedef struct {
    VkFormat color;
    int has_depth, samples, depth, cull, blend;
    VkPipeline pipe;
} PipeEntry;

struct GfxProg {
    char label[96];
    VkShaderModule vs, fs;
    int vtx;
    PipeEntry pipes[MAX_PIPES];
    int npipes;
};

typedef struct {
    VkBuffer buf;
    VkDeviceMemory mem;
    unsigned char *map;
    VkDeviceSize size, off;
} Ring;

typedef struct {
    VkCommandPool pool;
    VkCommandBuffer cmd;
    VkFence fence;
    VkSemaphore acquired;
    Ring ring;
} Frame;

static struct {
    GfxConfig cfg;
    GLFWwindow *win;
    VkInstance inst;
    VkDebugUtilsMessengerEXT messenger;
    VkSurfaceKHR surface;
    VkPhysicalDevice phys;
    VkPhysicalDeviceProperties props;
    VkPhysicalDeviceMemoryProperties memprops;
    VkDevice dev;
    uint32_t qfam;
    VkQueue queue;
    PFN_vkCmdPushDescriptorSetKHR push_desc;
    VkDescriptorSetLayout dsl;
    VkPipelineLayout layout;
    VkSampler samplers[3][2];
    shaderc_compiler_t sc;
    int float_linear, max_samples;
    VkFormat depth_fmt;

    /* swapchain */
    VkSwapchainKHR swapchain;
    VkFormat sc_fmt;
    VkExtent2D sc_ext;
    uint32_t sc_count;
    GfxTex sc_tex[MAX_SC];
    VkImageView sc_views[MAX_SC];
    VkSemaphore sc_done[MAX_SC];
    int sc_dirty;

    /* frames */
    Frame fr[FRAMES];
    int cur, recording, acquired;
    uint32_t sc_index;

    /* work outside a frame (texture init, uploads at load time) */
    VkCommandPool setup_pool;
    VkCommandBuffer setup;
    struct { VkBuffer buf; VkDeviceMemory mem; } temp[MAX_TEMP];
    int ntemp;

    /* current pass */
    GfxPass pass;
    GfxTex *pass_color;
    int pass_w, pass_h, rendering, pending_clear, pass_skip;
    VkPipeline bound;

    /* readback */
    VkBuffer rb_buf;
    VkDeviceMemory rb_mem;
    void *rb_map;
    VkDeviceSize rb_size;
    void *rb_dst;
    size_t rb_bytes;

    char device[256];
} V;

static const char *PRELUDE =
    "#version 450\n"
    "#define GFX_VULKAN 1\n"
    "#define GFX_UBO(n) layout(std140, set=0, binding=n) uniform\n"
    "#define GFX_TEX(n) layout(set=0, binding=n) uniform\n"
    "#define GFX_VERTEX_ID gl_VertexIndex\n"
    "#define GFX_CLIP(p) vec4((p).xy, ((p).z + (p).w) * 0.5, (p).w)\n";

/* ---------------------------------------------------------------- helpers */

static uint32_t find_mem(uint32_t bits, VkMemoryPropertyFlags want) {
    for (uint32_t i = 0; i < V.memprops.memoryTypeCount; i++)
        if ((bits & (1u << i)) && (V.memprops.memoryTypes[i].propertyFlags & want) == want) return i;
    return UINT32_MAX;
}

static VkDeviceMemory alloc_mem(VkMemoryRequirements req, VkMemoryPropertyFlags want) {
    uint32_t type = find_mem(req.memoryTypeBits, want);
    if (type == UINT32_MAX && (want & VK_MEMORY_PROPERTY_HOST_CACHED_BIT))
        type = find_mem(req.memoryTypeBits, want & ~(VkMemoryPropertyFlags)VK_MEMORY_PROPERTY_HOST_CACHED_BIT);
    if (type == UINT32_MAX && (want & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))
        type = find_mem(req.memoryTypeBits, 0);
    if (type == UINT32_MAX) {
        fprintf(stderr, "Vulkan: no suitable memory type\n");
        exit(1);
    }
    VkMemoryAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                               .allocationSize = req.size, .memoryTypeIndex = type};
    VkDeviceMemory m;
    VKCHECK(vkAllocateMemory(V.dev, &ai, NULL, &m));
    return m;
}

static void make_buffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags want,
                        VkBuffer *buf, VkDeviceMemory *mem, void **map) {
    VkBufferCreateInfo bi = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size, .usage = usage,
                             .sharingMode = VK_SHARING_MODE_EXCLUSIVE};
    VKCHECK(vkCreateBuffer(V.dev, &bi, NULL, buf));
    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(V.dev, *buf, &req);
    *mem = alloc_mem(req, want);
    VKCHECK(vkBindBufferMemory(V.dev, *buf, *mem, 0));
    if (map) VKCHECK(vkMapMemory(V.dev, *mem, 0, VK_WHOLE_SIZE, 0, map));
}

static VkDeviceSize ring_alloc(Ring *r, VkDeviceSize size, VkDeviceSize align) {
    VkDeviceSize off = (r->off + align - 1) / align * align;
    if (off + size > r->size) {
        fprintf(stderr, "Vulkan: per-frame upload ring exhausted (%llu bytes)\n", (unsigned long long)r->size);
        exit(1);
    }
    r->off = off + size;
    return off;
}

/* Command buffer for transfer-type work: the frame's while recording,
 * otherwise a setup buffer that is flushed before the next frame. */
static VkCommandBuffer work_cmd(void) {
    if (V.recording) return V.fr[V.cur].cmd;
    if (!V.setup) {
        VkCommandBufferAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                                          .commandPool = V.setup_pool,
                                          .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
        VKCHECK(vkAllocateCommandBuffers(V.dev, &ai, &V.setup));
        VkCommandBufferBeginInfo bi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                                       .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
        VKCHECK(vkBeginCommandBuffer(V.setup, &bi));
    }
    return V.setup;
}

static void flush_setup(void) {
    if (!V.setup) return;
    VKCHECK(vkEndCommandBuffer(V.setup));
    VkSubmitInfo si = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &V.setup};
    VKCHECK(vkQueueSubmit(V.queue, 1, &si, VK_NULL_HANDLE));
    VKCHECK(vkQueueWaitIdle(V.queue));
    vkFreeCommandBuffers(V.dev, V.setup_pool, 1, &V.setup);
    V.setup = VK_NULL_HANDLE;
    for (int i = 0; i < V.ntemp; i++) {
        vkDestroyBuffer(V.dev, V.temp[i].buf, NULL);
        vkFreeMemory(V.dev, V.temp[i].mem, NULL);
    }
    V.ntemp = 0;
}

/* Copies data somewhere the GPU can read it during the current work_cmd. */
static void stage(const void *data, size_t size, VkBuffer *buf, VkDeviceSize *off) {
    if (V.recording) {
        Ring *r = &V.fr[V.cur].ring;
        *off = ring_alloc(r, size, 16);
        memcpy(r->map + *off, data, size);
        *buf = r->buf;
        return;
    }
    if (V.ntemp == MAX_TEMP) flush_setup();
    void *map;
    make_buffer(size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                &V.temp[V.ntemp].buf, &V.temp[V.ntemp].mem, &map);
    memcpy(map, data, size);
    vkUnmapMemory(V.dev, V.temp[V.ntemp].mem);
    *buf = V.temp[V.ntemp].buf;
    *off = 0;
    V.ntemp++;
}

static void img_barrier(VkCommandBuffer c, GfxTex *t, VkImageLayout from, VkImageLayout to,
                        uint32_t level, uint32_t nlevels) {
    VkImageMemoryBarrier b = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_MEMORY_WRITE_BIT,
        .dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT,
        .oldLayout = from,
        .newLayout = to,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = t->img,
        .subresourceRange = {t->aspect, level, nlevels, 0, VK_REMAINING_ARRAY_LAYERS},
    };
    vkCmdPipelineBarrier(c, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, NULL, 0,
                         NULL, 1, &b);
}

static void transition(VkCommandBuffer c, GfxTex *t, VkImageLayout to) {
    img_barrier(c, t, t->layout, to, 0, VK_REMAINING_MIP_LEVELS);
    t->layout = to;
}

/* ---------------------------------------------------------------- instance & device */

static VKAPI_ATTR VkBool32 VKAPI_CALL on_debug(VkDebugUtilsMessageSeverityFlagBitsEXT sev,
                                               VkDebugUtilsMessageTypeFlagsEXT type,
                                               const VkDebugUtilsMessengerCallbackDataEXT *d, void *user) {
    (void)type; (void)user;
    if (sev >= VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT)
        fprintf(stderr, "Vulkan %s: %s\n",
                sev >= VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT ? "error" : "warning", d->pMessage);
    return VK_FALSE;
}

static int has_layer(const char *name) {
    uint32_t n = 0;
    vkEnumerateInstanceLayerProperties(&n, NULL);
    VkLayerProperties *p = calloc(n ? n : 1, sizeof *p);
    vkEnumerateInstanceLayerProperties(&n, p);
    int found = 0;
    for (uint32_t i = 0; i < n; i++)
        if (!strcmp(p[i].layerName, name)) found = 1;
    free(p);
    return found;
}

static void create_instance(void) {
    const char *exts[16];
    uint32_t next = 0;
    if (V.win) {
        uint32_t n = 0;
        const char **req = glfwGetRequiredInstanceExtensions(&n);
        for (uint32_t i = 0; i < n && next < 14; i++) exts[next++] = req[i];
    }
    const char *layers[1];
    uint32_t nlayers = 0;
    if (V.cfg.debug) {
        exts[next++] = VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
        if (has_layer("VK_LAYER_KHRONOS_validation")) layers[nlayers++] = "VK_LAYER_KHRONOS_validation";
        else fprintf(stderr, "Vulkan: validation layer not installed\n");
    }
    VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .pApplicationName = "shader-cube",
                             .applicationVersion = 1, .pEngineName = "shader-cube",
                             .apiVersion = VK_API_VERSION_1_3};
    VkInstanceCreateInfo ci = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app,
                               .enabledExtensionCount = next, .ppEnabledExtensionNames = exts,
                               .enabledLayerCount = nlayers, .ppEnabledLayerNames = layers};
    VKCHECK(vkCreateInstance(&ci, NULL, &V.inst));
    if (V.cfg.debug) {
        PFN_vkCreateDebugUtilsMessengerEXT f =
            (PFN_vkCreateDebugUtilsMessengerEXT)vkGetInstanceProcAddr(V.inst, "vkCreateDebugUtilsMessengerEXT");
        VkDebugUtilsMessengerCreateInfoEXT mi = {
            .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                               VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                           VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                           VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = on_debug};
        if (f) f(V.inst, &mi, NULL, &V.messenger);
    }
}

static int dev_has_ext(VkPhysicalDevice pd, const char *name) {
    uint32_t n = 0;
    vkEnumerateDeviceExtensionProperties(pd, NULL, &n, NULL);
    VkExtensionProperties *e = calloc(n ? n : 1, sizeof *e);
    vkEnumerateDeviceExtensionProperties(pd, NULL, &n, e);
    int found = 0;
    for (uint32_t i = 0; i < n; i++)
        if (!strcmp(e[i].extensionName, name)) found = 1;
    free(e);
    return found;
}

/* First device (in the order the loader and its layers report them) that
 * can render, and present to our window if there is one. */
static int pick_device(void) {
    uint32_t n = 0;
    vkEnumeratePhysicalDevices(V.inst, &n, NULL);
    if (!n) {
        fprintf(stderr, "Vulkan: no devices\n");
        return 0;
    }
    VkPhysicalDevice *devs = calloc(n, sizeof *devs);
    vkEnumeratePhysicalDevices(V.inst, &n, devs);
    for (uint32_t i = 0; i < n; i++) {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(devs[i], &p);
        const char *why = NULL;
        VkPhysicalDeviceVulkan13Features f13 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
        VkPhysicalDeviceFeatures2 f2 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &f13};
        if (p.apiVersion >= VK_API_VERSION_1_3) vkGetPhysicalDeviceFeatures2(devs[i], &f2);
        if (p.apiVersion < VK_API_VERSION_1_3) why = "Vulkan 1.3 required";
        else if (!f13.dynamicRendering) why = "no dynamic rendering";
        else if (!dev_has_ext(devs[i], VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME)) why = "no VK_KHR_push_descriptor";
        else if (V.surface && !dev_has_ext(devs[i], VK_KHR_SWAPCHAIN_EXTENSION_NAME)) why = "no swapchain";
        int qf = -1;
        if (!why) {
            uint32_t nq = 0;
            vkGetPhysicalDeviceQueueFamilyProperties(devs[i], &nq, NULL);
            VkQueueFamilyProperties *q = calloc(nq, sizeof *q);
            vkGetPhysicalDeviceQueueFamilyProperties(devs[i], &nq, q);
            for (uint32_t k = 0; k < nq && qf < 0; k++) {
                if (!(q[k].queueFlags & VK_QUEUE_GRAPHICS_BIT)) continue;
                VkBool32 present = VK_TRUE;
                if (V.surface) vkGetPhysicalDeviceSurfaceSupportKHR(devs[i], k, V.surface, &present);
                if (present) qf = (int)k;
            }
            free(q);
            if (qf < 0) why = V.surface ? "cannot present to this window" : "no graphics queue";
        }
        if (why) {
            fprintf(stderr, "Vulkan: skipping %s (%s)\n", p.deviceName, why);
            continue;
        }
        V.phys = devs[i];
        V.props = p;
        V.qfam = (uint32_t)qf;
        snprintf(V.device, sizeof V.device, "%s", p.deviceName);
        printf("Vulkan %u.%u.%u: %s (device %u of %u as ordered by the loader)\n", VK_API_VERSION_MAJOR(p.apiVersion),
               VK_API_VERSION_MINOR(p.apiVersion), VK_API_VERSION_PATCH(p.apiVersion), p.deviceName, i + 1, n);
        free(devs);
        return 1;
    }
    free(devs);
    fprintf(stderr, "Vulkan: no usable device\n");
    return 0;
}

static void create_device(void) {
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qi = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = V.qfam,
                                  .queueCount = 1, .pQueuePriorities = &prio};
    const char *exts[2];
    uint32_t next = 0;
    exts[next++] = VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME;
    if (V.surface) exts[next++] = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    VkPhysicalDeviceVulkan13Features f13 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
                                            .dynamicRendering = VK_TRUE};
    VkDeviceCreateInfo ci = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &f13,
                             .queueCreateInfoCount = 1, .pQueueCreateInfos = &qi,
                             .enabledExtensionCount = next, .ppEnabledExtensionNames = exts};
    VKCHECK(vkCreateDevice(V.phys, &ci, NULL, &V.dev));
    vkGetDeviceQueue(V.dev, V.qfam, 0, &V.queue);
    V.push_desc = (PFN_vkCmdPushDescriptorSetKHR)vkGetDeviceProcAddr(V.dev, "vkCmdPushDescriptorSetKHR");
    vkGetPhysicalDeviceMemoryProperties(V.phys, &V.memprops);
}

/* ---------------------------------------------------------------- swapchain */

static void destroy_swapchain_views(void) {
    for (uint32_t i = 0; i < V.sc_count; i++) {
        vkDestroyImageView(V.dev, V.sc_views[i], NULL);
        vkDestroySemaphore(V.dev, V.sc_done[i], NULL);
    }
    V.sc_count = 0;
}

static void create_swapchain(void) {
    vkDeviceWaitIdle(V.dev);
    V.sc_dirty = 0;
    VkSurfaceCapabilitiesKHR caps;
    VKCHECK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(V.phys, V.surface, &caps));
    VkExtent2D ext = caps.currentExtent;
    if (ext.width == UINT32_MAX) {
        int w, h;
        glfwGetFramebufferSize(V.win, &w, &h);
        ext.width = (uint32_t)w;
        ext.height = (uint32_t)h;
        if (ext.width < caps.minImageExtent.width) ext.width = caps.minImageExtent.width;
        if (ext.height < caps.minImageExtent.height) ext.height = caps.minImageExtent.height;
        if (ext.width > caps.maxImageExtent.width) ext.width = caps.maxImageExtent.width;
        if (ext.height > caps.maxImageExtent.height) ext.height = caps.maxImageExtent.height;
    }
    destroy_swapchain_views();
    if (ext.width == 0 || ext.height == 0) { /* minimised */
        if (V.swapchain) vkDestroySwapchainKHR(V.dev, V.swapchain, NULL);
        V.swapchain = VK_NULL_HANDLE;
        V.sc_ext = ext;
        return;
    }

    uint32_t nf = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(V.phys, V.surface, &nf, NULL);
    VkSurfaceFormatKHR *fmts = calloc(nf ? nf : 1, sizeof *fmts);
    vkGetPhysicalDeviceSurfaceFormatsKHR(V.phys, V.surface, &nf, fmts);
    VkSurfaceFormatKHR fmt = fmts[0];
    for (uint32_t i = 0; i < nf; i++) /* non-sRGB, like the GL default framebuffer */
        if ((fmts[i].format == VK_FORMAT_B8G8R8A8_UNORM || fmts[i].format == VK_FORMAT_R8G8B8A8_UNORM) &&
            fmts[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            fmt = fmts[i];
            break;
        }
    free(fmts);

    uint32_t npm = 0;
    vkGetPhysicalDeviceSurfacePresentModesKHR(V.phys, V.surface, &npm, NULL);
    VkPresentModeKHR *pms = calloc(npm ? npm : 1, sizeof *pms);
    vkGetPhysicalDeviceSurfacePresentModesKHR(V.phys, V.surface, &npm, pms);
    VkPresentModeKHR mode = VK_PRESENT_MODE_FIFO_KHR;
    if (!V.cfg.vsync) {
        for (uint32_t i = 0; i < npm; i++)
            if (pms[i] == VK_PRESENT_MODE_IMMEDIATE_KHR) mode = pms[i];
        for (uint32_t i = 0; i < npm; i++)
            if (pms[i] == VK_PRESENT_MODE_MAILBOX_KHR) mode = pms[i];
    }
    free(pms);

    uint32_t count = caps.minImageCount + 1;
    if (caps.maxImageCount && count > caps.maxImageCount) count = caps.maxImageCount;
    if (count > MAX_SC) count = MAX_SC;
    VkSwapchainKHR old = V.swapchain;
    VkSwapchainCreateInfoKHR ci = {
        .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = V.surface,
        .minImageCount = count,
        .imageFormat = fmt.format,
        .imageColorSpace = fmt.colorSpace,
        .imageExtent = ext,
        .imageArrayLayers = 1,
        .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = caps.currentTransform,
        .compositeAlpha = (caps.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR)
                              ? VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
                              : (VkCompositeAlphaFlagBitsKHR)(caps.supportedCompositeAlpha &
                                                              -caps.supportedCompositeAlpha),
        .presentMode = mode,
        .clipped = VK_TRUE,
        .oldSwapchain = old,
    };
    VKCHECK(vkCreateSwapchainKHR(V.dev, &ci, NULL, &V.swapchain));
    if (old) vkDestroySwapchainKHR(V.dev, old, NULL);
    V.sc_fmt = fmt.format;
    V.sc_ext = ext;

    VkImage imgs[MAX_SC];
    V.sc_count = MAX_SC;
    VKCHECK(vkGetSwapchainImagesKHR(V.dev, V.swapchain, &V.sc_count, imgs));
    for (uint32_t i = 0; i < V.sc_count; i++) {
        VkImageViewCreateInfo vi = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = imgs[i],
                                    .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = fmt.format,
                                    .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
        VKCHECK(vkCreateImageView(V.dev, &vi, NULL, &V.sc_views[i]));
        GfxTex *t = &V.sc_tex[i];
        memset(t, 0, sizeof *t);
        t->img = imgs[i];
        t->vkfmt = fmt.format;
        t->rt = &V.sc_views[i];
        t->nrt = 1;
        t->w = (int)ext.width;
        t->h = (int)ext.height;
        t->d = t->levels = t->samples = 1;
        t->aspect = VK_IMAGE_ASPECT_COLOR_BIT;
        t->layout = VK_IMAGE_LAYOUT_UNDEFINED;
        VkSemaphoreCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VKCHECK(vkCreateSemaphore(V.dev, &si, NULL, &V.sc_done[i]));
    }
}

/* ---------------------------------------------------------------- init */

static void vk_window_hints(const GfxConfig *cfg) {
    (void)cfg;
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
}

static int vk_init(const GfxConfig *cfg, GLFWwindow *win) {
    memset(&V, 0, sizeof V);
    V.cfg = *cfg;
    V.win = win;
    create_instance();
    if (win) VKCHECK(glfwCreateWindowSurface(V.inst, win, NULL, &V.surface));
    if (!pick_device()) return 0;
    create_device();

    V.sc = shaderc_compiler_initialize();

    VkFormatProperties fp;
    vkGetPhysicalDeviceFormatProperties(V.phys, VK_FORMAT_R32G32B32A32_SFLOAT, &fp);
    V.float_linear = (fp.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT) &&
                     (fp.optimalTilingFeatures & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT);
    V.depth_fmt = VK_FORMAT_D32_SFLOAT;
    vkGetPhysicalDeviceFormatProperties(V.phys, V.depth_fmt, &fp);
    if (!(fp.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT))
        V.depth_fmt = VK_FORMAT_X8_D24_UNORM_PACK32;
    VkSampleCountFlags sc = V.props.limits.framebufferColorSampleCounts & V.props.limits.framebufferDepthSampleCounts;
    V.max_samples = 1;
    for (int s = 2; s <= 8; s *= 2)
        if (sc & (VkSampleCountFlags)s) V.max_samples = s;

    /* One layout for every program: binding 0 = uniform block, 1.. = samplers. */
    VkDescriptorSetLayoutBinding b[1 + GFX_MAX_TEX];
    for (int i = 0; i <= GFX_MAX_TEX; i++)
        b[i] = (VkDescriptorSetLayoutBinding){
            .binding = (uint32_t)i,
            .descriptorType = i ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT};
    VkDescriptorSetLayoutCreateInfo dli = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                                           .flags = VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR,
                                           .bindingCount = 1 + GFX_MAX_TEX, .pBindings = b};
    VKCHECK(vkCreateDescriptorSetLayout(V.dev, &dli, NULL, &V.dsl));
    VkPipelineLayoutCreateInfo pli = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                      .setLayoutCount = 1, .pSetLayouts = &V.dsl};
    VKCHECK(vkCreatePipelineLayout(V.dev, &pli, NULL, &V.layout));

    static const VkFilter filt[3] = {VK_FILTER_NEAREST, VK_FILTER_LINEAR, VK_FILTER_LINEAR};
    static const VkSamplerAddressMode wraps[2] = {VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                                                  VK_SAMPLER_ADDRESS_MODE_REPEAT};
    for (int f = 0; f < 3; f++)
        for (int w = 0; w < 2; w++) {
            VkSamplerCreateInfo si = {
                .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                .magFilter = filt[f], .minFilter = filt[f],
                .mipmapMode = f == GFX_MIPMAP ? VK_SAMPLER_MIPMAP_MODE_LINEAR : VK_SAMPLER_MIPMAP_MODE_NEAREST,
                .addressModeU = wraps[w], .addressModeV = wraps[w], .addressModeW = wraps[w],
                .maxLod = f == GFX_MIPMAP ? VK_LOD_CLAMP_NONE : 0.25f, /* GL: non-mip filters use level 0 */
            };
            VKCHECK(vkCreateSampler(V.dev, &si, NULL, &V.samplers[f][w]));
        }

    VkCommandPoolCreateInfo pi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                  .flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, .queueFamilyIndex = V.qfam};
    VKCHECK(vkCreateCommandPool(V.dev, &pi, NULL, &V.setup_pool));
    for (int i = 0; i < FRAMES; i++) {
        Frame *f = &V.fr[i];
        VKCHECK(vkCreateCommandPool(V.dev, &pi, NULL, &f->pool));
        VkCommandBufferAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                                          .commandPool = f->pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                                          .commandBufferCount = 1};
        VKCHECK(vkAllocateCommandBuffers(V.dev, &ai, &f->cmd));
        VkFenceCreateInfo fi = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT};
        VKCHECK(vkCreateFence(V.dev, &fi, NULL, &f->fence));
        VkSemaphoreCreateInfo si = {.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VKCHECK(vkCreateSemaphore(V.dev, &si, NULL, &f->acquired));
        f->ring.size = RING_BYTES;
        make_buffer(RING_BYTES,
                    VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
                        VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &f->ring.buf,
                    &f->ring.mem, (void **)&f->ring.map);
    }
    if (V.surface) create_swapchain();
    return 1;
}

static void destroy_pipelines(GfxProg *p) {
    for (int i = 0; i < p->npipes; i++) vkDestroyPipeline(V.dev, p->pipes[i].pipe, NULL);
    p->npipes = 0;
}

static void vk_shutdown(void) {
    if (!V.dev) return;
    flush_setup();
    vkDeviceWaitIdle(V.dev);
    destroy_swapchain_views();
    if (V.swapchain) vkDestroySwapchainKHR(V.dev, V.swapchain, NULL);
    for (int i = 0; i < FRAMES; i++) {
        Frame *f = &V.fr[i];
        vkDestroyBuffer(V.dev, f->ring.buf, NULL);
        vkFreeMemory(V.dev, f->ring.mem, NULL);
        vkDestroySemaphore(V.dev, f->acquired, NULL);
        vkDestroyFence(V.dev, f->fence, NULL);
        vkDestroyCommandPool(V.dev, f->pool, NULL);
    }
    vkDestroyCommandPool(V.dev, V.setup_pool, NULL);
    if (V.rb_buf) { vkDestroyBuffer(V.dev, V.rb_buf, NULL); vkFreeMemory(V.dev, V.rb_mem, NULL); }
    for (int f = 0; f < 3; f++)
        for (int w = 0; w < 2; w++) vkDestroySampler(V.dev, V.samplers[f][w], NULL);
    vkDestroyPipelineLayout(V.dev, V.layout, NULL);
    vkDestroyDescriptorSetLayout(V.dev, V.dsl, NULL);
    shaderc_compiler_release(V.sc);
    vkDestroyDevice(V.dev, NULL);
    if (V.surface) vkDestroySurfaceKHR(V.inst, V.surface, NULL);
    if (V.messenger) {
        PFN_vkDestroyDebugUtilsMessengerEXT f =
            (PFN_vkDestroyDebugUtilsMessengerEXT)vkGetInstanceProcAddr(V.inst, "vkDestroyDebugUtilsMessengerEXT");
        if (f) f(V.inst, V.messenger, NULL);
    }
    vkDestroyInstance(V.inst, NULL);
    memset(&V, 0, sizeof V);
}

static const char *vk_device_name(void) { return V.device; }
static int vk_is_nvidia(void) { return V.props.vendorID == 0x10DE; }
static int vk_float32_filterable(void) { return V.float_linear; }
static int vk_max_samples(void) { return V.max_samples; }
static int vk_flip_y(void) { return 1; }

/* ---------------------------------------------------------------- textures */

static VkFormat vk_format(GfxFormat f) {
    switch (f) {
    case GFX_R8: return VK_FORMAT_R8_UNORM;
    case GFX_RGBA8: return VK_FORMAT_R8G8B8A8_UNORM;
    case GFX_RGBA16F: return VK_FORMAT_R16G16B16A16_SFLOAT;
    case GFX_RGBA32F: return VK_FORMAT_R32G32B32A32_SFLOAT;
    case GFX_DEPTH: return V.depth_fmt;
    }
    return VK_FORMAT_UNDEFINED;
}

static size_t texel_bytes(GfxFormat f) {
    switch (f) {
    case GFX_R8: return 1;
    case GFX_RGBA8: return 4;
    case GFX_RGBA16F: return 8;
    case GFX_RGBA32F: return 16;
    case GFX_DEPTH: return 4;
    }
    return 4;
}

static VkImageView make_view(GfxTex *t, VkImageViewType type, uint32_t level, uint32_t nlevels, uint32_t layer,
                             VkImageUsageFlags usage) {
    VkImageViewUsageCreateInfo ui = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_USAGE_CREATE_INFO, .usage = usage};
    VkImageViewCreateInfo vi = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .pNext = usage ? &ui : NULL,
                                .image = t->img, .viewType = type, .format = t->vkfmt,
                                .subresourceRange = {t->aspect, level, nlevels, layer, 1}};
    VkImageView v;
    VKCHECK(vkCreateImageView(V.dev, &vi, NULL, &v));
    return v;
}

static GfxTex *vk_texture(GfxFormat fmt, int w, int h, int d, int mips, int samples) {
    GfxTex *t = calloc(1, sizeof *t);
    t->fmt = fmt;
    t->vkfmt = vk_format(fmt);
    t->w = w; t->h = h; t->d = d < 1 ? 1 : d;
    t->samples = samples < 1 ? 1 : samples;
    t->owned = 1;
    t->levels = 1;
    if (mips && t->d == 1 && t->samples == 1)
        for (int m = w > h ? w : h; m > 1; m >>= 1) t->levels++;
    int is_depth = fmt == GFX_DEPTH;
    t->aspect = is_depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT;
    int sampled = !is_depth && t->samples == 1;
    VkImageUsageFlags usage = is_depth ? VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
                                       : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    if (sampled)
        usage |= VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    VkImageCreateInfo ii = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .flags = t->d > 1 ? VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT : 0,
        .imageType = t->d > 1 ? VK_IMAGE_TYPE_3D : VK_IMAGE_TYPE_2D,
        .format = t->vkfmt,
        .extent = {(uint32_t)w, (uint32_t)h, (uint32_t)t->d},
        .mipLevels = (uint32_t)t->levels,
        .arrayLayers = 1,
        .samples = (VkSampleCountFlagBits)t->samples,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
    };
    VKCHECK(vkCreateImage(V.dev, &ii, NULL, &t->img));
    VkMemoryRequirements req;
    vkGetImageMemoryRequirements(V.dev, t->img, &req);
    t->mem = alloc_mem(req, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    VKCHECK(vkBindImageMemory(V.dev, t->img, t->mem, 0));

    if (sampled)
        t->view = make_view(t, t->d > 1 ? VK_IMAGE_VIEW_TYPE_3D : VK_IMAGE_VIEW_TYPE_2D, 0, (uint32_t)t->levels,
                            0, 0);
    t->nrt = t->d;
    t->rt = calloc((size_t)t->nrt, sizeof *t->rt);
    for (int z = 0; z < t->nrt; z++) /* 2D views of a 3D image may only be attachments */
        t->rt[z] = make_view(t, VK_IMAGE_VIEW_TYPE_2D, 0, 1, (uint32_t)z,
                             t->d > 1 ? VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT : 0);
    t->layout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (sampled) { /* start out zeroed, like Shadertoy buffers */
        VkCommandBuffer c = work_cmd();
        transition(c, t, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        VkClearColorValue zero = {{0, 0, 0, 0}};
        VkImageSubresourceRange r = {VK_IMAGE_ASPECT_COLOR_BIT, 0, VK_REMAINING_MIP_LEVELS, 0, 1};
        vkCmdClearColorImage(c, t->img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &zero, 1, &r);
    }
    return t;
}

static void vk_upload(GfxTex *t, const void *px) {
    VkCommandBuffer c = work_cmd();
    size_t size = (size_t)t->w * (size_t)t->h * (size_t)t->d * texel_bytes(t->fmt);
    VkBuffer buf;
    VkDeviceSize off;
    stage(px, size, &buf, &off);
    transition(c, t, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    VkBufferImageCopy r = {.bufferOffset = off,
                           .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
                           .imageExtent = {(uint32_t)t->w, (uint32_t)t->h, (uint32_t)t->d}};
    vkCmdCopyBufferToImage(c, buf, t->img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &r);
}

static void vk_gen_mips(GfxTex *t) {
    if (t->levels < 2) return;
    VkCommandBuffer c = work_cmd();
    transition(c, t, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    img_barrier(c, t, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, 0, 1);
    int w = t->w, h = t->h;
    for (int l = 1; l < t->levels; l++) {
        int nw = w > 1 ? w / 2 : 1, nh = h > 1 ? h / 2 : 1;
        VkImageBlit b = {
            .srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, (uint32_t)l - 1, 0, 1},
            .srcOffsets = {{0, 0, 0}, {w, h, 1}},
            .dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, (uint32_t)l, 0, 1},
            .dstOffsets = {{0, 0, 0}, {nw, nh, 1}},
        };
        vkCmdBlitImage(c, t->img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, t->img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                       1, &b, VK_FILTER_LINEAR);
        img_barrier(c, t, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, (uint32_t)l, 1);
        w = nw;
        h = nh;
    }
    t->layout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
}

static void vk_readback(GfxTex *t, void *dst) {
    VkCommandBuffer c = work_cmd();
    VkDeviceSize size = (VkDeviceSize)t->w * (VkDeviceSize)t->h * 4;
    if (size > V.rb_size) {
        if (V.rb_buf) {
            vkDeviceWaitIdle(V.dev);
            vkDestroyBuffer(V.dev, V.rb_buf, NULL);
            vkFreeMemory(V.dev, V.rb_mem, NULL);
        }
        make_buffer(size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT |
                        VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
                    &V.rb_buf, &V.rb_mem, &V.rb_map);
        V.rb_size = size;
    }
    transition(c, t, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    VkBufferImageCopy r = {.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
                           .imageExtent = {(uint32_t)t->w, (uint32_t)t->h, 1}};
    vkCmdCopyImageToBuffer(c, t->img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, V.rb_buf, 1, &r);
    VkMemoryBarrier mb = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
                          .dstAccessMask = VK_ACCESS_HOST_READ_BIT};
    vkCmdPipelineBarrier(c, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
    V.rb_dst = dst;
    V.rb_bytes = (size_t)size;
    if (!V.recording) {
        flush_setup();
        memcpy(dst, V.rb_map, V.rb_bytes);
        V.rb_dst = NULL;
    }
}

static void vk_wait_idle(void) {
    flush_setup();
    vkDeviceWaitIdle(V.dev);
}

static void vk_tex_free(GfxTex *t) {
    if (!t) return;
    vk_wait_idle();
    for (int i = 0; i < t->nrt; i++) vkDestroyImageView(V.dev, t->rt[i], NULL);
    free(t->rt);
    if (t->view) vkDestroyImageView(V.dev, t->view, NULL);
    vkDestroyImage(V.dev, t->img, NULL);
    vkFreeMemory(V.dev, t->mem, NULL);
    free(t);
}

/* ---------------------------------------------------------------- buffers & programs */

static GfxBuf *vk_buffer(const void *data, size_t size) {
    GfxBuf *b = calloc(1, sizeof *b);
    void *map;
    make_buffer(size, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &b->buf, &b->mem, &map);
    memcpy(map, data, size);
    vkUnmapMemory(V.dev, b->mem);
    return b;
}

static void vk_buf_free(GfxBuf *b) {
    if (!b) return;
    vk_wait_idle();
    vkDestroyBuffer(V.dev, b->buf, NULL);
    vkFreeMemory(V.dev, b->mem, NULL);
    free(b);
}

static VkShaderModule compile(const char *const *chunks, int n, int is_vs, const char *label) {
    const char *stage = is_vs ? "#define GFX_VS 1\n" : "#define GFX_FS 1\n";
    size_t len = strlen(PRELUDE) + strlen(stage);
    for (int i = 0; i < n; i++) len += strlen(chunks[i]);
    char *src = malloc(len + 1), *p = src;
    p += sprintf(p, "%s%s", PRELUDE, stage);
    for (int i = 0; i < n; i++) {
        size_t l = strlen(chunks[i]);
        memcpy(p, chunks[i], l);
        p += l;
    }
    *p = 0;
    shaderc_compile_options_t o = shaderc_compile_options_initialize();
    shaderc_compile_options_set_target_env(o, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_3);
    shaderc_compile_options_set_auto_map_locations(o, true);
    shaderc_compilation_result_t r = shaderc_compile_into_spv(
        V.sc, src, len, is_vs ? shaderc_vertex_shader : shaderc_fragment_shader, label, "main", o);
    shaderc_compile_options_release(o);
    free(src);
    VkShaderModule m = VK_NULL_HANDLE;
    if (shaderc_result_get_compilation_status(r) != shaderc_compilation_status_success) {
        fprintf(stderr, "[%s] compile error:\n%s\n", label, shaderc_result_get_error_message(r));
    } else {
        VkShaderModuleCreateInfo mi = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                                       .codeSize = shaderc_result_get_length(r),
                                       .pCode = (const uint32_t *)shaderc_result_get_bytes(r)};
        VKCHECK(vkCreateShaderModule(V.dev, &mi, NULL, &m));
    }
    shaderc_result_release(r);
    return m;
}

static GfxProg *vk_program(const GfxProgDesc *d) {
    VkShaderModule vs = compile(d->vs, d->nvs, 1, d->label);
    VkShaderModule fs = vs ? compile(d->fs, d->nfs, 0, d->label) : VK_NULL_HANDLE;
    if (!vs || !fs) {
        if (vs) vkDestroyShaderModule(V.dev, vs, NULL);
        return NULL;
    }
    GfxProg *p = calloc(1, sizeof *p);
    snprintf(p->label, sizeof p->label, "%s", d->label);
    p->vs = vs;
    p->fs = fs;
    p->vtx = d->vtx;
    return p;
}

static void vk_prog_free(GfxProg *p) {
    if (!p) return;
    vk_wait_idle();
    destroy_pipelines(p);
    vkDestroyShaderModule(V.dev, p->vs, NULL);
    vkDestroyShaderModule(V.dev, p->fs, NULL);
    V.bound = VK_NULL_HANDLE;
    free(p);
}

static VkPipeline get_pipeline(GfxProg *p, const GfxDraw *d) {
    GfxTex *rt = V.pass.msaa ? V.pass.msaa : V.pass_color;
    PipeEntry key = {.color = rt->vkfmt, .has_depth = V.pass.depth != NULL, .samples = rt->samples,
                     .depth = d->depth, .cull = d->cull, .blend = d->blend_add};
    for (int i = 0; i < p->npipes; i++) {
        PipeEntry *e = &p->pipes[i];
        if (e->color == key.color && e->has_depth == key.has_depth && e->samples == key.samples &&
            e->depth == key.depth && e->cull == key.cull && e->blend == key.blend)
            return e->pipe;
    }
    if (p->npipes == MAX_PIPES) destroy_pipelines(p); /* never expected; keeps the cache bounded */

    VkPipelineShaderStageCreateInfo st[2] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT,
         .module = p->vs, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
         .module = p->fs, .pName = "main"},
    };
    VkVertexInputBindingDescription vb[2] = {
        {0, GFX_VTX_STRIDE, VK_VERTEX_INPUT_RATE_VERTEX},
        {1, GFX_INST_STRIDE, VK_VERTEX_INPUT_RATE_INSTANCE},
    };
    VkVertexInputAttributeDescription va[6] = {
        {0, 0, VK_FORMAT_R32G32B32_SFLOAT, 0},     {1, 0, VK_FORMAT_R32G32B32_SFLOAT, 12},
        {2, 0, VK_FORMAT_R32G32_SFLOAT, 24},       {3, 1, VK_FORMAT_R32G32B32A32_SFLOAT, 0},
        {4, 1, VK_FORMAT_R32G32B32A32_SFLOAT, 16}, {5, 1, VK_FORMAT_R32G32B32A32_SFLOAT, 32},
    };
    VkPipelineVertexInputStateCreateInfo vi = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = p->vtx == GFX_VTX_NONE ? 0 : p->vtx == GFX_VTX_MESH ? 1 : 2,
        .pVertexBindingDescriptions = vb,
        .vertexAttributeDescriptionCount = p->vtx == GFX_VTX_NONE ? 0 : p->vtx == GFX_VTX_MESH ? 3 : 6,
        .pVertexAttributeDescriptions = va,
    };
    VkPipelineInputAssemblyStateCreateInfo ia = {.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                                                 .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
    VkPipelineViewportStateCreateInfo vp = {.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                                            .viewportCount = 1, .scissorCount = 1};
    /* Rows are stored bottom-up like GL, which mirrors winding relative to
     * Vulkan's top-down framebuffer convention: GL's CCW is Vulkan's CW. */
    VkPipelineRasterizationStateCreateInfo rs = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL,
        .cullMode = key.cull ? VK_CULL_MODE_BACK_BIT : VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_CLOCKWISE,
        .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo ms = {.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                                               .rasterizationSamples = (VkSampleCountFlagBits)key.samples};
    VkPipelineDepthStencilStateCreateInfo ds = {.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
                                                .depthTestEnable = (VkBool32)key.depth,
                                                .depthWriteEnable = (VkBool32)key.depth,
                                                .depthCompareOp = VK_COMPARE_OP_LESS};
    VkPipelineColorBlendAttachmentState ba = {
        .blendEnable = (VkBool32)key.blend,
        .srcColorBlendFactor = VK_BLEND_FACTOR_ONE, .dstColorBlendFactor = VK_BLEND_FACTOR_ONE,
        .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE, .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .alphaBlendOp = VK_BLEND_OP_ADD,
        .colorWriteMask = 0xF,
    };
    VkPipelineColorBlendStateCreateInfo cb = {.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                                              .attachmentCount = 1, .pAttachments = &ba};
    VkDynamicState dyn[2] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dy = {.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                                           .dynamicStateCount = 2, .pDynamicStates = dyn};
    VkPipelineRenderingCreateInfo ri = {.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
                                        .colorAttachmentCount = 1, .pColorAttachmentFormats = &key.color,
                                        .depthAttachmentFormat = key.has_depth ? V.depth_fmt : VK_FORMAT_UNDEFINED};
    VkGraphicsPipelineCreateInfo gi = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .pNext = &ri,
        .stageCount = 2, .pStages = st, .pVertexInputState = &vi, .pInputAssemblyState = &ia,
        .pViewportState = &vp, .pRasterizationState = &rs, .pMultisampleState = &ms, .pDepthStencilState = &ds,
        .pColorBlendState = &cb, .pDynamicState = &dy, .layout = V.layout,
    };
    VKCHECK(vkCreateGraphicsPipelines(V.dev, VK_NULL_HANDLE, 1, &gi, NULL, &key.pipe));
    p->pipes[p->npipes++] = key;
    return key.pipe;
}

/* ---------------------------------------------------------------- frame */

static void vk_begin_frame(void) {
    flush_setup();
    Frame *f = &V.fr[V.cur];
    VKCHECK(vkWaitForFences(V.dev, 1, &f->fence, VK_TRUE, UINT64_MAX));
    VKCHECK(vkResetFences(V.dev, 1, &f->fence));
    VKCHECK(vkResetCommandPool(V.dev, f->pool, 0));
    VkCommandBufferBeginInfo bi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                                   .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
    VKCHECK(vkBeginCommandBuffer(f->cmd, &bi));
    f->ring.off = 0;
    V.recording = 1;
    V.acquired = 0;
    V.bound = VK_NULL_HANDLE;
    if (V.surface) { /* Wayland never reports a resize as out-of-date */
        int w, h;
        glfwGetFramebufferSize(V.win, &w, &h);
        if ((uint32_t)w != V.sc_ext.width || (uint32_t)h != V.sc_ext.height) V.sc_dirty = 1;
    }
}

static int acquire(void) {
    if (V.acquired) return 1;
    if (!V.surface) return 0;
    for (int tries = 0; tries < 3; tries++) {
        if (V.sc_dirty || !V.swapchain) create_swapchain();
        if (!V.swapchain) return 0;
        VkResult r = vkAcquireNextImageKHR(V.dev, V.swapchain, UINT64_MAX, V.fr[V.cur].acquired, VK_NULL_HANDLE,
                                           &V.sc_index);
        if (r == VK_SUCCESS || r == VK_SUBOPTIMAL_KHR) {
            if (r == VK_SUBOPTIMAL_KHR) V.sc_dirty = 1;
            V.acquired = 1;
            return 1;
        }
        if (r != VK_ERROR_OUT_OF_DATE_KHR) VKCHECK(r);
        V.sc_dirty = 1;
    }
    return 0;
}

static void begin_rendering(void) {
    VkCommandBuffer c = V.fr[V.cur].cmd;
    GfxPass *p = &V.pass;
    GfxTex *col = V.pass_color;
    VkRenderingAttachmentInfo ca = {
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = p->msaa ? p->msaa->rt[0] : col->rt[col->d > 1 ? p->layer : 0],
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = V.pending_clear ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
    };
    memcpy(ca.clearValue.color.float32, p->clear_color, sizeof p->clear_color);
    if (p->msaa) {
        ca.resolveMode = VK_RESOLVE_MODE_AVERAGE_BIT;
        ca.resolveImageView = col->rt[0];
        ca.resolveImageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    }
    VkRenderingAttachmentInfo da = {
        .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = p->depth ? p->depth->rt[0] : VK_NULL_HANDLE,
        .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = V.pending_clear ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue.depthStencil = {1.0f, 0},
    };
    VkRenderingInfo ri = {
        .sType = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = {{0, 0}, {(uint32_t)V.pass_w, (uint32_t)V.pass_h}},
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &ca,
        .pDepthAttachment = p->depth ? &da : NULL,
    };
    vkCmdBeginRendering(c, &ri);
    VkViewport vp = {0, 0, (float)V.pass_w, (float)V.pass_h, 0, 1};
    VkRect2D sc = {{0, 0}, {(uint32_t)V.pass_w, (uint32_t)V.pass_h}};
    vkCmdSetViewport(c, 0, 1, &vp);
    vkCmdSetScissor(c, 0, 1, &sc);
    V.rendering = 1;
    V.pending_clear = 0;
}

static void end_rendering(void) {
    if (!V.rendering) return;
    vkCmdEndRendering(V.fr[V.cur].cmd);
    V.rendering = 0;
}

static void vk_begin_pass(const GfxPass *p) {
    VkCommandBuffer c = V.fr[V.cur].cmd;
    V.pass = *p;
    V.pass_skip = 0;
    V.rendering = 0;
    V.pending_clear = p->clear;
    if (!p->color) {
        if (!acquire()) {
            V.pass_skip = 1;
            V.pass_w = V.pass_h = 1;
            return;
        }
        V.pass_color = &V.sc_tex[V.sc_index];
        V.pass_color->layout = VK_IMAGE_LAYOUT_UNDEFINED; /* contents are always redrawn */
        transition(c, V.pass_color, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    } else {
        V.pass_color = p->color;
        GfxTex *rt = p->msaa ? p->msaa : p->color;
        /* 3D targets: one barrier before slice 0 covers the whole volume, so
         * the slices of one update can render without serialising. */
        if (rt->d == 1 || p->layer == 0 || rt->layout != VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
            transition(c, rt, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
        if (p->msaa) transition(c, p->color, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
        if (p->depth) transition(c, p->depth, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL);
    }
    V.pass_w = V.pass_color->w;
    V.pass_h = V.pass_color->h;
}

static void vk_pass_size(int *w, int *h) { *w = V.pass_w; *h = V.pass_h; }

static void vk_draw(const GfxDraw *d) {
    if (V.pass_skip) return;
    if (d->prog->vtx == GFX_VTX_MESH_INST && d->ninst <= 0) return;
    VkCommandBuffer c = V.fr[V.cur].cmd;
    Ring *ring = &V.fr[V.cur].ring;
    for (int i = 0; i < GFX_MAX_TEX; i++) {
        GfxTex *t = d->tex[i];
        if (t && t->layout != VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
            end_rendering();
            transition(c, t, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        }
    }
    if (!V.rendering) begin_rendering();
    VkPipeline pipe = get_pipeline(d->prog, d);
    if (pipe != V.bound) {
        vkCmdBindPipeline(c, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);
        V.bound = pipe;
    }

    VkWriteDescriptorSet w[1 + GFX_MAX_TEX];
    VkDescriptorBufferInfo bi;
    VkDescriptorImageInfo ii[GFX_MAX_TEX];
    uint32_t n = 0;
    if (d->ubo_size > 0) {
        VkDeviceSize off = ring_alloc(ring, (VkDeviceSize)d->ubo_size, V.props.limits.minUniformBufferOffsetAlignment);
        memcpy(ring->map + off, d->ubo, (size_t)d->ubo_size);
        bi = (VkDescriptorBufferInfo){ring->buf, off, (VkDeviceSize)d->ubo_size};
        w[n++] = (VkWriteDescriptorSet){.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstBinding = 0,
                                        .descriptorCount = 1,
                                        .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pBufferInfo = &bi};
    }
    for (int i = 0; i < GFX_MAX_TEX; i++) {
        GfxTex *t = d->tex[i];
        if (!t) continue;
        int filt = d->filter[i];
        if (filt == GFX_MIPMAP && t->levels < 2) filt = GFX_LINEAR;
        ii[i] = (VkDescriptorImageInfo){V.samplers[filt][d->wrap[i]], t->view,
                                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        w[n++] = (VkWriteDescriptorSet){.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                                        .dstBinding = (uint32_t)(1 + i), .descriptorCount = 1,
                                        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                                        .pImageInfo = &ii[i]};
    }
    if (n) V.push_desc(c, VK_PIPELINE_BIND_POINT_GRAPHICS, V.layout, 0, n, w);

    uint32_t ninst = 1;
    if (d->vbuf) {
        VkDeviceSize zero = 0;
        vkCmdBindVertexBuffers(c, 0, 1, &d->vbuf->buf, &zero);
        if (d->prog->vtx == GFX_VTX_MESH_INST) {
            size_t bytes = (size_t)d->ninst * GFX_INST_STRIDE;
            VkDeviceSize off = ring_alloc(ring, bytes, 16);
            memcpy(ring->map + off, d->inst, bytes);
            vkCmdBindVertexBuffers(c, 1, 1, &ring->buf, &off);
            ninst = (uint32_t)d->ninst;
        }
    }
    vkCmdDraw(c, (uint32_t)d->count, ninst, (uint32_t)d->first, 0);
}

static void vk_end_pass(void) {
    if (V.pass_skip) return;
    if (V.pending_clear && !V.rendering) begin_rendering();
    end_rendering();
}

static void vk_end_frame(void) {
    Frame *f = &V.fr[V.cur];
    if (V.acquired) transition(f->cmd, &V.sc_tex[V.sc_index], VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
    VKCHECK(vkEndCommandBuffer(f->cmd));
    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo si = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = V.acquired ? 1u : 0u,
        .pWaitSemaphores = &f->acquired,
        .pWaitDstStageMask = &wait_stage,
        .commandBufferCount = 1,
        .pCommandBuffers = &f->cmd,
        .signalSemaphoreCount = V.acquired ? 1u : 0u,
        .pSignalSemaphores = &V.sc_done[V.sc_index],
    };
    VKCHECK(vkQueueSubmit(V.queue, 1, &si, f->fence));
    if (V.acquired) {
        VkPresentInfoKHR pi = {.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, .waitSemaphoreCount = 1,
                               .pWaitSemaphores = &V.sc_done[V.sc_index], .swapchainCount = 1,
                               .pSwapchains = &V.swapchain, .pImageIndices = &V.sc_index};
        VkResult r = vkQueuePresentKHR(V.queue, &pi);
        if (r == VK_ERROR_OUT_OF_DATE_KHR || r == VK_SUBOPTIMAL_KHR) V.sc_dirty = 1;
        else VKCHECK(r);
    }
    if (V.rb_dst) {
        VKCHECK(vkWaitForFences(V.dev, 1, &f->fence, VK_TRUE, UINT64_MAX));
        memcpy(V.rb_dst, V.rb_map, V.rb_bytes);
        V.rb_dst = NULL;
    }
    V.recording = 0;
    V.acquired = 0;
    V.cur = (V.cur + 1) % FRAMES;
}

const GfxBackend gfx_vk_backend = {
    "Vulkan",
    vk_window_hints, vk_init, vk_shutdown, vk_device_name, vk_is_nvidia,
    vk_float32_filterable, vk_max_samples, vk_flip_y,
    vk_texture, vk_upload, vk_gen_mips, vk_readback, vk_tex_free,
    vk_buffer, vk_buf_free,
    vk_program, vk_prog_free,
    vk_begin_frame, vk_begin_pass, vk_pass_size, vk_draw, vk_end_pass, vk_end_frame, vk_wait_idle,
};
