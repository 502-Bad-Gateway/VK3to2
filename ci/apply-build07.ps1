$ErrorActionPreference = 'Stop'

# Build 07 layers the first semantic repair on Build 06. Build 05/06 proved that
# the dominant Win7 failure is a legacy framebuffer with exactly one missing
# final depth/stencil attachment. Build 07 appends a proxy-owned dummy depth
# image/view, creates a render-pass-compatible shadow pass whose dummy depth
# load/store semantics are DONT_CARE, and redirects beginRenderPass to that
# shadow pass. The older incomplete-framebuffer guard remains as a fail-closed
# fallback for cases that cannot be repaired safely (for example enormous
# depth-only 32768x32768 targets).
& .\ci\apply-build06.ps1

$sourcePath = 'dist\vk3to2_build06.cpp'
$outPath = 'dist\vk3to2_build07.cpp'
$script:src = Get-Content -Raw -LiteralPath $sourcePath

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:src.Contains($old)) {
        throw "Build 07 patch anchor not found: $old"
    }
    $script:src = $script:src.Replace($old, $new)
}

# Runtime controls: full audit stays ON by default, but can now be disabled for
# representative performance checks without changing DLLs.
Replace-Required @'
static bool g_guard_incomplete_framebuffers = false;
'@ @'
static bool g_guard_incomplete_framebuffers = false;
static bool g_audit_enabled = true;
static bool g_repair_null_depth = false;
static std::uint32_t g_repair_max_dimension = 8192;
'@

# Minimal Vulkan ABI needed for proxy-owned depth images and memory.
Replace-Required @'
using VkImageView = std::uint64_t;
'@ @'
using VkImageView = std::uint64_t;
using VkImage = std::uint64_t;
using VkDeviceMemory = std::uint64_t;
using VkDeviceSize = std::uint64_t;
'@

Replace-Required @'
struct VkRenderPassBeginInfoMini {
    std::uint32_t sType;
    const void* pNext;
    VkRenderPass renderPass;
    VkFramebuffer framebuffer;
    VkRect2DMini renderArea;
    std::uint32_t clearValueCount;
    const void* pClearValues;
};
'@ @'
struct VkRenderPassBeginInfoMini {
    std::uint32_t sType;
    const void* pNext;
    VkRenderPass renderPass;
    VkFramebuffer framebuffer;
    VkRect2DMini renderArea;
    std::uint32_t clearValueCount;
    const void* pClearValues;
};

struct VkExtent3DMini {
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t depth;
};

struct VkImageCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    std::uint32_t imageType;
    std::uint32_t format;
    VkExtent3DMini extent;
    std::uint32_t mipLevels;
    std::uint32_t arrayLayers;
    std::uint32_t samples;
    std::uint32_t tiling;
    std::uint32_t usage;
    std::uint32_t sharingMode;
    std::uint32_t queueFamilyIndexCount;
    const std::uint32_t* pQueueFamilyIndices;
    std::uint32_t initialLayout;
};

struct VkComponentMappingMini {
    std::uint32_t r;
    std::uint32_t g;
    std::uint32_t b;
    std::uint32_t a;
};

struct VkImageSubresourceRangeMini {
    std::uint32_t aspectMask;
    std::uint32_t baseMipLevel;
    std::uint32_t levelCount;
    std::uint32_t baseArrayLayer;
    std::uint32_t layerCount;
};

struct VkImageViewCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    VkImage image;
    std::uint32_t viewType;
    std::uint32_t format;
    VkComponentMappingMini components;
    VkImageSubresourceRangeMini subresourceRange;
};

struct VkMemoryRequirementsMini {
    VkDeviceSize size;
    VkDeviceSize alignment;
    std::uint32_t memoryTypeBits;
};

struct VkMemoryAllocateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    VkDeviceSize allocationSize;
    std::uint32_t memoryTypeIndex;
};

struct VkMemoryTypeMini {
    std::uint32_t propertyFlags;
    std::uint32_t heapIndex;
};

struct VkMemoryHeapMini {
    VkDeviceSize size;
    std::uint32_t flags;
};

struct VkPhysicalDeviceMemoryPropertiesMini {
    std::uint32_t memoryTypeCount;
    VkMemoryTypeMini memoryTypes[32];
    std::uint32_t memoryHeapCount;
    VkMemoryHeapMini memoryHeaps[16];
};
'@

Replace-Required @'
using PFN_vkDestroyImageView = void (WINAPI*)(VkDevice, VkImageView, const void*);
'@ @'
using PFN_vkDestroyImageView = void (WINAPI*)(VkDevice, VkImageView, const void*);
using PFN_vkGetPhysicalDeviceMemoryProperties = void (WINAPI*)(VkPhysicalDevice, VkPhysicalDeviceMemoryPropertiesMini*);
using PFN_vkCreateImage = VkResult (WINAPI*)(VkDevice, const VkImageCreateInfoMini*, const void*, VkImage*);
using PFN_vkDestroyImage = void (WINAPI*)(VkDevice, VkImage, const void*);
using PFN_vkGetImageMemoryRequirements = void (WINAPI*)(VkDevice, VkImage, VkMemoryRequirementsMini*);
using PFN_vkAllocateMemory = VkResult (WINAPI*)(VkDevice, const VkMemoryAllocateInfoMini*, const void*, VkDeviceMemory*);
using PFN_vkFreeMemory = void (WINAPI*)(VkDevice, VkDeviceMemory, const void*);
using PFN_vkBindImageMemory = VkResult (WINAPI*)(VkDevice, VkImage, VkDeviceMemory, VkDeviceSize);
using PFN_vkCreateImageView = VkResult (WINAPI*)(VkDevice, const VkImageViewCreateInfoMini*, const void*, VkImageView*);
'@

Replace-Required @'
static PFN_vkDestroyImageView g_destroy_image_view = nullptr;
'@ @'
static PFN_vkDestroyImageView g_destroy_image_view = nullptr;
static PFN_vkGetPhysicalDeviceMemoryProperties g_get_physical_device_memory_properties = nullptr;
static PFN_vkCreateImage g_create_image = nullptr;
static PFN_vkDestroyImage g_destroy_image = nullptr;
static PFN_vkGetImageMemoryRequirements g_get_image_memory_requirements = nullptr;
static PFN_vkAllocateMemory g_allocate_memory = nullptr;
static PFN_vkFreeMemory g_free_memory = nullptr;
static PFN_vkBindImageMemory g_bind_image_memory = nullptr;
static PFN_vkCreateImageView g_create_image_view = nullptr;
'@

# Extend the audit records with the metadata/lifetime needed by the repair.
Replace-Required @'
struct RenderPassAuditRecord {
    bool used;
    VkRenderPass renderPass;
    std::uint32_t attachmentCount;
};
'@ @'
struct RenderPassAuditRecord {
    bool used;
    VkRenderPass renderPass;
    VkRenderPass shadowRenderPass;
    const void* shadowAllocator;
    std::uint32_t attachmentCount;
    std::uint32_t subpassCount;
    std::uint32_t depthAttachmentIndex;
    std::uint32_t depthFormat;
    std::uint32_t depthSamples;
};
'@

Replace-Required @'
struct FramebufferAuditRecord {
    bool used;
    bool incomplete;
    VkFramebuffer framebuffer;
    VkRenderPass renderPass;
    std::uint32_t attachmentCount;
    std::uint32_t actualAttachmentCount;
    std::uint32_t expectedAttachmentCount;
    VkImageView attachments[9];
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t layers;
};
'@ @'
struct FramebufferAuditRecord {
    bool used;
    bool incomplete;
    bool repairedNullDepth;
    VkFramebuffer framebuffer;
    VkRenderPass renderPass;
    VkRenderPass originalRenderPass;
    VkRenderPass shadowRenderPass;
    std::uint32_t attachmentCount;
    std::uint32_t actualAttachmentCount;
    std::uint32_t expectedAttachmentCount;
    VkImageView attachments[9];
    VkImage dummyDepthImage;
    VkImageView dummyDepthView;
    VkDeviceMemory dummyDepthMemory;
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t layers;
};
'@

Replace-Required @'
static RenderPassAuditRecord g_render_pass_records[512]{};
static FramebufferAuditRecord g_framebuffer_records[2048]{};
static ActiveRenderPassAuditRecord g_active_render_pass_records[128]{};
'@ @'
static RenderPassAuditRecord g_render_pass_records[512]{};
static FramebufferAuditRecord g_framebuffer_records[2048]{};
static ActiveRenderPassAuditRecord g_active_render_pass_records[128]{};
static VkPhysicalDeviceMemoryPropertiesMini g_memory_properties{};
static bool g_memory_properties_valid = false;
'@

# Filtering at LogFormat entry avoids both string formatting and file I/O when
# audit=0, rather than merely hiding the output after paying the diagnostic cost.
$logFilter = @'
static bool IsAlwaysLogMessage(const char* text) {
    if (!text) return false;
    return strncmp(text, "ERROR", 5) == 0 ||
           strncmp(text, "NVIDIA_EXCEPTION", 16) == 0 ||
           strncmp(text, "REPAIR_ERROR", 12) == 0 ||
           strncmp(text, "VK3to2 Build", 12) == 0 ||
           strncmp(text, "Real loader:", 12) == 0 ||
           strncmp(text, "OPTIONS", 7) == 0;
}

'@
Replace-Required 'static void LogLine(const char* text) {' ($logFilter + @'
static void LogLine(const char* text) {
    if (!g_audit_enabled && !IsAlwaysLogMessage(text)) return;
'@)

Replace-Required @'
static void LogFormat(const char* format, ...) {
    char message[1200]{};
'@ @'
static void LogFormat(const char* format, ...) {
    if (!g_audit_enabled && !IsAlwaysLogMessage(format)) return;
    char message[1200]{};
'@

# INI controls.
Replace-Required @'
    g_guard_incomplete_framebuffers =
        GetPrivateProfileIntW(L"patches", L"guard_incomplete_framebuffers", 0, ini_path) != 0;
'@ @'
    g_guard_incomplete_framebuffers =
        GetPrivateProfileIntW(L"patches", L"guard_incomplete_framebuffers", 0, ini_path) != 0;
    g_audit_enabled = GetPrivateProfileIntW(L"trace", L"audit", 1, ini_path) != 0;
    g_repair_null_depth = GetPrivateProfileIntW(L"patches", L"repair_null_depth", 0, ini_path) != 0;
    const int repair_limit = GetPrivateProfileIntW(L"patches", L"repair_max_dimension", 8192, ini_path);
    g_repair_max_dimension = repair_limit > 0 ? static_cast<std::uint32_t>(repair_limit) : 8192u;
'@

# Initialize repair-only driver functions from the real loader after device
# creation. Also cache the physical-device memory table used for allocations.
$deviceHelpers = @'
static void ResolveRepairDeviceFunctions(VkDevice device) {
    if (!device || !g_real_gdpa) return;
    if (!g_create_image) g_create_image = reinterpret_cast<PFN_vkCreateImage>(g_real_gdpa(device, "vkCreateImage"));
    if (!g_destroy_image) g_destroy_image = reinterpret_cast<PFN_vkDestroyImage>(g_real_gdpa(device, "vkDestroyImage"));
    if (!g_get_image_memory_requirements) {
        g_get_image_memory_requirements = reinterpret_cast<PFN_vkGetImageMemoryRequirements>(
            g_real_gdpa(device, "vkGetImageMemoryRequirements"));
    }
    if (!g_allocate_memory) g_allocate_memory = reinterpret_cast<PFN_vkAllocateMemory>(g_real_gdpa(device, "vkAllocateMemory"));
    if (!g_free_memory) g_free_memory = reinterpret_cast<PFN_vkFreeMemory>(g_real_gdpa(device, "vkFreeMemory"));
    if (!g_bind_image_memory) g_bind_image_memory = reinterpret_cast<PFN_vkBindImageMemory>(g_real_gdpa(device, "vkBindImageMemory"));
    if (!g_create_image_view) g_create_image_view = reinterpret_cast<PFN_vkCreateImageView>(g_real_gdpa(device, "vkCreateImageView"));
    if (!g_destroy_image_view) g_destroy_image_view = reinterpret_cast<PFN_vkDestroyImageView>(g_real_gdpa(device, "vkDestroyImageView"));
}

'@
Replace-Required 'static VkResult WINAPI Audit_vkCreateDevice(' ($deviceHelpers + 'static VkResult WINAPI Audit_vkCreateDevice(')

Replace-Required @'
    const VkResult result = g_create_instance ? g_create_instance(info, allocator, instance) : -3;
    LogFormat("CALL vkCreateInstance RETURN result=%d", result);
'@ @'
    const VkResult result = g_create_instance ? g_create_instance(info, allocator, instance) : -3;
    if (result == 0 && instance && *instance && g_real_gipa) {
        g_get_physical_device_memory_properties =
            reinterpret_cast<PFN_vkGetPhysicalDeviceMemoryProperties>(
                g_real_gipa(*instance, "vkGetPhysicalDeviceMemoryProperties"));
    }
    LogFormat("CALL vkCreateInstance RETURN result=%d", result);
'@

Replace-Required @'
    const VkResult result = g_create_device ? g_create_device(physicalDevice, info, allocator, device) : -3;
    LogFormat("CALL vkCreateDevice RETURN result=%d", result);
'@ @'
    const VkResult result = g_create_device ? g_create_device(physicalDevice, info, allocator, device) : -3;
    if (result == 0 && device && *device) {
        ResolveRepairDeviceFunctions(*device);
        if (g_get_physical_device_memory_properties) {
            g_get_physical_device_memory_properties(physicalDevice, &g_memory_properties);
            g_memory_properties_valid = g_memory_properties.memoryTypeCount > 0 &&
                                        g_memory_properties.memoryTypeCount <= 32;
        }
    }
    LogFormat("CALL vkCreateDevice RETURN result=%d", result);
'@

# Preserve enough render-pass structure to prove that the sole missing final
# attachment is the depth/stencil attachment.
Replace-Required @'
        record->used = true;
        record->renderPass = renderPass;
        record->attachmentCount = info->attachmentCount;
'@ @'
        record->used = true;
        record->renderPass = renderPass;
        record->shadowRenderPass = 0;
        record->shadowAllocator = nullptr;
        record->attachmentCount = info->attachmentCount;
        record->subpassCount = info->subpassCount;
        record->depthAttachmentIndex = 0xffffffffu;
        record->depthFormat = 0;
        record->depthSamples = 0;
        if (info->subpassCount == 1 && info->pSubpasses &&
            info->pSubpasses[0].pDepthStencilAttachment) {
            const std::uint32_t depth_index = info->pSubpasses[0].pDepthStencilAttachment->attachment;
            if (depth_index != 0xffffffffu && depth_index < info->attachmentCount && info->pAttachments) {
                record->depthAttachmentIndex = depth_index;
                record->depthFormat = info->pAttachments[depth_index].format;
                record->depthSamples = info->pAttachments[depth_index].samples;
            }
        }
'@

Replace-Required @'
        record->incomplete = false;
        const bool concrete = (info->flags & 0x1u) == 0;
'@ @'
        record->incomplete = false;
        record->repairedNullDepth = false;
        record->originalRenderPass = 0;
        record->shadowRenderPass = 0;
        record->dummyDepthImage = 0;
        record->dummyDepthView = 0;
        record->dummyDepthMemory = 0;
        const bool concrete = (info->flags & 0x1u) == 0;
'@

# Shadow render pass: attachment format/sample/reference structure stays the
# same, preserving render-pass compatibility with pipelines, while only the
# proxy-owned null-depth attachment changes to DONT_CARE + UNDEFINED initial
# layout so it does not pretend to contain guest depth data.
$repairHelpers = @'
struct DummyDepthResource {
    VkImage image;
    VkImageView view;
    VkDeviceMemory memory;
};

static std::uint32_t DepthAspectMaskForFormat(std::uint32_t format) {
    switch (format) {
    case 124: // D16_UNORM
    case 125: // X8_D24_UNORM_PACK32
    case 126: // D32_SFLOAT
        return 0x2u;
    case 127: // S8_UINT
        return 0x4u;
    case 128: // D16_UNORM_S8_UINT
    case 129: // D24_UNORM_S8_UINT
    case 130: // D32_SFLOAT_S8_UINT
        return 0x2u | 0x4u;
    default:
        return 0;
    }
}

static std::uint32_t ChooseMemoryType(std::uint32_t bits) {
    if (g_memory_properties_valid) {
        for (std::uint32_t i = 0; i < g_memory_properties.memoryTypeCount; ++i) {
            if ((bits & (1u << i)) && (g_memory_properties.memoryTypes[i].propertyFlags & 0x1u)) {
                return i;
            }
        }
        for (std::uint32_t i = 0; i < g_memory_properties.memoryTypeCount; ++i) {
            if (bits & (1u << i)) return i;
        }
    }
    for (std::uint32_t i = 0; i < 32; ++i) {
        if (bits & (1u << i)) return i;
    }
    return 0xffffffffu;
}

static void DestroyDummyDepthResource(VkDevice device, DummyDepthResource resource) {
    if (resource.view && g_destroy_image_view) g_destroy_image_view(device, resource.view, nullptr);
    if (resource.image && g_destroy_image) g_destroy_image(device, resource.image, nullptr);
    if (resource.memory && g_free_memory) g_free_memory(device, resource.memory, nullptr);
}

static bool CreateDummyDepthResource(VkDevice device, std::uint32_t format, std::uint32_t samples,
                                     std::uint32_t width, std::uint32_t height, std::uint32_t layers,
                                     DummyDepthResource* out) {
    if (!out || !device || !width || !height || !layers || !samples ||
        !g_create_image || !g_destroy_image || !g_get_image_memory_requirements ||
        !g_allocate_memory || !g_free_memory || !g_bind_image_memory ||
        !g_create_image_view || !g_destroy_image_view) {
        return false;
    }
    const std::uint32_t aspect = DepthAspectMaskForFormat(format);
    if (!aspect) return false;

    DummyDepthResource resource{};
    VkImageCreateInfoMini image_info{};
    image_info.sType = 14; // VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
    image_info.imageType = 1; // VK_IMAGE_TYPE_2D
    image_info.format = format;
    image_info.extent = {width, height, 1};
    image_info.mipLevels = 1;
    image_info.arrayLayers = layers;
    image_info.samples = samples;
    image_info.tiling = 0; // VK_IMAGE_TILING_OPTIMAL
    image_info.usage = 0x20u; // VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
    image_info.sharingMode = 0; // VK_SHARING_MODE_EXCLUSIVE
    image_info.initialLayout = 0; // VK_IMAGE_LAYOUT_UNDEFINED

    VkResult result = g_create_image(device, &image_info, nullptr, &resource.image);
    if (result != 0 || !resource.image) {
        LogFormat("REPAIR_ERROR null-depth vkCreateImage result=%d fmt=%u size=%ux%u layers=%u samples=0x%x",
                  result, format, width, height, layers, samples);
        return false;
    }

    VkMemoryRequirementsMini requirements{};
    g_get_image_memory_requirements(device, resource.image, &requirements);
    const std::uint32_t memory_type = ChooseMemoryType(requirements.memoryTypeBits);
    if (memory_type == 0xffffffffu) {
        LogFormat("REPAIR_ERROR null-depth no memory type bits=0x%x", requirements.memoryTypeBits);
        DestroyDummyDepthResource(device, resource);
        return false;
    }

    VkMemoryAllocateInfoMini allocation{};
    allocation.sType = 5; // VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
    allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = memory_type;
    result = g_allocate_memory(device, &allocation, nullptr, &resource.memory);
    if (result != 0 || !resource.memory) {
        LogFormat("REPAIR_ERROR null-depth vkAllocateMemory result=%d bytes=%llu type=%u",
                  result, static_cast<unsigned long long>(requirements.size), memory_type);
        DestroyDummyDepthResource(device, resource);
        return false;
    }

    result = g_bind_image_memory(device, resource.image, resource.memory, 0);
    if (result != 0) {
        LogFormat("REPAIR_ERROR null-depth vkBindImageMemory result=%d", result);
        DestroyDummyDepthResource(device, resource);
        return false;
    }

    VkImageViewCreateInfoMini view_info{};
    view_info.sType = 15; // VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
    view_info.image = resource.image;
    view_info.viewType = layers > 1 ? 5u : 1u; // 2D_ARRAY : 2D
    view_info.format = format;
    view_info.subresourceRange.aspectMask = aspect;
    view_info.subresourceRange.baseMipLevel = 0;
    view_info.subresourceRange.levelCount = 1;
    view_info.subresourceRange.baseArrayLayer = 0;
    view_info.subresourceRange.layerCount = layers;
    result = g_create_image_view(device, &view_info, nullptr, &resource.view);
    if (result != 0 || !resource.view) {
        LogFormat("REPAIR_ERROR null-depth vkCreateImageView result=%d fmt=%u aspect=0x%x",
                  result, format, aspect);
        DestroyDummyDepthResource(device, resource);
        return false;
    }

    *out = resource;
    return true;
}

static VkRenderPass CreateNullDepthShadowRenderPass(VkDevice device,
                                                     const VkRenderPassCreateInfoMini* info,
                                                     const void* allocator) {
    if (!g_repair_null_depth || !device || !info || info->pNext ||
        info->attachmentCount == 0 || info->attachmentCount > 9 ||
        info->subpassCount != 1 || !info->pAttachments || !info->pSubpasses ||
        !info->pSubpasses[0].pDepthStencilAttachment || !g_create_render_pass) {
        return 0;
    }
    const std::uint32_t depth_index = info->pSubpasses[0].pDepthStencilAttachment->attachment;
    if (depth_index == 0xffffffffu || depth_index >= info->attachmentCount) return 0;

    VkAttachmentDescriptionMini attachments[9]{};
    for (std::uint32_t i = 0; i < info->attachmentCount; ++i) attachments[i] = info->pAttachments[i];
    attachments[depth_index].loadOp = 2; // DONT_CARE
    attachments[depth_index].storeOp = 1; // DONT_CARE
    attachments[depth_index].stencilLoadOp = 2;
    attachments[depth_index].stencilStoreOp = 1;
    attachments[depth_index].initialLayout = 0; // UNDEFINED

    VkRenderPassCreateInfoMini shadow_info = *info;
    shadow_info.pAttachments = attachments;
    VkRenderPass shadow = 0;
    const VkResult result = g_create_render_pass(device, &shadow_info, allocator, &shadow);
    if (result != 0) {
        LogFormat("REPAIR_ERROR shadow renderPass create result=%d depthIndex=%u", result, depth_index);
        return 0;
    }
    return shadow;
}

static void RecordShadowRenderPass(VkRenderPass original, VkRenderPass shadow, const void* allocator) {
    if (!original || !shadow) return;
    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& record : g_render_pass_records) {
        if (record.used && record.renderPass == original) {
            record.shadowRenderPass = shadow;
            record.shadowAllocator = allocator;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

'@
Replace-Required 'static VkResult WINAPI Audit_vkCreateRenderPass(' ($repairHelpers + 'static VkResult WINAPI Audit_vkCreateRenderPass(')

Replace-Required @'
    if (result == 0 && handle && info) RecordRenderPassContract(handle, info);
'@ @'
    if (result == 0 && handle && info) {
        RecordRenderPassContract(handle, info);
        const VkRenderPass shadow = CreateNullDepthShadowRenderPass(device, info, allocator);
        if (shadow) {
            RecordShadowRenderPass(handle, shadow, allocator);
            LogFormat("REPAIR shadowRenderPass original=0x%llx shadow=0x%llx attachments=%u",
                      static_cast<unsigned long long>(handle),
                      static_cast<unsigned long long>(shadow), info->attachmentCount);
        }
    }
'@

# Build07 framebuffer wrappers. Repair any N -> N-1 concrete mismatch where the
# missing final attachment is the sole depth/stencil attachment and dimensions
# are beneath the configured safety cap. All other mismatches fall back to the
# proven Build06 guard.
$framebufferRepair = @'
struct RepairCandidate {
    bool valid;
    VkRenderPass originalRenderPass;
    VkRenderPass shadowRenderPass;
    std::uint32_t expectedAttachments;
    std::uint32_t depthFormat;
    std::uint32_t depthSamples;
};

static RepairCandidate FindNullDepthRepairCandidate(const VkFramebufferCreateInfoMini* info) {
    RepairCandidate candidate{};
    if (!g_repair_null_depth || !info || (info->flags & 0x1u) != 0 ||
        !info->pAttachments || info->width == 0 || info->height == 0 || info->layers == 0 ||
        info->width > g_repair_max_dimension || info->height > g_repair_max_dimension) {
        return candidate;
    }
    AcquireSRWLockShared(&g_render_audit_lock);
    for (const auto& rp : g_render_pass_records) {
        if (!rp.used || rp.renderPass != info->renderPass) continue;
        if (rp.shadowRenderPass && rp.subpassCount == 1 && rp.attachmentCount == info->attachmentCount + 1 &&
            rp.depthAttachmentIndex == info->attachmentCount && rp.depthFormat != 0 && rp.depthSamples != 0) {
            candidate.valid = true;
            candidate.originalRenderPass = rp.renderPass;
            candidate.shadowRenderPass = rp.shadowRenderPass;
            candidate.expectedAttachments = rp.attachmentCount;
            candidate.depthFormat = rp.depthFormat;
            candidate.depthSamples = rp.depthSamples;
        }
        break;
    }
    ReleaseSRWLockShared(&g_render_audit_lock);
    return candidate;
}

static void MarkFramebufferNullDepthRepair(VkFramebuffer framebuffer, VkRenderPass original,
                                           VkRenderPass shadow, DummyDepthResource dummy) {
    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& record : g_framebuffer_records) {
        if (record.used && record.framebuffer == framebuffer) {
            record.repairedNullDepth = true;
            record.originalRenderPass = original;
            record.shadowRenderPass = shadow;
            record.dummyDepthImage = dummy.image;
            record.dummyDepthView = dummy.view;
            record.dummyDepthMemory = dummy.memory;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

static DummyDepthResource TakeFramebufferDummyDepth(VkFramebuffer framebuffer) {
    DummyDepthResource resource{};
    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& record : g_framebuffer_records) {
        if (record.used && record.framebuffer == framebuffer && record.repairedNullDepth) {
            resource.image = record.dummyDepthImage;
            resource.view = record.dummyDepthView;
            resource.memory = record.dummyDepthMemory;
            record.dummyDepthImage = 0;
            record.dummyDepthView = 0;
            record.dummyDepthMemory = 0;
            record.repairedNullDepth = false;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
    return resource;
}

static VkResult WINAPI Build07_vkCreateFramebuffer(VkDevice device, const VkFramebufferCreateInfoMini* info,
                                                    const void* allocator, VkFramebuffer* outFramebuffer) {
    MarkApi("vkCreateFramebuffer");
    const RepairCandidate candidate = FindNullDepthRepairCandidate(info);
    if (!candidate.valid) {
        if (g_repair_null_depth && info && (info->flags & 0x1u) == 0 &&
            (info->width > g_repair_max_dimension || info->height > g_repair_max_dimension)) {
            LogFormat("REPAIR SKIP null-depth dimension %ux%u cap=%u rp=0x%llx actual=%u",
                      info->width, info->height, g_repair_max_dimension,
                      static_cast<unsigned long long>(info->renderPass), info->attachmentCount);
        }
        return Audit_vkCreateFramebuffer(device, info, allocator, outFramebuffer);
    }

    DummyDepthResource dummy{};
    if (!CreateDummyDepthResource(device, candidate.depthFormat, candidate.depthSamples,
                                  info->width, info->height, info->layers, &dummy)) {
        return Audit_vkCreateFramebuffer(device, info, allocator, outFramebuffer);
    }

    VkImageView attachments[9]{};
    for (std::uint32_t i = 0; i < info->attachmentCount && i < 8; ++i) attachments[i] = info->pAttachments[i];
    attachments[info->attachmentCount] = dummy.view;

    VkFramebufferCreateInfoMini forwarded = *info;
    forwarded.renderPass = candidate.shadowRenderPass;
    forwarded.attachmentCount = candidate.expectedAttachments;
    forwarded.pAttachments = attachments;

    const LONG id = InterlockedIncrement(&g_create_framebuffer_calls);
    const VkResult result = g_create_framebuffer ? g_create_framebuffer(device, &forwarded, allocator, outFramebuffer) : -3;
    const VkFramebuffer handle = (result == 0 && outFramebuffer) ? *outFramebuffer : 0;
    if (result != 0 || !handle) {
        LogFormat("REPAIR_ERROR null-depth framebuffer create result=%d originalRp=0x%llx shadowRp=0x%llx",
                  result, static_cast<unsigned long long>(candidate.originalRenderPass),
                  static_cast<unsigned long long>(candidate.shadowRenderPass));
        DestroyDummyDepthResource(device, dummy);
        return result;
    }

    RecordFramebuffer(handle, &forwarded);
    MarkFramebufferNullDepthRepair(handle, candidate.originalRenderPass, candidate.shadowRenderPass, dummy);
    LogFormat("REPAIR NULL_DEPTH #%ld fb=0x%llx originalRp=0x%llx shadowRp=0x%llx actual=%u repaired=%u fmt=%u samples=0x%x size=%ux%ux%u dummyView=0x%llx",
              id, static_cast<unsigned long long>(handle),
              static_cast<unsigned long long>(candidate.originalRenderPass),
              static_cast<unsigned long long>(candidate.shadowRenderPass),
              info->attachmentCount, candidate.expectedAttachments, candidate.depthFormat,
              candidate.depthSamples, info->width, info->height, info->layers,
              static_cast<unsigned long long>(dummy.view));
    return result;
}

static void WINAPI Build07_vkDestroyFramebuffer(VkDevice device, VkFramebuffer framebuffer, const void* allocator) {
    MarkApi("vkDestroyFramebuffer");
    const LONG id = InterlockedIncrement(&g_destroy_framebuffer_calls);
    const bool active = IsFramebufferActive(framebuffer);
    LogFormat("RPSTATE DESTROY_FB #%ld handle=0x%llx active=%d", id,
              static_cast<unsigned long long>(framebuffer), active ? 1 : 0);
    if (active) LogFormat("RPSTATE WARNING destroy framebuffer while active handle=0x%llx",
                          static_cast<unsigned long long>(framebuffer));
    const DummyDepthResource dummy = TakeFramebufferDummyDepth(framebuffer);
    if (g_destroy_framebuffer) g_destroy_framebuffer(device, framebuffer, allocator);
    DestroyDummyDepthResource(device, dummy);
    ForgetFramebuffer(framebuffer);
}

static void WINAPI Build07_vkDestroyRenderPass(VkDevice device, VkRenderPass renderPass, const void* allocator) {
    MarkApi("vkDestroyRenderPass");
    const LONG id = InterlockedIncrement(&g_destroy_render_pass_calls);
    const bool active = IsRenderPassActive(renderPass);
    VkRenderPass shadow = 0;
    const void* shadow_allocator = nullptr;
    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& record : g_render_pass_records) {
        if (record.used && record.renderPass == renderPass) {
            shadow = record.shadowRenderPass;
            shadow_allocator = record.shadowAllocator;
            record.shadowRenderPass = 0;
            record.shadowAllocator = nullptr;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
    LogFormat("RPSTATE DESTROY_RP #%ld handle=0x%llx active=%d shadow=0x%llx", id,
              static_cast<unsigned long long>(renderPass), active ? 1 : 0,
              static_cast<unsigned long long>(shadow));
    if (active) LogFormat("RPSTATE WARNING destroy renderPass while active handle=0x%llx",
                          static_cast<unsigned long long>(renderPass));
    if (g_destroy_render_pass) {
        g_destroy_render_pass(device, renderPass, allocator);
        if (shadow) g_destroy_render_pass(device, shadow, shadow_allocator);
    }
    ForgetRenderPassContract(renderPass);
}

'@
Replace-Required 'static VkResult WINAPI Audit_vkSetDebugUtilsObjectNameEXT' ($framebufferRepair + 'static VkResult WINAPI Audit_vkSetDebugUtilsObjectNameEXT')

# Redirect render-pass begin to the compatible shadow pass for repaired
# framebuffers. The framebuffer itself was created against that shadow pass.
$beginRedirect = @'
static bool PrepareRepairedBeginInfo(const void* beginInfoVoid, VkRenderPassBeginInfoMini* out) {
    if (!beginInfoVoid || !out) return false;
    const auto* beginInfo = reinterpret_cast<const VkRenderPassBeginInfoMini*>(beginInfoVoid);
    VkRenderPass shadow = 0;
    VkRenderPass original = 0;
    AcquireSRWLockShared(&g_render_audit_lock);
    for (const auto& fb : g_framebuffer_records) {
        if (fb.used && fb.framebuffer == beginInfo->framebuffer && fb.repairedNullDepth) {
            shadow = fb.shadowRenderPass;
            original = fb.originalRenderPass;
            break;
        }
    }
    ReleaseSRWLockShared(&g_render_audit_lock);
    if (!shadow) return false;
    *out = *beginInfo;
    out->renderPass = shadow;
    LogFormat("REPAIR BEGIN_REDIRECT cmd framebuffer=0x%llx originalRp=0x%llx shadowRp=0x%llx incomingRp=0x%llx",
              static_cast<unsigned long long>(beginInfo->framebuffer),
              static_cast<unsigned long long>(original),
              static_cast<unsigned long long>(shadow),
              static_cast<unsigned long long>(beginInfo->renderPass));
    return true;
}

'@
Replace-Required 'static bool GuardIncompleteFramebufferBegin(' ($beginRedirect + 'static bool GuardIncompleteFramebufferBegin(')

Replace-Required @'
    const char* audit_path = g_lower_renderpass2 && safe_to_lower ? "begin2-lowered" : "begin2-native";
    RecordRenderPassBegin(commandBuffer, beginInfo, audit_path);
    if (GuardIncompleteFramebufferBegin(commandBuffer, beginInfo, audit_path)) return;
'@ @'
    const char* audit_path = g_lower_renderpass2 && safe_to_lower ? "begin2-lowered" : "begin2-native";
    VkRenderPassBeginInfoMini repaired_begin{};
    const void* forwarded_begin = PrepareRepairedBeginInfo(beginInfo, &repaired_begin) ? &repaired_begin : beginInfo;
    RecordRenderPassBegin(commandBuffer, forwarded_begin, audit_path);
    if (GuardIncompleteFramebufferBegin(commandBuffer, forwarded_begin, audit_path)) return;
'@

Replace-Required @'
        LogFormat("LOWER vkCmdBeginRenderPass2 -> vkCmdBeginRenderPass #%ld contents=%u", id, contents);
        g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
'@ @'
        LogFormat("LOWER vkCmdBeginRenderPass2 -> vkCmdBeginRenderPass #%ld contents=%u", id, contents);
        g_cmd_begin_render_pass(commandBuffer, forwarded_begin, contents);
'@

Replace-Required @'
    if (g_cmd_begin_render_pass2) g_cmd_begin_render_pass2(commandBuffer, beginInfo, subpassBeginInfo);
'@ @'
    if (g_cmd_begin_render_pass2) g_cmd_begin_render_pass2(commandBuffer, forwarded_begin, subpassBeginInfo);
'@

Replace-Required @'
    RecordRenderPassBegin(commandBuffer, beginInfo, "begin-legacy");
    if (GuardIncompleteFramebufferBegin(commandBuffer, beginInfo, "begin-legacy")) return;
    if (g_cmd_begin_render_pass) g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
'@ @'
    VkRenderPassBeginInfoMini repaired_begin{};
    const void* forwarded_begin = PrepareRepairedBeginInfo(beginInfo, &repaired_begin) ? &repaired_begin : beginInfo;
    RecordRenderPassBegin(commandBuffer, forwarded_begin, "begin-legacy");
    if (GuardIncompleteFramebufferBegin(commandBuffer, forwarded_begin, "begin-legacy")) return;
    if (g_cmd_begin_render_pass) g_cmd_begin_render_pass(commandBuffer, forwarded_begin, contents);
'@

# Route object creation/destruction through the Build07 lifetime-aware wrappers.
Replace-Required 'return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCreateFramebuffer);' 'return reinterpret_cast<PFN_vkVoidFunction>(&Build07_vkCreateFramebuffer);'
Replace-Required 'return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkDestroyFramebuffer);' 'return reinterpret_cast<PFN_vkVoidFunction>(&Build07_vkDestroyFramebuffer);'
Replace-Required 'return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkDestroyRenderPass);' 'return reinterpret_cast<PFN_vkVoidFunction>(&Build07_vkDestroyRenderPass);'

Replace-Required @'
        LogLine("VK3to2 Build 06 initialized: incomplete framebuffer guard");
        LogFormat("OPTIONS patches.guard_incomplete_framebuffers=%d",
                  g_guard_incomplete_framebuffers ? 1 : 0);
'@ @'
        LogLine("VK3to2 Build 07 initialized: null depth attachment repair");
        LogFormat("OPTIONS trace.audit=%d trace.sampled_calls=%d trace.nvidia_exceptions=%d",
                  g_audit_enabled ? 1 : 0, g_trace_sampled_calls ? 1 : 0,
                  g_trace_nvidia_exceptions ? 1 : 0);
        LogFormat("OPTIONS patches.guard_incomplete_framebuffers=%d patches.repair_null_depth=%d repair_max_dimension=%u",
                  g_guard_incomplete_framebuffers ? 1 : 0, g_repair_null_depth ? 1 : 0,
                  g_repair_max_dimension);
'@

New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
Set-Content -LiteralPath $outPath -Value $script:src -Encoding UTF8
Write-Host "Build 07 patch generated $outPath"
