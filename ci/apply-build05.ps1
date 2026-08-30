$ErrorActionPreference = 'Stop'

# Build 05 layers structural render-pass/framebuffer auditing on Build 04, but
# disables all behavior-changing workarounds in the packaged INI. The purpose is
# to identify the invalid/driver-sensitive state that makes even legacy
# vkCmdEndRenderPass fault on NVIDIA 472.12.
& .\ci\apply-build04.ps1

$sourcePath = 'dist\vk3to2_build04.cpp'
$outPath = 'dist\vk3to2_build05.cpp'
$script:src = Get-Content -Raw -LiteralPath $sourcePath

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:src.Contains($old)) {
        throw "Build 05 patch anchor not found: $old"
    }
    $script:src = $script:src.Replace($old, $new)
}

Replace-Required @'
// VK3to2 keeps a deliberately small Vulkan ABI surface and does not depend on
// the Vulkan SDK. Build 04 lowers the RenderPass2 command path used by the frozen
// Windows 7 shadPS4 scheduler to legacy render-pass commands when no pNext-only
// semantics are present. Other workarounds remain independently configurable.
'@ @'
// VK3to2 keeps a deliberately small Vulkan ABI surface and does not depend on
// the Vulkan SDK. Build 05 audits the complete legacy render-pass/framebuffer
// state and object lifetime around the NVIDIA crash. The packaged INI enables no
// behavior-changing workaround, so this build is a structural diagnostic.
'@

Replace-Required @'
using VkPipelineLayout = std::uint64_t;
'@ @'
using VkPipelineLayout = std::uint64_t;
using VkRenderPass = std::uint64_t;
using VkFramebuffer = std::uint64_t;
using VkImageView = std::uint64_t;
'@

Replace-Required @'
struct VkSubpassEndInfoMini {
    std::uint32_t sType;
    const void* pNext;
};
'@ @'
struct VkSubpassEndInfoMini {
    std::uint32_t sType;
    const void* pNext;
};

struct VkAttachmentDescriptionMini {
    std::uint32_t flags;
    std::uint32_t format;
    std::uint32_t samples;
    std::uint32_t loadOp;
    std::uint32_t storeOp;
    std::uint32_t stencilLoadOp;
    std::uint32_t stencilStoreOp;
    std::uint32_t initialLayout;
    std::uint32_t finalLayout;
};

struct VkAttachmentReferenceMini {
    std::uint32_t attachment;
    std::uint32_t layout;
};

struct VkSubpassDescriptionMini {
    std::uint32_t flags;
    std::uint32_t pipelineBindPoint;
    std::uint32_t inputAttachmentCount;
    const VkAttachmentReferenceMini* pInputAttachments;
    std::uint32_t colorAttachmentCount;
    const VkAttachmentReferenceMini* pColorAttachments;
    const VkAttachmentReferenceMini* pResolveAttachments;
    const VkAttachmentReferenceMini* pDepthStencilAttachment;
    std::uint32_t preserveAttachmentCount;
    const std::uint32_t* pPreserveAttachments;
};

struct VkRenderPassCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    std::uint32_t attachmentCount;
    const VkAttachmentDescriptionMini* pAttachments;
    std::uint32_t subpassCount;
    const VkSubpassDescriptionMini* pSubpasses;
    std::uint32_t dependencyCount;
    const void* pDependencies;
};

struct VkFramebufferCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    VkRenderPass renderPass;
    std::uint32_t attachmentCount;
    const VkImageView* pAttachments;
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t layers;
};

struct VkOffset2DMini {
    std::int32_t x;
    std::int32_t y;
};

struct VkExtent2DMini {
    std::uint32_t width;
    std::uint32_t height;
};

struct VkRect2DMini {
    VkOffset2DMini offset;
    VkExtent2DMini extent;
};

struct VkRenderPassBeginInfoMini {
    std::uint32_t sType;
    const void* pNext;
    VkRenderPass renderPass;
    VkFramebuffer framebuffer;
    VkRect2DMini renderArea;
    std::uint32_t clearValueCount;
    const void* pClearValues;
};
'@

Replace-Required @'
using PFN_vkCmdEndRenderPass2 = void (WINAPI*)(VkCommandBuffer, const VkSubpassEndInfoMini*);
'@ @'
using PFN_vkCmdEndRenderPass2 = void (WINAPI*)(VkCommandBuffer, const VkSubpassEndInfoMini*);
using PFN_vkCreateRenderPass = VkResult (WINAPI*)(VkDevice, const VkRenderPassCreateInfoMini*, const void*, VkRenderPass*);
using PFN_vkDestroyRenderPass = void (WINAPI*)(VkDevice, VkRenderPass, const void*);
using PFN_vkCreateFramebuffer = VkResult (WINAPI*)(VkDevice, const VkFramebufferCreateInfoMini*, const void*, VkFramebuffer*);
using PFN_vkDestroyFramebuffer = void (WINAPI*)(VkDevice, VkFramebuffer, const void*);
using PFN_vkDestroyImageView = void (WINAPI*)(VkDevice, VkImageView, const void*);
'@

Replace-Required @'
static PFN_vkCmdEndRenderPass2 g_cmd_end_render_pass2 = nullptr;
'@ @'
static PFN_vkCmdEndRenderPass2 g_cmd_end_render_pass2 = nullptr;
static PFN_vkCreateRenderPass g_create_render_pass = nullptr;
static PFN_vkDestroyRenderPass g_destroy_render_pass = nullptr;
static PFN_vkCreateFramebuffer g_create_framebuffer = nullptr;
static PFN_vkDestroyFramebuffer g_destroy_framebuffer = nullptr;
static PFN_vkDestroyImageView g_destroy_image_view = nullptr;
'@

Replace-Required @'
static volatile LONG g_end_render_pass2_calls = 0;
'@ @'
static volatile LONG g_end_render_pass2_calls = 0;
static volatile LONG g_create_render_pass_calls = 0;
static volatile LONG g_create_framebuffer_calls = 0;
static volatile LONG g_destroy_render_pass_calls = 0;
static volatile LONG g_destroy_framebuffer_calls = 0;
static volatile LONG g_destroy_image_view_calls = 0;
'@

Replace-Required @'
static void BuildSiblingPath(const wchar_t* filename, wchar_t* output, DWORD capacity) {
'@ @'
struct FramebufferAuditRecord {
    bool used;
    VkFramebuffer framebuffer;
    VkRenderPass renderPass;
    std::uint32_t attachmentCount;
    VkImageView attachments[9];
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t layers;
};

struct ActiveRenderPassAuditRecord {
    bool used;
    VkCommandBuffer commandBuffer;
    VkRenderPass renderPass;
    VkFramebuffer framebuffer;
};

static SRWLOCK g_render_audit_lock = SRWLOCK_INIT;
static FramebufferAuditRecord g_framebuffer_records[2048]{};
static ActiveRenderPassAuditRecord g_active_render_pass_records[128]{};

static void BuildSiblingPath(const wchar_t* filename, wchar_t* output, DWORD capacity) {
'@

$helpers = @'
static void RecordFramebuffer(VkFramebuffer framebuffer, const VkFramebufferCreateInfoMini* info) {
    if (!framebuffer || !info) return;
    AcquireSRWLockExclusive(&g_render_audit_lock);
    FramebufferAuditRecord* record = nullptr;
    for (auto& candidate : g_framebuffer_records) {
        if (candidate.used && candidate.framebuffer == framebuffer) {
            record = &candidate;
            break;
        }
        if (!record && !candidate.used) record = &candidate;
    }
    if (record) {
        record->used = true;
        record->framebuffer = framebuffer;
        record->renderPass = info->renderPass;
        record->attachmentCount = info->attachmentCount > 9 ? 9 : info->attachmentCount;
        record->width = info->width;
        record->height = info->height;
        record->layers = info->layers;
        for (std::uint32_t i = 0; i < 9; ++i) record->attachments[i] = 0;
        if (info->pAttachments) {
            for (std::uint32_t i = 0; i < record->attachmentCount; ++i) {
                record->attachments[i] = info->pAttachments[i];
            }
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

static void ForgetFramebuffer(VkFramebuffer framebuffer) {
    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& record : g_framebuffer_records) {
        if (record.used && record.framebuffer == framebuffer) {
            record.used = false;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

static void RecordRenderPassBegin(VkCommandBuffer commandBuffer, const void* beginInfoVoid,
                                  const char* path) {
    const auto* beginInfo = reinterpret_cast<const VkRenderPassBeginInfoMini*>(beginInfoVoid);
    if (!beginInfo) {
        LogFormat("RPSTATE BEGIN path=%s cmd=%p beginInfo=<null>", path, commandBuffer);
        return;
    }

    LogFormat("RPSTATE BEGIN path=%s cmd=%p rp=0x%llx fb=0x%llx area=%d,%d %ux%u clears=%u pNext=%p",
              path, commandBuffer,
              static_cast<unsigned long long>(beginInfo->renderPass),
              static_cast<unsigned long long>(beginInfo->framebuffer),
              beginInfo->renderArea.offset.x, beginInfo->renderArea.offset.y,
              beginInfo->renderArea.extent.width, beginInfo->renderArea.extent.height,
              beginInfo->clearValueCount, beginInfo->pNext);

    AcquireSRWLockExclusive(&g_render_audit_lock);
    ActiveRenderPassAuditRecord* active = nullptr;
    for (auto& candidate : g_active_render_pass_records) {
        if (candidate.used && candidate.commandBuffer == commandBuffer) {
            active = &candidate;
            break;
        }
        if (!active && !candidate.used) active = &candidate;
    }
    if (active) {
        active->used = true;
        active->commandBuffer = commandBuffer;
        active->renderPass = beginInfo->renderPass;
        active->framebuffer = beginInfo->framebuffer;
    }

    for (const auto& fb : g_framebuffer_records) {
        if (!fb.used || fb.framebuffer != beginInfo->framebuffer) continue;
        LogFormat("RPSTATE FB fb=0x%llx rp=0x%llx size=%ux%ux%u attachments=%u views=[0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx]",
                  static_cast<unsigned long long>(fb.framebuffer),
                  static_cast<unsigned long long>(fb.renderPass),
                  fb.width, fb.height, fb.layers, fb.attachmentCount,
                  static_cast<unsigned long long>(fb.attachments[0]),
                  static_cast<unsigned long long>(fb.attachments[1]),
                  static_cast<unsigned long long>(fb.attachments[2]),
                  static_cast<unsigned long long>(fb.attachments[3]),
                  static_cast<unsigned long long>(fb.attachments[4]),
                  static_cast<unsigned long long>(fb.attachments[5]),
                  static_cast<unsigned long long>(fb.attachments[6]),
                  static_cast<unsigned long long>(fb.attachments[7]),
                  static_cast<unsigned long long>(fb.attachments[8]));
        break;
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

static void RecordRenderPassEndBefore(VkCommandBuffer commandBuffer, const char* path) {
    AcquireSRWLockShared(&g_render_audit_lock);
    bool found = false;
    for (const auto& active : g_active_render_pass_records) {
        if (active.used && active.commandBuffer == commandBuffer) {
            LogFormat("RPSTATE END_ENTER path=%s cmd=%p rp=0x%llx fb=0x%llx",
                      path, commandBuffer,
                      static_cast<unsigned long long>(active.renderPass),
                      static_cast<unsigned long long>(active.framebuffer));
            found = true;
            break;
        }
    }
    ReleaseSRWLockShared(&g_render_audit_lock);
    if (!found) LogFormat("RPSTATE END_ENTER path=%s cmd=%p active=<none>", path, commandBuffer);
}

static void RecordRenderPassEndSuccess(VkCommandBuffer commandBuffer, const char* path) {
    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& active : g_active_render_pass_records) {
        if (active.used && active.commandBuffer == commandBuffer) {
            active.used = false;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
    LogFormat("RPSTATE END_RETURN path=%s cmd=%p", path, commandBuffer);
}

static bool IsFramebufferActive(VkFramebuffer framebuffer) {
    bool active_now = false;
    AcquireSRWLockShared(&g_render_audit_lock);
    for (const auto& active : g_active_render_pass_records) {
        if (active.used && active.framebuffer == framebuffer) {
            active_now = true;
            break;
        }
    }
    ReleaseSRWLockShared(&g_render_audit_lock);
    return active_now;
}

static bool IsRenderPassActive(VkRenderPass renderPass) {
    bool active_now = false;
    AcquireSRWLockShared(&g_render_audit_lock);
    for (const auto& active : g_active_render_pass_records) {
        if (active.used && active.renderPass == renderPass) {
            active_now = true;
            break;
        }
    }
    ReleaseSRWLockShared(&g_render_audit_lock);
    return active_now;
}

static bool IsImageViewInActiveFramebuffer(VkImageView view) {
    bool active_now = false;
    AcquireSRWLockShared(&g_render_audit_lock);
    for (const auto& active : g_active_render_pass_records) {
        if (!active.used) continue;
        for (const auto& fb : g_framebuffer_records) {
            if (!fb.used || fb.framebuffer != active.framebuffer) continue;
            for (std::uint32_t i = 0; i < fb.attachmentCount; ++i) {
                if (fb.attachments[i] == view) {
                    active_now = true;
                    break;
                }
            }
            if (active_now) break;
        }
        if (active_now) break;
    }
    ReleaseSRWLockShared(&g_render_audit_lock);
    return active_now;
}

'@
Replace-Required 'static bool SampleCall' ($helpers + 'static bool SampleCall')

$objectWrappers = @'
static VkResult WINAPI Audit_vkCreateRenderPass(VkDevice device, const VkRenderPassCreateInfoMini* info,
                                                 const void* allocator, VkRenderPass* outRenderPass) {
    MarkApi("vkCreateRenderPass");
    const LONG id = InterlockedIncrement(&g_create_render_pass_calls);
    const VkResult result = g_create_render_pass ? g_create_render_pass(device, info, allocator, outRenderPass) : -3;
    const VkRenderPass handle = (result == 0 && outRenderPass) ? *outRenderPass : 0;
    LogFormat("RPSTATE CREATE_RP #%ld result=%d handle=0x%llx attachments=%u subpasses=%u deps=%u pNext=%p",
              id, result, static_cast<unsigned long long>(handle),
              info ? info->attachmentCount : 0, info ? info->subpassCount : 0,
              info ? info->dependencyCount : 0, info ? info->pNext : nullptr);
    if (info && info->pAttachments) {
        const std::uint32_t count = info->attachmentCount > 9 ? 9 : info->attachmentCount;
        for (std::uint32_t i = 0; i < count; ++i) {
            const auto& a = info->pAttachments[i];
            LogFormat("RPSTATE RP_ATTACHMENT rp=0x%llx i=%u fmt=%u samples=0x%x load=%u store=%u sload=%u sstore=%u initial=%u final=%u",
                      static_cast<unsigned long long>(handle), i, a.format, a.samples,
                      a.loadOp, a.storeOp, a.stencilLoadOp, a.stencilStoreOp,
                      a.initialLayout, a.finalLayout);
        }
    }
    if (info && info->pSubpasses && info->subpassCount) {
        const auto& s = info->pSubpasses[0];
        LogFormat("RPSTATE RP_SUBPASS rp=0x%llx colors=%u inputs=%u preserves=%u depthAtt=%u depthLayout=%u",
                  static_cast<unsigned long long>(handle), s.colorAttachmentCount,
                  s.inputAttachmentCount, s.preserveAttachmentCount,
                  s.pDepthStencilAttachment ? s.pDepthStencilAttachment->attachment : 0xffffffffu,
                  s.pDepthStencilAttachment ? s.pDepthStencilAttachment->layout : 0);
        if (s.pColorAttachments) {
            const std::uint32_t count = s.colorAttachmentCount > 8 ? 8 : s.colorAttachmentCount;
            for (std::uint32_t i = 0; i < count; ++i) {
                LogFormat("RPSTATE RP_COLOR_REF rp=0x%llx slot=%u attachment=%u layout=%u",
                          static_cast<unsigned long long>(handle), i,
                          s.pColorAttachments[i].attachment, s.pColorAttachments[i].layout);
            }
        }
    }
    return result;
}

static void WINAPI Audit_vkDestroyRenderPass(VkDevice device, VkRenderPass renderPass, const void* allocator) {
    MarkApi("vkDestroyRenderPass");
    const LONG id = InterlockedIncrement(&g_destroy_render_pass_calls);
    const bool active = IsRenderPassActive(renderPass);
    LogFormat("RPSTATE DESTROY_RP #%ld handle=0x%llx active=%d", id,
              static_cast<unsigned long long>(renderPass), active ? 1 : 0);
    if (active) LogFormat("RPSTATE WARNING destroy renderPass while active handle=0x%llx",
                          static_cast<unsigned long long>(renderPass));
    if (g_destroy_render_pass) g_destroy_render_pass(device, renderPass, allocator);
}

static VkResult WINAPI Audit_vkCreateFramebuffer(VkDevice device, const VkFramebufferCreateInfoMini* info,
                                                  const void* allocator, VkFramebuffer* outFramebuffer) {
    MarkApi("vkCreateFramebuffer");
    const LONG id = InterlockedIncrement(&g_create_framebuffer_calls);
    const VkResult result = g_create_framebuffer ? g_create_framebuffer(device, info, allocator, outFramebuffer) : -3;
    const VkFramebuffer handle = (result == 0 && outFramebuffer) ? *outFramebuffer : 0;
    LogFormat("RPSTATE CREATE_FB #%ld result=%d handle=0x%llx rp=0x%llx attachments=%u size=%ux%ux%u flags=0x%x pNext=%p concrete=%d",
              id, result, static_cast<unsigned long long>(handle),
              static_cast<unsigned long long>(info ? info->renderPass : 0),
              info ? info->attachmentCount : 0, info ? info->width : 0,
              info ? info->height : 0, info ? info->layers : 0,
              info ? info->flags : 0, info ? info->pNext : nullptr,
              (info && info->pAttachments) ? 1 : 0);
    if (result == 0 && handle && info) {
        RecordFramebuffer(handle, info);
        if (info->pAttachments) {
            const std::uint32_t count = info->attachmentCount > 9 ? 9 : info->attachmentCount;
            for (std::uint32_t i = 0; i < count; ++i) {
                LogFormat("RPSTATE FB_ATTACHMENT fb=0x%llx i=%u view=0x%llx",
                          static_cast<unsigned long long>(handle), i,
                          static_cast<unsigned long long>(info->pAttachments[i]));
            }
        }
    }
    return result;
}

static void WINAPI Audit_vkDestroyFramebuffer(VkDevice device, VkFramebuffer framebuffer, const void* allocator) {
    MarkApi("vkDestroyFramebuffer");
    const LONG id = InterlockedIncrement(&g_destroy_framebuffer_calls);
    const bool active = IsFramebufferActive(framebuffer);
    LogFormat("RPSTATE DESTROY_FB #%ld handle=0x%llx active=%d", id,
              static_cast<unsigned long long>(framebuffer), active ? 1 : 0);
    if (active) LogFormat("RPSTATE WARNING destroy framebuffer while active handle=0x%llx",
                          static_cast<unsigned long long>(framebuffer));
    if (g_destroy_framebuffer) g_destroy_framebuffer(device, framebuffer, allocator);
    ForgetFramebuffer(framebuffer);
}

static void WINAPI Audit_vkDestroyImageView(VkDevice device, VkImageView view, const void* allocator) {
    MarkApi("vkDestroyImageView");
    const LONG id = InterlockedIncrement(&g_destroy_image_view_calls);
    const bool active = IsImageViewInActiveFramebuffer(view);
    if (active || SampleCall(id, 64, 500)) {
        LogFormat("RPSTATE DESTROY_VIEW #%ld handle=0x%llx active_attachment=%d", id,
                  static_cast<unsigned long long>(view), active ? 1 : 0);
    }
    if (active) LogFormat("RPSTATE WARNING destroy imageView used by active framebuffer handle=0x%llx",
                          static_cast<unsigned long long>(view));
    if (g_destroy_image_view) g_destroy_image_view(device, view, allocator);
}

'@
Replace-Required 'static VkResult WINAPI Audit_vkSetDebugUtilsObjectNameEXT' ($objectWrappers + 'static VkResult WINAPI Audit_vkSetDebugUtilsObjectNameEXT')

# Add active render-pass state around both RenderPass2 and legacy command paths.
Replace-Required @'
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_begin_render_pass) {
        LogFormat("LOWER vkCmdBeginRenderPass2 -> vkCmdBeginRenderPass #%ld contents=%u", id, contents);
        g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
        return;
    }
'@ @'
    RecordRenderPassBegin(commandBuffer, beginInfo, g_lower_renderpass2 && safe_to_lower ? "begin2-lowered" : "begin2-native");
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_begin_render_pass) {
        LogFormat("LOWER vkCmdBeginRenderPass2 -> vkCmdBeginRenderPass #%ld contents=%u", id, contents);
        g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
        return;
    }
'@

Replace-Required @'
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_end_render_pass) {
        LogFormat("LOWER vkCmdEndRenderPass2 -> vkCmdEndRenderPass #%ld", id);
        g_cmd_end_render_pass(commandBuffer);
        return;
    }
'@ @'
    RecordRenderPassEndBefore(commandBuffer, g_lower_renderpass2 && safe_to_lower ? "end2-lowered" : "end2-native");
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_end_render_pass) {
        LogFormat("LOWER vkCmdEndRenderPass2 -> vkCmdEndRenderPass #%ld", id);
        g_cmd_end_render_pass(commandBuffer);
        RecordRenderPassEndSuccess(commandBuffer, "end2-lowered");
        return;
    }
'@

Replace-Required @'
    if (g_cmd_end_render_pass2) g_cmd_end_render_pass2(commandBuffer, subpassEndInfo);
}
'@ @'
    if (g_cmd_end_render_pass2) g_cmd_end_render_pass2(commandBuffer, subpassEndInfo);
    RecordRenderPassEndSuccess(commandBuffer, "end2-native");
}
'@

Replace-Required @'
static void WINAPI Audit_vkCmdBeginRenderPass(VkCommandBuffer commandBuffer, const void* beginInfo, std::uint32_t contents) {
    MarkApi("vkCmdBeginRenderPass");
    const LONG id = InterlockedIncrement(&g_begin_render_pass_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE beginRenderPass #%ld contents=%u", id, contents);
    if (g_cmd_begin_render_pass) g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
}
'@ @'
static void WINAPI Audit_vkCmdBeginRenderPass(VkCommandBuffer commandBuffer, const void* beginInfo, std::uint32_t contents) {
    MarkApi("vkCmdBeginRenderPass");
    const LONG id = InterlockedIncrement(&g_begin_render_pass_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE beginRenderPass #%ld contents=%u", id, contents);
    RecordRenderPassBegin(commandBuffer, beginInfo, "begin-legacy");
    if (g_cmd_begin_render_pass) g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
}
'@

Replace-Required @'
static void WINAPI Audit_vkCmdEndRenderPass(VkCommandBuffer commandBuffer) {
    MarkApi("vkCmdEndRenderPass");
    const LONG id = InterlockedIncrement(&g_end_render_pass_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE endRenderPass #%ld", id);
    if (g_cmd_end_render_pass) g_cmd_end_render_pass(commandBuffer);
}
'@ @'
static void WINAPI Audit_vkCmdEndRenderPass(VkCommandBuffer commandBuffer) {
    MarkApi("vkCmdEndRenderPass");
    const LONG id = InterlockedIncrement(&g_end_render_pass_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE endRenderPass #%ld", id);
    RecordRenderPassEndBefore(commandBuffer, "end-legacy");
    if (g_cmd_end_render_pass) g_cmd_end_render_pass(commandBuffer);
    RecordRenderPassEndSuccess(commandBuffer, "end-legacy");
}
'@

$hooks = @'
    if (strcmp(name, "vkCreateRenderPass") == 0) {
        g_create_render_pass = reinterpret_cast<PFN_vkCreateRenderPass>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCreateRenderPass);
    }
    if (strcmp(name, "vkDestroyRenderPass") == 0) {
        g_destroy_render_pass = reinterpret_cast<PFN_vkDestroyRenderPass>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkDestroyRenderPass);
    }
    if (strcmp(name, "vkCreateFramebuffer") == 0) {
        g_create_framebuffer = reinterpret_cast<PFN_vkCreateFramebuffer>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCreateFramebuffer);
    }
    if (strcmp(name, "vkDestroyFramebuffer") == 0) {
        g_destroy_framebuffer = reinterpret_cast<PFN_vkDestroyFramebuffer>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkDestroyFramebuffer);
    }
    if (strcmp(name, "vkDestroyImageView") == 0) {
        g_destroy_image_view = reinterpret_cast<PFN_vkDestroyImageView>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkDestroyImageView);
    }
'@
$hookAnchor = @'
static PFN_vkVoidFunction MaybeInterceptDevice(VkDevice device, const char* name, PFN_vkVoidFunction real) {
    if (!real || !name) return real;
'@
Replace-Required $hookAnchor ($hookAnchor + $hooks)

Replace-Required @'
        LogLine("VK3to2 Build 04 initialized: RenderPass2 to legacy lowering");
'@ @'
        LogLine("VK3to2 Build 05 initialized: render-pass/framebuffer state + lifetime audit");
'@

New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
Set-Content -LiteralPath $outPath -Value $script:src -Encoding UTF8
Write-Host "Build 05 patch generated $outPath"
