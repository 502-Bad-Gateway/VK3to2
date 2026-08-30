$ErrorActionPreference = 'Stop'

$sourcePath = 'src\vk3to2_proxy.cpp'
$outPath = 'dist\vk3to2_build03.cpp'
$script:src = Get-Content -Raw -LiteralPath $sourcePath

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:src.Contains($old)) {
        throw "Build 03 patch anchor not found: $old"
    }
    $script:src = $script:src.Replace($old, $new)
}

Replace-Required @'
// VK3to2 keeps a deliberately small Vulkan ABI surface and does not depend on
// the Vulkan SDK. Build 02 is still pass-through by default. Its main purpose is
// to correlate the NVIDIA access violation with the Vulkan call/thread that was
// active when the fault happened. Optional patch switches are present but OFF.
'@ @'
// VK3to2 keeps a deliberately small Vulkan ABI surface and does not depend on
// the Vulkan SDK. Build 03 follows the post-pipeline path identified by Build 02:
// debug-object naming can be suppressed independently while cleanup calls are
// traced. All other Vulkan behavior remains pass-through unless an older switch
// is explicitly enabled in VK3to2.ini.
'@

Replace-Required @'
struct VkPhysicalDevicePropertiesPrefix {
    std::uint32_t apiVersion;
    std::uint32_t driverVersion;
    std::uint32_t vendorID;
    std::uint32_t deviceID;
    std::uint32_t deviceType;
    char deviceName[256];
};
'@ @'
struct VkPhysicalDevicePropertiesPrefix {
    std::uint32_t apiVersion;
    std::uint32_t driverVersion;
    std::uint32_t vendorID;
    std::uint32_t deviceID;
    std::uint32_t deviceType;
    char deviceName[256];
};

struct VkDebugUtilsObjectNameInfoEXTMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t objectType;
    std::uint64_t objectHandle;
    const char* pObjectName;
};
'@

Replace-Required @'
using PFN_vkCreateShaderModule = VkResult (WINAPI*)(VkDevice, const void*, const void*, VkShaderModule*);
'@ @'
using PFN_vkCreateShaderModule = VkResult (WINAPI*)(VkDevice, const void*, const void*, VkShaderModule*);
using PFN_vkSetDebugUtilsObjectNameEXT = VkResult (WINAPI*)(VkDevice, const VkDebugUtilsObjectNameInfoEXTMini*);
using PFN_vkDestroyShaderModule = void (WINAPI*)(VkDevice, VkShaderModule, const void*);
using PFN_vkDestroyPipeline = void (WINAPI*)(VkDevice, VkPipeline, const void*);
'@

Replace-Required @'
static bool g_disable_pipeline_cache = false;
'@ @'
static bool g_disable_pipeline_cache = false;
static bool g_disable_debug_object_names = false;
'@

Replace-Required @'
static PFN_vkCreateShaderModule g_create_shader_module = nullptr;
'@ @'
static PFN_vkCreateShaderModule g_create_shader_module = nullptr;
static PFN_vkSetDebugUtilsObjectNameEXT g_set_debug_utils_object_name_ext = nullptr;
static PFN_vkDestroyShaderModule g_destroy_shader_module = nullptr;
static PFN_vkDestroyPipeline g_destroy_pipeline = nullptr;
'@

Replace-Required @'
static volatile LONG g_shader_module_calls = 0;
'@ @'
static volatile LONG g_shader_module_calls = 0;
static volatile LONG g_debug_object_name_calls = 0;
static volatile LONG g_destroy_shader_module_calls = 0;
static volatile LONG g_destroy_pipeline_calls = 0;
'@

Replace-Required @'
    g_disable_pipeline_cache = GetPrivateProfileIntW(L"patches", L"disable_pipeline_cache", 0, ini_path) != 0;
'@ @'
    g_disable_pipeline_cache = GetPrivateProfileIntW(L"patches", L"disable_pipeline_cache", 0, ini_path) != 0;
    g_disable_debug_object_names = GetPrivateProfileIntW(L"patches", L"disable_debug_object_names", 0, ini_path) != 0;
'@

Replace-Required @'
        LogLine("VK3to2 Build 02 initialized: execution + NVIDIA crash correlation");
        LogLine("Real loader: %SystemRoot%\\System32\\vulkan-1.dll");
        LogFormat("OPTIONS trace.sampled_calls=%d trace.nvidia_exceptions=%d", g_trace_sampled_calls ? 1 : 0, g_trace_nvidia_exceptions ? 1 : 0);
        LogFormat("OPTIONS patches.serialize_pipelines=%d patches.disable_pipeline_cache=%d", g_serialize_pipelines ? 1 : 0, g_disable_pipeline_cache ? 1 : 0);
'@ @'
        LogLine("VK3to2 Build 03 initialized: post-pipeline debug-name isolation");
        LogLine("Real loader: %SystemRoot%\\System32\\vulkan-1.dll");
        LogFormat("OPTIONS trace.sampled_calls=%d trace.nvidia_exceptions=%d", g_trace_sampled_calls ? 1 : 0, g_trace_nvidia_exceptions ? 1 : 0);
        LogFormat("OPTIONS patches.serialize_pipelines=%d patches.disable_pipeline_cache=%d patches.disable_debug_object_names=%d",
                  g_serialize_pipelines ? 1 : 0, g_disable_pipeline_cache ? 1 : 0,
                  g_disable_debug_object_names ? 1 : 0);
'@

$wrappers = @'
static VkResult WINAPI Audit_vkSetDebugUtilsObjectNameEXT(VkDevice device, const VkDebugUtilsObjectNameInfoEXTMini* info) {
    MarkApi("vkSetDebugUtilsObjectNameEXT");
    const LONG id = InterlockedIncrement(&g_debug_object_name_calls);
    const std::uint32_t object_type = info ? info->objectType : 0;
    const std::uint64_t object_handle = info ? info->objectHandle : 0;
    const char* object_name = (info && info->pObjectName) ? info->pObjectName : "<null>";
    LogFormat("TRACE debugObjectName #%ld ENTER objectType=%u handle=0x%llx suppress=%d name=%.160s",
              id, object_type, static_cast<unsigned long long>(object_handle),
              g_disable_debug_object_names ? 1 : 0, object_name);
    if (g_disable_debug_object_names) {
        LogFormat("TRACE debugObjectName #%ld SKIP return=VK_SUCCESS", id);
        return 0;
    }
    const VkResult result = g_set_debug_utils_object_name_ext ? g_set_debug_utils_object_name_ext(device, info) : -3;
    LogFormat("TRACE debugObjectName #%ld RETURN result=%d", id, result);
    return result;
}

static void WINAPI Audit_vkDestroyShaderModule(VkDevice device, VkShaderModule module, const void* allocator) {
    MarkApi("vkDestroyShaderModule");
    const LONG id = InterlockedIncrement(&g_destroy_shader_module_calls);
    if (SampleCall(id, 128, 500)) {
        LogFormat("TRACE destroyShaderModule #%ld module=0x%llx", id,
                  static_cast<unsigned long long>(module));
    }
    if (g_destroy_shader_module) g_destroy_shader_module(device, module, allocator);
}

static void WINAPI Audit_vkDestroyPipeline(VkDevice device, VkPipeline pipeline, const void* allocator) {
    MarkApi("vkDestroyPipeline");
    const LONG id = InterlockedIncrement(&g_destroy_pipeline_calls);
    if (SampleCall(id, 128, 500)) {
        LogFormat("TRACE destroyPipeline #%ld pipeline=0x%llx", id,
                  static_cast<unsigned long long>(pipeline));
    }
    if (g_destroy_pipeline) g_destroy_pipeline(device, pipeline, allocator);
}

'@
Replace-Required 'static VkResult WINAPI Audit_vkCreateShaderModule' ($wrappers + 'static VkResult WINAPI Audit_vkCreateShaderModule')

$deviceHooks = @'
    if (strcmp(name, "vkSetDebugUtilsObjectNameEXT") == 0) {
        g_set_debug_utils_object_name_ext = reinterpret_cast<PFN_vkSetDebugUtilsObjectNameEXT>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkSetDebugUtilsObjectNameEXT);
    }
    if (strcmp(name, "vkDestroyShaderModule") == 0) {
        g_destroy_shader_module = reinterpret_cast<PFN_vkDestroyShaderModule>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkDestroyShaderModule);
    }
    if (strcmp(name, "vkDestroyPipeline") == 0) {
        g_destroy_pipeline = reinterpret_cast<PFN_vkDestroyPipeline>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkDestroyPipeline);
    }
'@
$deviceAnchor = @'
static PFN_vkVoidFunction MaybeInterceptDevice(const char* name, PFN_vkVoidFunction real) {
    if (!real || !name) return real;
'@
Replace-Required $deviceAnchor ($deviceAnchor + $deviceHooks)

# vkSetDebugUtilsObjectNameEXT may also be queried through vkGetInstanceProcAddr.
$instanceHook = @'
    if (strcmp(name, "vkSetDebugUtilsObjectNameEXT") == 0) {
        g_set_debug_utils_object_name_ext = reinterpret_cast<PFN_vkSetDebugUtilsObjectNameEXT>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkSetDebugUtilsObjectNameEXT);
    }
'@
$instanceAnchor = @'
static PFN_vkVoidFunction MaybeInterceptInstance(const char* name, PFN_vkVoidFunction real) {
    if (!real || !name) return real;
'@
Replace-Required $instanceAnchor ($instanceAnchor + $instanceHook)

New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
Set-Content -LiteralPath $outPath -Value $script:src -Encoding UTF8
Write-Host "Build 03 patch generated $outPath"
