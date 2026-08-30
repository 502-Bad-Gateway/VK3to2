$ErrorActionPreference = 'Stop'

# Build 06 layers a narrowly-scoped compatibility guard on Build 05. Build 05
# proved that both observed NVIDIA crashes occur on concrete framebuffers whose
# attachment count does not match the render pass. Build 06 suppresses only the
# begin/end pair for such incomplete passes; all other Vulkan calls remain
# pass-through.
& .\ci\apply-build05.ps1

$sourcePath = 'dist\vk3to2_build05.cpp'
$outPath = 'dist\vk3to2_build06.cpp'
$script:src = Get-Content -Raw -LiteralPath $sourcePath

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:src.Contains($old)) {
        throw "Build 06 patch anchor not found: $old"
    }
    $script:src = $script:src.Replace($old, $new)
}

Replace-Required @'
static bool g_lower_renderpass2 = false;
'@ @'
static bool g_lower_renderpass2 = false;
static bool g_guard_incomplete_framebuffers = false;
'@

Replace-Required @'
    g_lower_renderpass2 = GetPrivateProfileIntW(L"patches", L"lower_renderpass2", 0, ini_path) != 0;
'@ @'
    g_lower_renderpass2 = GetPrivateProfileIntW(L"patches", L"lower_renderpass2", 0, ini_path) != 0;
    g_guard_incomplete_framebuffers =
        GetPrivateProfileIntW(L"patches", L"guard_incomplete_framebuffers", 0, ini_path) != 0;
'@

Replace-Required @'
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
'@ @'
struct RenderPassAuditRecord {
    bool used;
    VkRenderPass renderPass;
    std::uint32_t attachmentCount;
};

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

struct ActiveRenderPassAuditRecord {
    bool used;
    bool suppressed;
    VkCommandBuffer commandBuffer;
    VkRenderPass renderPass;
    VkFramebuffer framebuffer;
};

static SRWLOCK g_render_audit_lock = SRWLOCK_INIT;
static RenderPassAuditRecord g_render_pass_records[512]{};
static FramebufferAuditRecord g_framebuffer_records[2048]{};
static ActiveRenderPassAuditRecord g_active_render_pass_records[128]{};
'@

$contractHelpers = @'
static void RecordRenderPassContract(VkRenderPass renderPass, const VkRenderPassCreateInfoMini* info) {
    if (!renderPass || !info) return;
    AcquireSRWLockExclusive(&g_render_audit_lock);
    RenderPassAuditRecord* record = nullptr;
    for (auto& candidate : g_render_pass_records) {
        if (candidate.used && candidate.renderPass == renderPass) {
            record = &candidate;
            break;
        }
        if (!record && !candidate.used) record = &candidate;
    }
    if (record) {
        record->used = true;
        record->renderPass = renderPass;
        record->attachmentCount = info->attachmentCount;
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

static void ForgetRenderPassContract(VkRenderPass renderPass) {
    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& record : g_render_pass_records) {
        if (record.used && record.renderPass == renderPass) {
            record.used = false;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

'@
Replace-Required 'static void RecordFramebuffer(VkFramebuffer framebuffer, const VkFramebufferCreateInfoMini* info) {' ($contractHelpers + 'static void RecordFramebuffer(VkFramebuffer framebuffer, const VkFramebufferCreateInfoMini* info) {')

Replace-Required @'
        record->renderPass = info->renderPass;
        record->attachmentCount = info->attachmentCount > 9 ? 9 : info->attachmentCount;
        record->width = info->width;
'@ @'
        record->renderPass = info->renderPass;
        record->attachmentCount = info->attachmentCount > 9 ? 9 : info->attachmentCount;
        record->actualAttachmentCount = info->attachmentCount;
        record->expectedAttachmentCount = info->attachmentCount;
        record->incomplete = false;
        const bool concrete = (info->flags & 0x1u) == 0;
        if (concrete) {
            for (const auto& rp : g_render_pass_records) {
                if (rp.used && rp.renderPass == info->renderPass) {
                    record->expectedAttachmentCount = rp.attachmentCount;
                    record->incomplete = info->attachmentCount != rp.attachmentCount;
                    break;
                }
            }
        }
        record->width = info->width;
'@

Replace-Required @'
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

static void ForgetFramebuffer(VkFramebuffer framebuffer) {
'@ @'
    if (record && record->incomplete) {
        LogFormat("RPSTATE CONTRACT_MISMATCH fb=0x%llx rp=0x%llx expected_attachments=%u actual_attachments=%u",
                  static_cast<unsigned long long>(record->framebuffer),
                  static_cast<unsigned long long>(record->renderPass),
                  record->expectedAttachmentCount, record->actualAttachmentCount);
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);
}

static void ForgetFramebuffer(VkFramebuffer framebuffer) {
'@

Replace-Required @'
        active->used = true;
        active->commandBuffer = commandBuffer;
'@ @'
        active->used = true;
        active->suppressed = false;
        active->commandBuffer = commandBuffer;
'@

$guardHelpers = @'
static bool GuardIncompleteFramebufferBegin(VkCommandBuffer commandBuffer, const void* beginInfoVoid,
                                            const char* path) {
    if (!g_guard_incomplete_framebuffers || !beginInfoVoid) return false;
    const auto* beginInfo = reinterpret_cast<const VkRenderPassBeginInfoMini*>(beginInfoVoid);
    bool suppress = false;
    std::uint32_t expected = 0;
    std::uint32_t actual = 0;

    AcquireSRWLockShared(&g_render_audit_lock);
    for (const auto& fb : g_framebuffer_records) {
        if (!fb.used || fb.framebuffer != beginInfo->framebuffer) continue;
        if (fb.renderPass == beginInfo->renderPass && fb.incomplete) {
            suppress = true;
            expected = fb.expectedAttachmentCount;
            actual = fb.actualAttachmentCount;
        }
        break;
    }
    ReleaseSRWLockShared(&g_render_audit_lock);

    if (!suppress) return false;

    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& active : g_active_render_pass_records) {
        if (active.used && active.commandBuffer == commandBuffer) {
            active.suppressed = true;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);

    LogFormat("GUARD INCOMPLETE_FB SUPPRESS_BEGIN path=%s cmd=%p rp=0x%llx fb=0x%llx expected=%u actual=%u",
              path, commandBuffer,
              static_cast<unsigned long long>(beginInfo->renderPass),
              static_cast<unsigned long long>(beginInfo->framebuffer),
              expected, actual);
    return true;
}

static bool ConsumeSuppressedRenderPassEnd(VkCommandBuffer commandBuffer, const char* path) {
    if (!g_guard_incomplete_framebuffers) return false;
    bool suppressed = false;
    VkRenderPass renderPass = 0;
    VkFramebuffer framebuffer = 0;

    AcquireSRWLockExclusive(&g_render_audit_lock);
    for (auto& active : g_active_render_pass_records) {
        if (active.used && active.commandBuffer == commandBuffer && active.suppressed) {
            suppressed = true;
            renderPass = active.renderPass;
            framebuffer = active.framebuffer;
            active.used = false;
            active.suppressed = false;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_render_audit_lock);

    if (suppressed) {
        LogFormat("GUARD INCOMPLETE_FB SUPPRESS_END path=%s cmd=%p rp=0x%llx fb=0x%llx",
                  path, commandBuffer,
                  static_cast<unsigned long long>(renderPass),
                  static_cast<unsigned long long>(framebuffer));
    }
    return suppressed;
}

'@
Replace-Required 'static bool IsFramebufferActive(VkFramebuffer framebuffer) {' ($guardHelpers + 'static bool IsFramebufferActive(VkFramebuffer framebuffer) {')

Replace-Required @'
    const VkRenderPass handle = (result == 0 && outRenderPass) ? *outRenderPass : 0;
    LogFormat("RPSTATE CREATE_RP #%ld result=%d handle=0x%llx attachments=%u subpasses=%u deps=%u pNext=%p",
'@ @'
    const VkRenderPass handle = (result == 0 && outRenderPass) ? *outRenderPass : 0;
    if (result == 0 && handle && info) RecordRenderPassContract(handle, info);
    LogFormat("RPSTATE CREATE_RP #%ld result=%d handle=0x%llx attachments=%u subpasses=%u deps=%u pNext=%p",
'@

Replace-Required @'
    if (g_destroy_render_pass) g_destroy_render_pass(device, renderPass, allocator);
}
'@ @'
    if (g_destroy_render_pass) g_destroy_render_pass(device, renderPass, allocator);
    ForgetRenderPassContract(renderPass);
}
'@

Replace-Required @'
    RecordRenderPassBegin(commandBuffer, beginInfo, g_lower_renderpass2 && safe_to_lower ? "begin2-lowered" : "begin2-native");
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_begin_render_pass) {
'@ @'
    const char* audit_path = g_lower_renderpass2 && safe_to_lower ? "begin2-lowered" : "begin2-native";
    RecordRenderPassBegin(commandBuffer, beginInfo, audit_path);
    if (GuardIncompleteFramebufferBegin(commandBuffer, beginInfo, audit_path)) return;
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_begin_render_pass) {
'@

Replace-Required @'
    RecordRenderPassEndBefore(commandBuffer, g_lower_renderpass2 && safe_to_lower ? "end2-lowered" : "end2-native");
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_end_render_pass) {
'@ @'
    const char* audit_path = g_lower_renderpass2 && safe_to_lower ? "end2-lowered" : "end2-native";
    RecordRenderPassEndBefore(commandBuffer, audit_path);
    if (ConsumeSuppressedRenderPassEnd(commandBuffer, audit_path)) return;
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_end_render_pass) {
'@

Replace-Required @'
    RecordRenderPassBegin(commandBuffer, beginInfo, "begin-legacy");
    if (g_cmd_begin_render_pass) g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
'@ @'
    RecordRenderPassBegin(commandBuffer, beginInfo, "begin-legacy");
    if (GuardIncompleteFramebufferBegin(commandBuffer, beginInfo, "begin-legacy")) return;
    if (g_cmd_begin_render_pass) g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
'@

Replace-Required @'
    RecordRenderPassEndBefore(commandBuffer, "end-legacy");
    if (g_cmd_end_render_pass) g_cmd_end_render_pass(commandBuffer);
    RecordRenderPassEndSuccess(commandBuffer, "end-legacy");
'@ @'
    RecordRenderPassEndBefore(commandBuffer, "end-legacy");
    if (ConsumeSuppressedRenderPassEnd(commandBuffer, "end-legacy")) return;
    if (g_cmd_end_render_pass) g_cmd_end_render_pass(commandBuffer);
    RecordRenderPassEndSuccess(commandBuffer, "end-legacy");
'@

Replace-Required @'
        LogLine("VK3to2 Build 05 initialized: render-pass/framebuffer state + lifetime audit");
'@ @'
        LogLine("VK3to2 Build 06 initialized: incomplete framebuffer guard");
        LogFormat("OPTIONS patches.guard_incomplete_framebuffers=%d",
                  g_guard_incomplete_framebuffers ? 1 : 0);
'@

New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
Set-Content -LiteralPath $outPath -Value $script:src -Encoding UTF8
Write-Host "Build 06 patch generated $outPath"
