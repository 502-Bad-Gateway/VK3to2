$ErrorActionPreference = 'Stop'

# Build 04 is layered on the proven Build 03 diagnostics, then changes only the
# RenderPass2 command path. Keep the source baseline small and generated builds
# out of the repository.
& .\ci\apply-build03.ps1

$sourcePath = 'dist\vk3to2_build03.cpp'
$outPath = 'dist\vk3to2_build04.cpp'
$script:src = Get-Content -Raw -LiteralPath $sourcePath

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:src.Contains($old)) {
        throw "Build 04 patch anchor not found: $old"
    }
    $script:src = $script:src.Replace($old, $new)
}

Replace-Required @'
// VK3to2 keeps a deliberately small Vulkan ABI surface and does not depend on
// the Vulkan SDK. Build 03 follows the post-pipeline path identified by Build 02:
// debug-object naming can be suppressed independently while cleanup calls are
// traced. All other Vulkan behavior remains pass-through unless an older switch
// is explicitly enabled in VK3to2.ini.
'@ @'
// VK3to2 keeps a deliberately small Vulkan ABI surface and does not depend on
// the Vulkan SDK. Build 04 lowers the RenderPass2 command path used by the frozen
// Windows 7 shadPS4 scheduler to legacy render-pass commands when no pNext-only
// semantics are present. Other workarounds remain independently configurable.
'@

Replace-Required @'
struct VkDebugUtilsObjectNameInfoEXTMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t objectType;
    std::uint64_t objectHandle;
    const char* pObjectName;
};
'@ @'
struct VkDebugUtilsObjectNameInfoEXTMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t objectType;
    std::uint64_t objectHandle;
    const char* pObjectName;
};

struct VkSubpassBeginInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t contents;
};

struct VkSubpassEndInfoMini {
    std::uint32_t sType;
    const void* pNext;
};
'@

Replace-Required @'
using PFN_vkCmdBeginRenderPass = void (WINAPI*)(VkCommandBuffer, const void*, std::uint32_t);
using PFN_vkCmdEndRenderPass = void (WINAPI*)(VkCommandBuffer);
'@ @'
using PFN_vkCmdBeginRenderPass = void (WINAPI*)(VkCommandBuffer, const void*, std::uint32_t);
using PFN_vkCmdNextSubpass = void (WINAPI*)(VkCommandBuffer, std::uint32_t);
using PFN_vkCmdEndRenderPass = void (WINAPI*)(VkCommandBuffer);
using PFN_vkCmdBeginRenderPass2 = void (WINAPI*)(VkCommandBuffer, const void*, const VkSubpassBeginInfoMini*);
using PFN_vkCmdNextSubpass2 = void (WINAPI*)(VkCommandBuffer, const VkSubpassBeginInfoMini*, const VkSubpassEndInfoMini*);
using PFN_vkCmdEndRenderPass2 = void (WINAPI*)(VkCommandBuffer, const VkSubpassEndInfoMini*);
'@

Replace-Required @'
static bool g_disable_debug_object_names = false;
'@ @'
static bool g_disable_debug_object_names = false;
static bool g_lower_renderpass2 = false;
'@

Replace-Required @'
static PFN_vkCmdBeginRenderPass g_cmd_begin_render_pass = nullptr;
static PFN_vkCmdEndRenderPass g_cmd_end_render_pass = nullptr;
'@ @'
static PFN_vkCmdBeginRenderPass g_cmd_begin_render_pass = nullptr;
static PFN_vkCmdNextSubpass g_cmd_next_subpass = nullptr;
static PFN_vkCmdEndRenderPass g_cmd_end_render_pass = nullptr;
static PFN_vkCmdBeginRenderPass2 g_cmd_begin_render_pass2 = nullptr;
static PFN_vkCmdNextSubpass2 g_cmd_next_subpass2 = nullptr;
static PFN_vkCmdEndRenderPass2 g_cmd_end_render_pass2 = nullptr;
'@

Replace-Required @'
static volatile LONG g_begin_render_pass_calls = 0;
static volatile LONG g_end_render_pass_calls = 0;
'@ @'
static volatile LONG g_begin_render_pass_calls = 0;
static volatile LONG g_next_subpass_calls = 0;
static volatile LONG g_end_render_pass_calls = 0;
static volatile LONG g_begin_render_pass2_calls = 0;
static volatile LONG g_next_subpass2_calls = 0;
static volatile LONG g_end_render_pass2_calls = 0;
'@

Replace-Required @'
    g_disable_debug_object_names = GetPrivateProfileIntW(L"patches", L"disable_debug_object_names", 0, ini_path) != 0;
'@ @'
    g_disable_debug_object_names = GetPrivateProfileIntW(L"patches", L"disable_debug_object_names", 0, ini_path) != 0;
    g_lower_renderpass2 = GetPrivateProfileIntW(L"patches", L"lower_renderpass2", 0, ini_path) != 0;
'@

Replace-Required @'
        LogLine("VK3to2 Build 03 initialized: post-pipeline debug-name isolation");
        LogLine("Real loader: %SystemRoot%\\System32\\vulkan-1.dll");
        LogFormat("OPTIONS trace.sampled_calls=%d trace.nvidia_exceptions=%d", g_trace_sampled_calls ? 1 : 0, g_trace_nvidia_exceptions ? 1 : 0);
        LogFormat("OPTIONS patches.serialize_pipelines=%d patches.disable_pipeline_cache=%d patches.disable_debug_object_names=%d",
                  g_serialize_pipelines ? 1 : 0, g_disable_pipeline_cache ? 1 : 0,
                  g_disable_debug_object_names ? 1 : 0);
'@ @'
        LogLine("VK3to2 Build 04 initialized: RenderPass2 to legacy lowering");
        LogLine("Real loader: %SystemRoot%\\System32\\vulkan-1.dll");
        LogFormat("OPTIONS trace.sampled_calls=%d trace.nvidia_exceptions=%d", g_trace_sampled_calls ? 1 : 0, g_trace_nvidia_exceptions ? 1 : 0);
        LogFormat("OPTIONS patches.serialize_pipelines=%d patches.disable_pipeline_cache=%d patches.disable_debug_object_names=%d patches.lower_renderpass2=%d",
                  g_serialize_pipelines ? 1 : 0, g_disable_pipeline_cache ? 1 : 0,
                  g_disable_debug_object_names ? 1 : 0, g_lower_renderpass2 ? 1 : 0);
'@

$renderPass2Wrappers = @'
static void WINAPI Audit_vkCmdBeginRenderPass2(VkCommandBuffer commandBuffer, const void* beginInfo,
                                                const VkSubpassBeginInfoMini* subpassBeginInfo) {
    MarkApi("vkCmdBeginRenderPass2");
    const LONG id = InterlockedIncrement(&g_begin_render_pass2_calls);
    const std::uint32_t contents = subpassBeginInfo ? subpassBeginInfo->contents : 0;
    const bool safe_to_lower = !subpassBeginInfo || subpassBeginInfo->pNext == nullptr;
    if (SampleCall(id, 128, 500)) {
        LogFormat("TRACE beginRenderPass2 #%ld contents=%u lower=%d safe=%d", id, contents,
                  g_lower_renderpass2 ? 1 : 0, safe_to_lower ? 1 : 0);
    }
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_begin_render_pass) {
        LogFormat("LOWER vkCmdBeginRenderPass2 -> vkCmdBeginRenderPass #%ld contents=%u", id, contents);
        g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
        return;
    }
    if (g_lower_renderpass2 && !safe_to_lower) {
        LogFormat("BYPASS RenderPass2 lowering on begin #%ld: VkSubpassBeginInfo.pNext is non-null", id);
    }
    if (g_cmd_begin_render_pass2) g_cmd_begin_render_pass2(commandBuffer, beginInfo, subpassBeginInfo);
}

static void WINAPI Audit_vkCmdNextSubpass2(VkCommandBuffer commandBuffer,
                                            const VkSubpassBeginInfoMini* subpassBeginInfo,
                                            const VkSubpassEndInfoMini* subpassEndInfo) {
    MarkApi("vkCmdNextSubpass2");
    const LONG id = InterlockedIncrement(&g_next_subpass2_calls);
    const std::uint32_t contents = subpassBeginInfo ? subpassBeginInfo->contents : 0;
    const bool safe_to_lower = (!subpassBeginInfo || subpassBeginInfo->pNext == nullptr) &&
                               (!subpassEndInfo || subpassEndInfo->pNext == nullptr);
    if (SampleCall(id, 128, 500)) {
        LogFormat("TRACE nextSubpass2 #%ld contents=%u lower=%d safe=%d", id, contents,
                  g_lower_renderpass2 ? 1 : 0, safe_to_lower ? 1 : 0);
    }
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_next_subpass) {
        LogFormat("LOWER vkCmdNextSubpass2 -> vkCmdNextSubpass #%ld contents=%u", id, contents);
        g_cmd_next_subpass(commandBuffer, contents);
        return;
    }
    if (g_lower_renderpass2 && !safe_to_lower) {
        LogFormat("BYPASS RenderPass2 lowering on next #%ld: subpass pNext is non-null", id);
    }
    if (g_cmd_next_subpass2) g_cmd_next_subpass2(commandBuffer, subpassBeginInfo, subpassEndInfo);
}

static void WINAPI Audit_vkCmdEndRenderPass2(VkCommandBuffer commandBuffer,
                                              const VkSubpassEndInfoMini* subpassEndInfo) {
    MarkApi("vkCmdEndRenderPass2");
    const LONG id = InterlockedIncrement(&g_end_render_pass2_calls);
    const bool safe_to_lower = !subpassEndInfo || subpassEndInfo->pNext == nullptr;
    if (SampleCall(id, 128, 500)) {
        LogFormat("TRACE endRenderPass2 #%ld lower=%d safe=%d", id,
                  g_lower_renderpass2 ? 1 : 0, safe_to_lower ? 1 : 0);
    }
    if (g_lower_renderpass2 && safe_to_lower && g_cmd_end_render_pass) {
        LogFormat("LOWER vkCmdEndRenderPass2 -> vkCmdEndRenderPass #%ld", id);
        g_cmd_end_render_pass(commandBuffer);
        return;
    }
    if (g_lower_renderpass2 && !safe_to_lower) {
        LogFormat("BYPASS RenderPass2 lowering on end #%ld: VkSubpassEndInfo.pNext is non-null", id);
    }
    if (g_cmd_end_render_pass2) g_cmd_end_render_pass2(commandBuffer, subpassEndInfo);
}

'@
Replace-Required 'static void WINAPI Audit_vkCmdBeginRenderPass(' ($renderPass2Wrappers + 'static void WINAPI Audit_vkCmdBeginRenderPass(')

# Let the device-hook path proactively resolve the legacy functions so lowering
# does not depend on dispatch-table query order.
Replace-Required @'
static PFN_vkVoidFunction MaybeInterceptDevice(const char* name, PFN_vkVoidFunction real) {
    if (!real || !name) return real;
'@ @'
static PFN_vkVoidFunction MaybeInterceptDevice(VkDevice device, const char* name, PFN_vkVoidFunction real) {
    if (!real || !name) return real;

    if ((strcmp(name, "vkCmdBeginRenderPass2") == 0 || strcmp(name, "vkCmdBeginRenderPass2KHR") == 0 ||
         strcmp(name, "vkCmdNextSubpass2") == 0 || strcmp(name, "vkCmdNextSubpass2KHR") == 0 ||
         strcmp(name, "vkCmdEndRenderPass2") == 0 || strcmp(name, "vkCmdEndRenderPass2KHR") == 0) &&
        g_real_gdpa) {
        if (!g_cmd_begin_render_pass) {
            g_cmd_begin_render_pass = reinterpret_cast<PFN_vkCmdBeginRenderPass>(g_real_gdpa(device, "vkCmdBeginRenderPass"));
        }
        if (!g_cmd_next_subpass) {
            g_cmd_next_subpass = reinterpret_cast<PFN_vkCmdNextSubpass>(g_real_gdpa(device, "vkCmdNextSubpass"));
        }
        if (!g_cmd_end_render_pass) {
            g_cmd_end_render_pass = reinterpret_cast<PFN_vkCmdEndRenderPass>(g_real_gdpa(device, "vkCmdEndRenderPass"));
        }
    }
'@

$renderPass2Hooks = @'
    if (strcmp(name, "vkCmdBeginRenderPass2") == 0 || strcmp(name, "vkCmdBeginRenderPass2KHR") == 0) {
        g_cmd_begin_render_pass2 = reinterpret_cast<PFN_vkCmdBeginRenderPass2>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdBeginRenderPass2);
    }
    if (strcmp(name, "vkCmdNextSubpass2") == 0 || strcmp(name, "vkCmdNextSubpass2KHR") == 0) {
        g_cmd_next_subpass2 = reinterpret_cast<PFN_vkCmdNextSubpass2>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdNextSubpass2);
    }
    if (strcmp(name, "vkCmdEndRenderPass2") == 0 || strcmp(name, "vkCmdEndRenderPass2KHR") == 0) {
        g_cmd_end_render_pass2 = reinterpret_cast<PFN_vkCmdEndRenderPass2>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdEndRenderPass2);
    }
    if (strcmp(name, "vkCmdNextSubpass") == 0) {
        g_cmd_next_subpass = reinterpret_cast<PFN_vkCmdNextSubpass>(real);
        return real;
    }
'@
$hookAnchor = @'
    if (strcmp(name, "vkCmdBeginRenderPass") == 0) {
'@
Replace-Required $hookAnchor ($renderPass2Hooks + $hookAnchor)

Replace-Required 'return MaybeInterceptDevice(name, real);' 'return MaybeInterceptDevice(device, name, real);'

New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
Set-Content -LiteralPath $outPath -Value $script:src -Encoding UTF8
Write-Host "Build 04 patch generated $outPath"
