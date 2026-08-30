#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdarg>
#include <cstdio>
#include <cstring>

// VK3to2 keeps a deliberately small Vulkan ABI surface and does not depend on
// the Vulkan SDK. Build 02 is still pass-through by default. Its main purpose is
// to correlate the NVIDIA access violation with the Vulkan call/thread that was
// active when the fault happened. Optional patch switches are present but OFF.
struct VkInstance_T;
struct VkPhysicalDevice_T;
struct VkDevice_T;
struct VkQueue_T;
struct VkCommandBuffer_T;

using VkInstance = VkInstance_T*;
using VkPhysicalDevice = VkPhysicalDevice_T*;
using VkDevice = VkDevice_T*;
using VkQueue = VkQueue_T*;
using VkCommandBuffer = VkCommandBuffer_T*;
using VkResult = std::int32_t;
using VkPipelineCache = std::uint64_t;
using VkPipeline = std::uint64_t;
using VkShaderModule = std::uint64_t;
using VkFence = std::uint64_t;
using VkPipelineLayout = std::uint64_t;
using PFN_vkVoidFunction = void (WINAPI*)();

struct VkApplicationInfoMini {
    std::uint32_t sType;
    const void* pNext;
    const char* pApplicationName;
    std::uint32_t applicationVersion;
    const char* pEngineName;
    std::uint32_t engineVersion;
    std::uint32_t apiVersion;
};

struct VkInstanceCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    const VkApplicationInfoMini* pApplicationInfo;
    std::uint32_t enabledLayerCount;
    const char* const* ppEnabledLayerNames;
    std::uint32_t enabledExtensionCount;
    const char* const* ppEnabledExtensionNames;
};

struct VkDeviceCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    std::uint32_t queueCreateInfoCount;
    const void* pQueueCreateInfos;
    std::uint32_t enabledLayerCount;
    const char* const* ppEnabledLayerNames;
    std::uint32_t enabledExtensionCount;
    const char* const* ppEnabledExtensionNames;
    const void* pEnabledFeatures;
};

struct VkBaseInStructureMini {
    std::uint32_t sType;
    const VkBaseInStructureMini* pNext;
};

struct VkPhysicalDevicePropertiesPrefix {
    std::uint32_t apiVersion;
    std::uint32_t driverVersion;
    std::uint32_t vendorID;
    std::uint32_t deviceID;
    std::uint32_t deviceType;
    char deviceName[256];
};

using PFN_vkGetInstanceProcAddr = PFN_vkVoidFunction (WINAPI*)(VkInstance, const char*);
using PFN_vkGetDeviceProcAddr = PFN_vkVoidFunction (WINAPI*)(VkDevice, const char*);
using PFN_vkEnumerateInstanceVersion = VkResult (WINAPI*)(std::uint32_t*);
using PFN_vkCreateInstance = VkResult (WINAPI*)(const VkInstanceCreateInfoMini*, const void*, VkInstance*);
using PFN_vkCreateDevice = VkResult (WINAPI*)(VkPhysicalDevice, const VkDeviceCreateInfoMini*, const void*, VkDevice*);
using PFN_vkGetPhysicalDeviceProperties = void (WINAPI*)(VkPhysicalDevice, void*);
using PFN_vkCreateShaderModule = VkResult (WINAPI*)(VkDevice, const void*, const void*, VkShaderModule*);
using PFN_vkCreateGraphicsPipelines = VkResult (WINAPI*)(VkDevice, VkPipelineCache, std::uint32_t, const void*, const void*, VkPipeline*);
using PFN_vkCreateComputePipelines = VkResult (WINAPI*)(VkDevice, VkPipelineCache, std::uint32_t, const void*, const void*, VkPipeline*);
using PFN_vkQueueSubmit = VkResult (WINAPI*)(VkQueue, std::uint32_t, const void*, VkFence);
using PFN_vkQueueSubmit2KHR = VkResult (WINAPI*)(VkQueue, std::uint32_t, const void*, VkFence);
using PFN_vkQueuePresentKHR = VkResult (WINAPI*)(VkQueue, const void*);
using PFN_vkEndCommandBuffer = VkResult (WINAPI*)(VkCommandBuffer);
using PFN_vkCmdPushDescriptorSetKHR = void (WINAPI*)(VkCommandBuffer, std::uint32_t, VkPipelineLayout, std::uint32_t, std::uint32_t, const void*);
using PFN_vkCmdPipelineBarrier2KHR = void (WINAPI*)(VkCommandBuffer, const void*);
using PFN_vkCmdSetVertexInputEXT = void (WINAPI*)(VkCommandBuffer, std::uint32_t, const void*, std::uint32_t, const void*);
using PFN_vkCmdBeginRenderPass = void (WINAPI*)(VkCommandBuffer, const void*, std::uint32_t);
using PFN_vkCmdEndRenderPass = void (WINAPI*)(VkCommandBuffer);
using PFN_vkCmdBindPipeline = void (WINAPI*)(VkCommandBuffer, std::uint32_t, VkPipeline);
using PFN_vkCmdDraw = void (WINAPI*)(VkCommandBuffer, std::uint32_t, std::uint32_t, std::uint32_t, std::uint32_t);
using PFN_vkCmdDrawIndexed = void (WINAPI*)(VkCommandBuffer, std::uint32_t, std::uint32_t, std::uint32_t, std::int32_t, std::uint32_t);
using PFN_vkCmdDispatch = void (WINAPI*)(VkCommandBuffer, std::uint32_t, std::uint32_t, std::uint32_t);
using PFN_vkCmdBeginRendering = void (WINAPI*)(VkCommandBuffer, const void*);
using PFN_vkCmdEndRendering = void (WINAPI*)(VkCommandBuffer);

static HMODULE g_self = nullptr;
static HMODULE g_real_vulkan = nullptr;
static HMODULE g_nvidia_module = nullptr;
static PFN_vkGetInstanceProcAddr g_real_gipa = nullptr;
static PFN_vkGetDeviceProcAddr g_real_gdpa = nullptr;
static INIT_ONCE g_init_once = INIT_ONCE_STATIC_INIT;
static SRWLOCK g_pipeline_lock = SRWLOCK_INIT;

static bool g_trace_sampled_calls = true;
static bool g_trace_nvidia_exceptions = true;
static bool g_serialize_pipelines = false;
static bool g_disable_pipeline_cache = false;
static PVOID g_veh_handle = nullptr;
static volatile LONG g_exception_log_count = 0;
static volatile LONG g_global_last_tid = 0;
static PVOID volatile g_global_last_api = nullptr;
static thread_local const char* g_thread_last_api = "<none>";

static PFN_vkEnumerateInstanceVersion g_enum_instance_version = nullptr;
static PFN_vkCreateInstance g_create_instance = nullptr;
static PFN_vkCreateDevice g_create_device = nullptr;
static PFN_vkGetPhysicalDeviceProperties g_get_physical_device_properties = nullptr;
static PFN_vkCreateShaderModule g_create_shader_module = nullptr;
static PFN_vkCreateGraphicsPipelines g_create_graphics_pipelines = nullptr;
static PFN_vkCreateComputePipelines g_create_compute_pipelines = nullptr;
static PFN_vkQueueSubmit g_queue_submit = nullptr;
static PFN_vkQueueSubmit2KHR g_queue_submit2_khr = nullptr;
static PFN_vkQueuePresentKHR g_queue_present_khr = nullptr;
static PFN_vkEndCommandBuffer g_end_command_buffer = nullptr;
static PFN_vkCmdPushDescriptorSetKHR g_cmd_push_descriptor_set_khr = nullptr;
static PFN_vkCmdPipelineBarrier2KHR g_cmd_pipeline_barrier2_khr = nullptr;
static PFN_vkCmdSetVertexInputEXT g_cmd_set_vertex_input_ext = nullptr;
static PFN_vkCmdBeginRenderPass g_cmd_begin_render_pass = nullptr;
static PFN_vkCmdEndRenderPass g_cmd_end_render_pass = nullptr;
static PFN_vkCmdBindPipeline g_cmd_bind_pipeline = nullptr;
static PFN_vkCmdDraw g_cmd_draw = nullptr;
static PFN_vkCmdDrawIndexed g_cmd_draw_indexed = nullptr;
static PFN_vkCmdDispatch g_cmd_dispatch = nullptr;
static PFN_vkCmdBeginRendering g_cmd_begin_rendering = nullptr;
static PFN_vkCmdEndRendering g_cmd_end_rendering = nullptr;

static volatile LONG g_shader_module_calls = 0;
static volatile LONG g_graphics_pipeline_calls = 0;
static volatile LONG g_compute_pipeline_calls = 0;
static volatile LONG g_queue_submit_calls = 0;
static volatile LONG g_queue_submit2_calls = 0;
static volatile LONG g_queue_present_calls = 0;
static volatile LONG g_end_command_buffer_calls = 0;
static volatile LONG g_push_descriptor_calls = 0;
static volatile LONG g_pipeline_barrier2_calls = 0;
static volatile LONG g_vertex_input_calls = 0;
static volatile LONG g_begin_render_pass_calls = 0;
static volatile LONG g_end_render_pass_calls = 0;
static volatile LONG g_bind_pipeline_calls = 0;
static volatile LONG g_draw_calls = 0;
static volatile LONG g_draw_indexed_calls = 0;
static volatile LONG g_dispatch_calls = 0;
static volatile LONG g_begin_rendering_calls = 0;
static volatile LONG g_end_rendering_calls = 0;

static void BuildSiblingPath(const wchar_t* filename, wchar_t* output, DWORD capacity) {
    output[0] = L'\0';
    if (!g_self || !GetModuleFileNameW(g_self, output, capacity)) return;
    wchar_t* slash = wcsrchr(output, L'\\');
    if (!slash) slash = wcsrchr(output, L'/');
    if (!slash) {
        output[0] = L'\0';
        return;
    }
    *(slash + 1) = L'\0';
    if (wcslen(output) < capacity) wcsncat_s(output, capacity, filename, _TRUNCATE);
}

static void LogLine(const char* text) {
    wchar_t log_path[MAX_PATH]{};
    BuildSiblingPath(L"VK3to2.log", log_path, MAX_PATH);
    if (!log_path[0]) return;
    HANDLE file = CreateFileW(log_path, FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME st{};
    GetLocalTime(&st);
    char line[1400]{};
    _snprintf_s(line, sizeof(line), _TRUNCATE,
                "[%02u:%02u:%02u.%03u] [tid=%lu] %s\r\n",
                st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
                static_cast<unsigned long>(GetCurrentThreadId()), text ? text : "");
    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(strlen(line)), &written, nullptr);
    CloseHandle(file);
}

static void LogFormat(const char* format, ...) {
    char message[1200]{};
    va_list args;
    va_start(args, format);
    _vsnprintf_s(message, sizeof(message), _TRUNCATE, format, args);
    va_end(args);
    LogLine(message);
}

static void MarkApi(const char* name) {
    g_thread_last_api = name ? name : "<null>";
    InterlockedExchange(&g_global_last_tid, static_cast<LONG>(GetCurrentThreadId()));
    InterlockedExchangePointer(&g_global_last_api, const_cast<char*>(g_thread_last_api));
}

static bool SampleCall(LONG id, LONG first = 64, LONG interval = 1000) {
    if (!g_trace_sampled_calls) return false;
    return id <= first || (interval > 0 && (id % interval) == 0);
}

static void LogVersion(const char* label, std::uint32_t version) {
    const std::uint32_t major = (version >> 22) & 0x7f;
    const std::uint32_t minor = (version >> 12) & 0x3ff;
    const std::uint32_t patch = version & 0xfff;
    LogFormat("AUDIT %s=%u.%u.%u raw=0x%08x", label, major, minor, patch, version);
}

static void LogPNextChain(const void* pNext, const char* owner) {
    const auto* node = reinterpret_cast<const VkBaseInStructureMini*>(pNext);
    unsigned index = 0;
    while (node && index < 64) {
        LogFormat("AUDIT %s.pNext[%u].sType=%u", owner, index, node->sType);
        node = node->pNext;
        ++index;
    }
    if (node) LogFormat("AUDIT %s.pNext truncated after 64 nodes", owner);
}

static void LoadOptions() {
    wchar_t ini_path[MAX_PATH]{};
    BuildSiblingPath(L"VK3to2.ini", ini_path, MAX_PATH);
    if (!ini_path[0]) return;
    g_trace_sampled_calls = GetPrivateProfileIntW(L"trace", L"sampled_calls", 1, ini_path) != 0;
    g_trace_nvidia_exceptions = GetPrivateProfileIntW(L"trace", L"nvidia_exceptions", 1, ini_path) != 0;
    g_serialize_pipelines = GetPrivateProfileIntW(L"patches", L"serialize_pipelines", 0, ini_path) != 0;
    g_disable_pipeline_cache = GetPrivateProfileIntW(L"patches", L"disable_pipeline_cache", 0, ini_path) != 0;
}

static LONG CALLBACK NvidiaExceptionHandler(PEXCEPTION_POINTERS info) {
    if (!g_trace_nvidia_exceptions || !info || !info->ExceptionRecord) return EXCEPTION_CONTINUE_SEARCH;
    if (info->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;

    if (!g_nvidia_module) g_nvidia_module = GetModuleHandleW(L"nvoglv64.dll");
    if (!g_nvidia_module) return EXCEPTION_CONTINUE_SEARCH;

    MEMORY_BASIC_INFORMATION mbi{};
    if (!VirtualQuery(info->ExceptionRecord->ExceptionAddress, &mbi, sizeof(mbi))) return EXCEPTION_CONTINUE_SEARCH;
    if (mbi.AllocationBase != g_nvidia_module) return EXCEPTION_CONTINUE_SEARCH;

    const LONG fault_id = InterlockedIncrement(&g_exception_log_count);
    if (fault_id <= 32) {
        const ULONG_PTR access = info->ExceptionRecord->NumberParameters > 0 ? info->ExceptionRecord->ExceptionInformation[0] : 0;
        const ULONG_PTR address = info->ExceptionRecord->NumberParameters > 1 ? info->ExceptionRecord->ExceptionInformation[1] : 0;
        const auto* global_api = reinterpret_cast<const char*>(InterlockedCompareExchangePointer(&g_global_last_api, nullptr, nullptr));
        const LONG global_tid = InterlockedCompareExchange(&g_global_last_tid, 0, 0);
        const auto offset = reinterpret_cast<std::uintptr_t>(info->ExceptionRecord->ExceptionAddress) -
                            reinterpret_cast<std::uintptr_t>(g_nvidia_module);
        LogFormat("NVIDIA_EXCEPTION #%ld code=0x%08lx rip=%p nv_offset=0x%llx access=%llu fault=%p thread.last_api=%s global.last_api=%s global.last_tid=%ld",
                  fault_id,
                  static_cast<unsigned long>(info->ExceptionRecord->ExceptionCode),
                  info->ExceptionRecord->ExceptionAddress,
                  static_cast<unsigned long long>(offset),
                  static_cast<unsigned long long>(access),
                  reinterpret_cast<void*>(address),
                  g_thread_last_api ? g_thread_last_api : "<none>",
                  global_api ? global_api : "<none>",
                  global_tid);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static BOOL CALLBACK InitializeRealVulkan(PINIT_ONCE, PVOID, PVOID*) {
    wchar_t system_dir[MAX_PATH]{};
    const UINT length = GetSystemDirectoryW(system_dir, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        LogLine("ERROR GetSystemDirectoryW failed");
        return TRUE;
    }
    wchar_t real_path[MAX_PATH]{};
    wcscpy_s(real_path, system_dir);
    wcsncat_s(real_path, L"\\vulkan-1.dll", _TRUNCATE);
    g_real_vulkan = LoadLibraryW(real_path);
    if (!g_real_vulkan) {
        LogLine("ERROR could not load System32\\vulkan-1.dll");
        return TRUE;
    }
    g_real_gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(g_real_vulkan, "vkGetInstanceProcAddr"));
    g_real_gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(GetProcAddress(g_real_vulkan, "vkGetDeviceProcAddr"));
    LoadOptions();
    if (g_trace_nvidia_exceptions) g_veh_handle = AddVectoredExceptionHandler(1, NvidiaExceptionHandler);
    if (!g_real_gipa) {
        LogLine("ERROR real vkGetInstanceProcAddr export is missing");
    } else {
        LogLine("============================================================");
        LogLine("VK3to2 Build 02 initialized: execution + NVIDIA crash correlation");
        LogLine("Real loader: %SystemRoot%\\System32\\vulkan-1.dll");
        LogFormat("OPTIONS trace.sampled_calls=%d trace.nvidia_exceptions=%d", g_trace_sampled_calls ? 1 : 0, g_trace_nvidia_exceptions ? 1 : 0);
        LogFormat("OPTIONS patches.serialize_pipelines=%d patches.disable_pipeline_cache=%d", g_serialize_pipelines ? 1 : 0, g_disable_pipeline_cache ? 1 : 0);
    }
    return TRUE;
}

static bool EnsureRealVulkan() {
    InitOnceExecuteOnce(&g_init_once, InitializeRealVulkan, nullptr, nullptr);
    return g_real_vulkan != nullptr && g_real_gipa != nullptr;
}

static VkResult WINAPI Audit_vkEnumerateInstanceVersion(std::uint32_t* version) {
    MarkApi("vkEnumerateInstanceVersion");
    const VkResult result = g_enum_instance_version ? g_enum_instance_version(version) : -3;
    LogFormat("CALL vkEnumerateInstanceVersion RETURN result=%d", result);
    if (result == 0 && version) LogVersion("loader.instanceVersion", *version);
    return result;
}

static VkResult WINAPI Audit_vkCreateInstance(const VkInstanceCreateInfoMini* info, const void* allocator, VkInstance* instance) {
    MarkApi("vkCreateInstance");
    LogLine("CALL vkCreateInstance ENTER");
    if (info) {
        if (info->pApplicationInfo) {
            LogVersion("requested.apiVersion", info->pApplicationInfo->apiVersion);
            LogFormat("AUDIT application=%s engine=%s",
                      info->pApplicationInfo->pApplicationName ? info->pApplicationInfo->pApplicationName : "<null>",
                      info->pApplicationInfo->pEngineName ? info->pApplicationInfo->pEngineName : "<null>");
        }
        LogFormat("AUDIT instance.extensions.count=%u", info->enabledExtensionCount);
        for (std::uint32_t i = 0; i < info->enabledExtensionCount; ++i) {
            LogFormat("AUDIT instance.extension[%u]=%s", i,
                      info->ppEnabledExtensionNames && info->ppEnabledExtensionNames[i] ? info->ppEnabledExtensionNames[i] : "<null>");
        }
        LogPNextChain(info->pNext, "VkInstanceCreateInfo");
    }
    const VkResult result = g_create_instance ? g_create_instance(info, allocator, instance) : -3;
    LogFormat("CALL vkCreateInstance RETURN result=%d", result);
    return result;
}

static VkResult WINAPI Audit_vkCreateDevice(VkPhysicalDevice physicalDevice, const VkDeviceCreateInfoMini* info, const void* allocator, VkDevice* device) {
    MarkApi("vkCreateDevice");
    LogLine("CALL vkCreateDevice ENTER");
    if (info) {
        LogFormat("AUDIT device.extensions.count=%u", info->enabledExtensionCount);
        for (std::uint32_t i = 0; i < info->enabledExtensionCount; ++i) {
            LogFormat("AUDIT device.extension[%u]=%s", i,
                      info->ppEnabledExtensionNames && info->ppEnabledExtensionNames[i] ? info->ppEnabledExtensionNames[i] : "<null>");
        }
        LogPNextChain(info->pNext, "VkDeviceCreateInfo");
    }
    const VkResult result = g_create_device ? g_create_device(physicalDevice, info, allocator, device) : -3;
    LogFormat("CALL vkCreateDevice RETURN result=%d", result);
    return result;
}

static void WINAPI Audit_vkGetPhysicalDeviceProperties(VkPhysicalDevice physicalDevice, void* properties) {
    MarkApi("vkGetPhysicalDeviceProperties");
    if (g_get_physical_device_properties) g_get_physical_device_properties(physicalDevice, properties);
    if (properties) {
        const auto* p = reinterpret_cast<const VkPhysicalDevicePropertiesPrefix*>(properties);
        LogFormat("AUDIT physicalDevice name=%s vendor=0x%04x device=0x%04x driverVersion=0x%08x",
                  p->deviceName, p->vendorID, p->deviceID, p->driverVersion);
        LogVersion("physicalDevice.apiVersion", p->apiVersion);
    }
}

static VkResult WINAPI Audit_vkCreateShaderModule(VkDevice device, const void* info, const void* allocator, VkShaderModule* module) {
    MarkApi("vkCreateShaderModule");
    const LONG id = InterlockedIncrement(&g_shader_module_calls);
    LogFormat("TRACE shaderModule #%ld ENTER", id);
    const VkResult result = g_create_shader_module ? g_create_shader_module(device, info, allocator, module) : -3;
    LogFormat("TRACE shaderModule #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkCreateGraphicsPipelines(VkDevice device, VkPipelineCache cache, std::uint32_t count, const void* infos, const void* allocator, VkPipeline* pipelines) {
    MarkApi("vkCreateGraphicsPipelines");
    const LONG id = InterlockedIncrement(&g_graphics_pipeline_calls);
    const VkPipelineCache forwarded_cache = g_disable_pipeline_cache ? 0 : cache;
    LogFormat("TRACE graphicsPipelines #%ld ENTER count=%u cache=0x%llx forwarded_cache=0x%llx",
              id, count, static_cast<unsigned long long>(cache), static_cast<unsigned long long>(forwarded_cache));
    if (g_serialize_pipelines) AcquireSRWLockExclusive(&g_pipeline_lock);
    const VkResult result = g_create_graphics_pipelines ? g_create_graphics_pipelines(device, forwarded_cache, count, infos, allocator, pipelines) : -3;
    if (g_serialize_pipelines) ReleaseSRWLockExclusive(&g_pipeline_lock);
    LogFormat("TRACE graphicsPipelines #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkCreateComputePipelines(VkDevice device, VkPipelineCache cache, std::uint32_t count, const void* infos, const void* allocator, VkPipeline* pipelines) {
    MarkApi("vkCreateComputePipelines");
    const LONG id = InterlockedIncrement(&g_compute_pipeline_calls);
    const VkPipelineCache forwarded_cache = g_disable_pipeline_cache ? 0 : cache;
    LogFormat("TRACE computePipelines #%ld ENTER count=%u cache=0x%llx forwarded_cache=0x%llx",
              id, count, static_cast<unsigned long long>(cache), static_cast<unsigned long long>(forwarded_cache));
    if (g_serialize_pipelines) AcquireSRWLockExclusive(&g_pipeline_lock);
    const VkResult result = g_create_compute_pipelines ? g_create_compute_pipelines(device, forwarded_cache, count, infos, allocator, pipelines) : -3;
    if (g_serialize_pipelines) ReleaseSRWLockExclusive(&g_pipeline_lock);
    LogFormat("TRACE computePipelines #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkQueueSubmit(VkQueue queue, std::uint32_t count, const void* submits, VkFence fence) {
    MarkApi("vkQueueSubmit");
    const LONG id = InterlockedIncrement(&g_queue_submit_calls);
    if (SampleCall(id, 32, 100)) LogFormat("TRACE queueSubmit #%ld ENTER submitCount=%u", id, count);
    const VkResult result = g_queue_submit ? g_queue_submit(queue, count, submits, fence) : -3;
    if (SampleCall(id, 32, 100)) LogFormat("TRACE queueSubmit #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkQueueSubmit2KHR(VkQueue queue, std::uint32_t count, const void* submits, VkFence fence) {
    MarkApi("vkQueueSubmit2KHR");
    const LONG id = InterlockedIncrement(&g_queue_submit2_calls);
    if (SampleCall(id, 32, 100)) LogFormat("TRACE queueSubmit2KHR #%ld ENTER submitCount=%u", id, count);
    const VkResult result = g_queue_submit2_khr ? g_queue_submit2_khr(queue, count, submits, fence) : -3;
    if (SampleCall(id, 32, 100)) LogFormat("TRACE queueSubmit2KHR #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkQueuePresentKHR(VkQueue queue, const void* info) {
    MarkApi("vkQueuePresentKHR");
    const LONG id = InterlockedIncrement(&g_queue_present_calls);
    if (SampleCall(id, 32, 100)) LogFormat("TRACE queuePresentKHR #%ld ENTER", id);
    const VkResult result = g_queue_present_khr ? g_queue_present_khr(queue, info) : -3;
    if (SampleCall(id, 32, 100)) LogFormat("TRACE queuePresentKHR #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkEndCommandBuffer(VkCommandBuffer commandBuffer) {
    MarkApi("vkEndCommandBuffer");
    const LONG id = InterlockedIncrement(&g_end_command_buffer_calls);
    if (SampleCall(id, 32, 100)) LogFormat("TRACE endCommandBuffer #%ld ENTER", id);
    const VkResult result = g_end_command_buffer ? g_end_command_buffer(commandBuffer) : -3;
    if (SampleCall(id, 32, 100)) LogFormat("TRACE endCommandBuffer #%ld RETURN result=%d", id, result);
    return result;
}

static void WINAPI Audit_vkCmdPushDescriptorSetKHR(VkCommandBuffer commandBuffer, std::uint32_t bindPoint, VkPipelineLayout layout,
                                                    std::uint32_t set, std::uint32_t writeCount, const void* writes) {
    MarkApi("vkCmdPushDescriptorSetKHR");
    const LONG id = InterlockedIncrement(&g_push_descriptor_calls);
    if (SampleCall(id, 32, 500)) LogFormat("TRACE pushDescriptor #%ld writes=%u set=%u", id, writeCount, set);
    if (g_cmd_push_descriptor_set_khr) g_cmd_push_descriptor_set_khr(commandBuffer, bindPoint, layout, set, writeCount, writes);
}

static void WINAPI Audit_vkCmdPipelineBarrier2KHR(VkCommandBuffer commandBuffer, const void* dependencyInfo) {
    MarkApi("vkCmdPipelineBarrier2KHR");
    const LONG id = InterlockedIncrement(&g_pipeline_barrier2_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE pipelineBarrier2KHR #%ld", id);
    if (g_cmd_pipeline_barrier2_khr) g_cmd_pipeline_barrier2_khr(commandBuffer, dependencyInfo);
}

static void WINAPI Audit_vkCmdSetVertexInputEXT(VkCommandBuffer commandBuffer, std::uint32_t bindingCount, const void* bindings,
                                                std::uint32_t attributeCount, const void* attributes) {
    MarkApi("vkCmdSetVertexInputEXT");
    const LONG id = InterlockedIncrement(&g_vertex_input_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE setVertexInputEXT #%ld bindings=%u attributes=%u", id, bindingCount, attributeCount);
    if (g_cmd_set_vertex_input_ext) g_cmd_set_vertex_input_ext(commandBuffer, bindingCount, bindings, attributeCount, attributes);
}

static void WINAPI Audit_vkCmdBeginRenderPass(VkCommandBuffer commandBuffer, const void* beginInfo, std::uint32_t contents) {
    MarkApi("vkCmdBeginRenderPass");
    const LONG id = InterlockedIncrement(&g_begin_render_pass_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE beginRenderPass #%ld contents=%u", id, contents);
    if (g_cmd_begin_render_pass) g_cmd_begin_render_pass(commandBuffer, beginInfo, contents);
}

static void WINAPI Audit_vkCmdEndRenderPass(VkCommandBuffer commandBuffer) {
    MarkApi("vkCmdEndRenderPass");
    const LONG id = InterlockedIncrement(&g_end_render_pass_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE endRenderPass #%ld", id);
    if (g_cmd_end_render_pass) g_cmd_end_render_pass(commandBuffer);
}

static void WINAPI Audit_vkCmdBindPipeline(VkCommandBuffer commandBuffer, std::uint32_t bindPoint, VkPipeline pipeline) {
    MarkApi("vkCmdBindPipeline");
    const LONG id = InterlockedIncrement(&g_bind_pipeline_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE bindPipeline #%ld bindPoint=%u pipeline=0x%llx", id, bindPoint, static_cast<unsigned long long>(pipeline));
    if (g_cmd_bind_pipeline) g_cmd_bind_pipeline(commandBuffer, bindPoint, pipeline);
}

static void WINAPI Audit_vkCmdDraw(VkCommandBuffer commandBuffer, std::uint32_t vertexCount, std::uint32_t instanceCount,
                                   std::uint32_t firstVertex, std::uint32_t firstInstance) {
    MarkApi("vkCmdDraw");
    const LONG id = InterlockedIncrement(&g_draw_calls);
    if (SampleCall(id, 32, 1000)) LogFormat("TRACE draw #%ld vertices=%u instances=%u", id, vertexCount, instanceCount);
    if (g_cmd_draw) g_cmd_draw(commandBuffer, vertexCount, instanceCount, firstVertex, firstInstance);
}

static void WINAPI Audit_vkCmdDrawIndexed(VkCommandBuffer commandBuffer, std::uint32_t indexCount, std::uint32_t instanceCount,
                                          std::uint32_t firstIndex, std::int32_t vertexOffset, std::uint32_t firstInstance) {
    MarkApi("vkCmdDrawIndexed");
    const LONG id = InterlockedIncrement(&g_draw_indexed_calls);
    if (SampleCall(id, 32, 1000)) LogFormat("TRACE drawIndexed #%ld indices=%u instances=%u", id, indexCount, instanceCount);
    if (g_cmd_draw_indexed) g_cmd_draw_indexed(commandBuffer, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
}

static void WINAPI Audit_vkCmdDispatch(VkCommandBuffer commandBuffer, std::uint32_t x, std::uint32_t y, std::uint32_t z) {
    MarkApi("vkCmdDispatch");
    const LONG id = InterlockedIncrement(&g_dispatch_calls);
    if (SampleCall(id, 32, 500)) LogFormat("TRACE dispatch #%ld groups=%u,%u,%u", id, x, y, z);
    if (g_cmd_dispatch) g_cmd_dispatch(commandBuffer, x, y, z);
}

static void WINAPI Audit_vkCmdBeginRendering(VkCommandBuffer commandBuffer, const void* renderingInfo) {
    MarkApi("vkCmdBeginRendering/KHR");
    const LONG id = InterlockedIncrement(&g_begin_rendering_calls);
    if (SampleCall(id, 32, 500)) LogFormat("TRACE beginRendering #%ld", id);
    if (g_cmd_begin_rendering) g_cmd_begin_rendering(commandBuffer, renderingInfo);
}

static void WINAPI Audit_vkCmdEndRendering(VkCommandBuffer commandBuffer) {
    MarkApi("vkCmdEndRendering/KHR");
    const LONG id = InterlockedIncrement(&g_end_rendering_calls);
    if (SampleCall(id, 32, 500)) LogFormat("TRACE endRendering #%ld", id);
    if (g_cmd_end_rendering) g_cmd_end_rendering(commandBuffer);
}

extern "C" __declspec(dllexport)
PFN_vkVoidFunction WINAPI vkGetDeviceProcAddr(VkDevice device, const char* name);

static PFN_vkVoidFunction MaybeInterceptInstance(const char* name, PFN_vkVoidFunction real) {
    if (!real || !name) return real;
    if (strcmp(name, "vkEnumerateInstanceVersion") == 0) {
        g_enum_instance_version = reinterpret_cast<PFN_vkEnumerateInstanceVersion>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkEnumerateInstanceVersion);
    }
    if (strcmp(name, "vkCreateInstance") == 0) {
        g_create_instance = reinterpret_cast<PFN_vkCreateInstance>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCreateInstance);
    }
    if (strcmp(name, "vkCreateDevice") == 0) {
        g_create_device = reinterpret_cast<PFN_vkCreateDevice>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCreateDevice);
    }
    if (strcmp(name, "vkGetPhysicalDeviceProperties") == 0) {
        g_get_physical_device_properties = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkGetPhysicalDeviceProperties);
    }
    return real;
}

static PFN_vkVoidFunction MaybeInterceptDevice(const char* name, PFN_vkVoidFunction real) {
    if (!real || !name) return real;
    if (strcmp(name, "vkCreateShaderModule") == 0) {
        g_create_shader_module = reinterpret_cast<PFN_vkCreateShaderModule>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCreateShaderModule);
    }
    if (strcmp(name, "vkCreateGraphicsPipelines") == 0) {
        g_create_graphics_pipelines = reinterpret_cast<PFN_vkCreateGraphicsPipelines>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCreateGraphicsPipelines);
    }
    if (strcmp(name, "vkCreateComputePipelines") == 0) {
        g_create_compute_pipelines = reinterpret_cast<PFN_vkCreateComputePipelines>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCreateComputePipelines);
    }
    if (strcmp(name, "vkQueueSubmit") == 0) {
        g_queue_submit = reinterpret_cast<PFN_vkQueueSubmit>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkQueueSubmit);
    }
    if (strcmp(name, "vkQueueSubmit2KHR") == 0) {
        g_queue_submit2_khr = reinterpret_cast<PFN_vkQueueSubmit2KHR>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkQueueSubmit2KHR);
    }
    if (strcmp(name, "vkQueuePresentKHR") == 0) {
        g_queue_present_khr = reinterpret_cast<PFN_vkQueuePresentKHR>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkQueuePresentKHR);
    }
    if (strcmp(name, "vkEndCommandBuffer") == 0) {
        g_end_command_buffer = reinterpret_cast<PFN_vkEndCommandBuffer>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkEndCommandBuffer);
    }
    if (strcmp(name, "vkCmdPushDescriptorSetKHR") == 0) {
        g_cmd_push_descriptor_set_khr = reinterpret_cast<PFN_vkCmdPushDescriptorSetKHR>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdPushDescriptorSetKHR);
    }
    if (strcmp(name, "vkCmdPipelineBarrier2KHR") == 0) {
        g_cmd_pipeline_barrier2_khr = reinterpret_cast<PFN_vkCmdPipelineBarrier2KHR>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdPipelineBarrier2KHR);
    }
    if (strcmp(name, "vkCmdSetVertexInputEXT") == 0) {
        g_cmd_set_vertex_input_ext = reinterpret_cast<PFN_vkCmdSetVertexInputEXT>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdSetVertexInputEXT);
    }
    if (strcmp(name, "vkCmdBeginRenderPass") == 0) {
        g_cmd_begin_render_pass = reinterpret_cast<PFN_vkCmdBeginRenderPass>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdBeginRenderPass);
    }
    if (strcmp(name, "vkCmdEndRenderPass") == 0) {
        g_cmd_end_render_pass = reinterpret_cast<PFN_vkCmdEndRenderPass>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdEndRenderPass);
    }
    if (strcmp(name, "vkCmdBindPipeline") == 0) {
        g_cmd_bind_pipeline = reinterpret_cast<PFN_vkCmdBindPipeline>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdBindPipeline);
    }
    if (strcmp(name, "vkCmdDraw") == 0) {
        g_cmd_draw = reinterpret_cast<PFN_vkCmdDraw>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdDraw);
    }
    if (strcmp(name, "vkCmdDrawIndexed") == 0) {
        g_cmd_draw_indexed = reinterpret_cast<PFN_vkCmdDrawIndexed>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdDrawIndexed);
    }
    if (strcmp(name, "vkCmdDispatch") == 0) {
        g_cmd_dispatch = reinterpret_cast<PFN_vkCmdDispatch>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdDispatch);
    }
    if (strcmp(name, "vkCmdBeginRendering") == 0 || strcmp(name, "vkCmdBeginRenderingKHR") == 0) {
        g_cmd_begin_rendering = reinterpret_cast<PFN_vkCmdBeginRendering>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdBeginRendering);
    }
    if (strcmp(name, "vkCmdEndRendering") == 0 || strcmp(name, "vkCmdEndRenderingKHR") == 0) {
        g_cmd_end_rendering = reinterpret_cast<PFN_vkCmdEndRendering>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdEndRendering);
    }
    return real;
}

static bool InterestingUnavailable(const char* name) {
    if (!name) return false;
    return strstr(name, "PipelineBarrier2") || strstr(name, "QueueSubmit2") ||
           strstr(name, "BeginRendering") || strstr(name, "EndRendering") ||
           strstr(name, "DeviceBufferMemoryRequirements") ||
           strstr(name, "DeviceImageMemoryRequirements") ||
           strstr(name, "DeviceImageSparseMemoryRequirements");
}

extern "C" __declspec(dllexport)
PFN_vkVoidFunction WINAPI vkGetInstanceProcAddr(VkInstance instance, const char* name) {
    if (!EnsureRealVulkan() || !name) return nullptr;
    if (strcmp(name, "vkGetInstanceProcAddr") == 0) return reinterpret_cast<PFN_vkVoidFunction>(&vkGetInstanceProcAddr);
    if (strcmp(name, "vkGetDeviceProcAddr") == 0) return reinterpret_cast<PFN_vkVoidFunction>(&vkGetDeviceProcAddr);
    PFN_vkVoidFunction real = g_real_gipa(instance, name);
    if (!real && InterestingUnavailable(name)) LogFormat("UNAVAILABLE GIPA %s", name);
    return MaybeInterceptInstance(name, real);
}

extern "C" __declspec(dllexport)
PFN_vkVoidFunction WINAPI vkGetDeviceProcAddr(VkDevice device, const char* name) {
    if (!EnsureRealVulkan() || !name) return nullptr;
    if (strcmp(name, "vkGetDeviceProcAddr") == 0) return reinterpret_cast<PFN_vkVoidFunction>(&vkGetDeviceProcAddr);
    if (strcmp(name, "vkGetInstanceProcAddr") == 0) return reinterpret_cast<PFN_vkVoidFunction>(&vkGetInstanceProcAddr);
    if (!g_real_gdpa) {
        g_real_gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(g_real_gipa(nullptr, "vkGetDeviceProcAddr"));
        if (!g_real_gdpa) {
            LogLine("ERROR real vkGetDeviceProcAddr is unavailable");
            return nullptr;
        }
    }
    PFN_vkVoidFunction real = g_real_gdpa(device, name);
    if (!real && InterestingUnavailable(name)) LogFormat("UNAVAILABLE GDPA %s", name);
    return MaybeInterceptDevice(name, real);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
