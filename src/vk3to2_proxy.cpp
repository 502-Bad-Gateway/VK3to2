#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdarg>
#include <cstdio>
#include <cstring>

// VK3to2 deliberately keeps a tiny Vulkan ABI surface instead of depending on
// a Vulkan SDK. Build 01 is diagnostic only: every intercepted call is forwarded
// unchanged to the real Windows Vulkan loader.
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
using PFN_vkEndCommandBuffer = VkResult (WINAPI*)(VkCommandBuffer);
using PFN_vkCmdPushDescriptorSetKHR = void (WINAPI*)(VkCommandBuffer, std::uint32_t, VkPipelineLayout, std::uint32_t, std::uint32_t, const void*);
using PFN_vkCmdBeginRendering = void (WINAPI*)(VkCommandBuffer, const void*);
using PFN_vkCmdEndRendering = void (WINAPI*)(VkCommandBuffer);

static HMODULE g_self = nullptr;
static HMODULE g_real_vulkan = nullptr;
static PFN_vkGetInstanceProcAddr g_real_gipa = nullptr;
static PFN_vkGetDeviceProcAddr g_real_gdpa = nullptr;
static INIT_ONCE g_init_once = INIT_ONCE_STATIC_INIT;

static PFN_vkEnumerateInstanceVersion g_enum_instance_version = nullptr;
static PFN_vkCreateInstance g_create_instance = nullptr;
static PFN_vkCreateDevice g_create_device = nullptr;
static PFN_vkGetPhysicalDeviceProperties g_get_physical_device_properties = nullptr;
static PFN_vkCreateShaderModule g_create_shader_module = nullptr;
static PFN_vkCreateGraphicsPipelines g_create_graphics_pipelines = nullptr;
static PFN_vkCreateComputePipelines g_create_compute_pipelines = nullptr;
static PFN_vkQueueSubmit g_queue_submit = nullptr;
static PFN_vkEndCommandBuffer g_end_command_buffer = nullptr;
static PFN_vkCmdPushDescriptorSetKHR g_cmd_push_descriptor_set_khr = nullptr;
static PFN_vkCmdBeginRendering g_cmd_begin_rendering = nullptr;
static PFN_vkCmdEndRendering g_cmd_end_rendering = nullptr;

static volatile LONG g_shader_module_calls = 0;
static volatile LONG g_graphics_pipeline_calls = 0;
static volatile LONG g_compute_pipeline_calls = 0;
static volatile LONG g_queue_submit_calls = 0;
static volatile LONG g_end_command_buffer_calls = 0;
static volatile LONG g_push_descriptor_calls = 0;
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
    char line[1200]{};
    _snprintf_s(line, sizeof(line), _TRUNCATE,
                "[%02u:%02u:%02u.%03u] %s\r\n",
                st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
                text ? text : "");
    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(strlen(line)), &written, nullptr);
    CloseHandle(file);
}

static void LogFormat(const char* format, ...) {
    char message[1024]{};
    va_list args;
    va_start(args, format);
    _vsnprintf_s(message, sizeof(message), _TRUNCATE, format, args);
    va_end(args);
    LogLine(message);
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
    if (!g_real_gipa) {
        LogLine("ERROR real vkGetInstanceProcAddr export is missing");
    } else {
        LogLine("============================================================");
        LogLine("VK3to2 Build 01 initialized: capability + pipeline trace audit");
        LogLine("Real loader: %SystemRoot%\\System32\\vulkan-1.dll");
        LogLine("Compatibility patches: NONE (diagnostic pass-through only)");
    }
    return TRUE;
}

static bool EnsureRealVulkan() {
    InitOnceExecuteOnce(&g_init_once, InitializeRealVulkan, nullptr, nullptr);
    return g_real_vulkan != nullptr && g_real_gipa != nullptr;
}

static VkResult WINAPI Audit_vkEnumerateInstanceVersion(std::uint32_t* version) {
    const VkResult result = g_enum_instance_version ? g_enum_instance_version(version) : -3;
    LogFormat("CALL vkEnumerateInstanceVersion RETURN result=%d", result);
    if (result == 0 && version) LogVersion("loader.instanceVersion", *version);
    return result;
}

static VkResult WINAPI Audit_vkCreateInstance(const VkInstanceCreateInfoMini* info, const void* allocator, VkInstance* instance) {
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
    if (g_get_physical_device_properties) g_get_physical_device_properties(physicalDevice, properties);
    if (properties) {
        const auto* p = reinterpret_cast<const VkPhysicalDevicePropertiesPrefix*>(properties);
        LogFormat("AUDIT physicalDevice name=%s vendor=0x%04x device=0x%04x driverVersion=0x%08x",
                  p->deviceName, p->vendorID, p->deviceID, p->driverVersion);
        LogVersion("physicalDevice.apiVersion", p->apiVersion);
    }
}

static VkResult WINAPI Audit_vkCreateShaderModule(VkDevice device, const void* info, const void* allocator, VkShaderModule* module) {
    const LONG id = InterlockedIncrement(&g_shader_module_calls);
    LogFormat("TRACE shaderModule #%ld ENTER", id);
    const VkResult result = g_create_shader_module ? g_create_shader_module(device, info, allocator, module) : -3;
    LogFormat("TRACE shaderModule #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkCreateGraphicsPipelines(VkDevice device, VkPipelineCache cache, std::uint32_t count, const void* infos, const void* allocator, VkPipeline* pipelines) {
    const LONG id = InterlockedIncrement(&g_graphics_pipeline_calls);
    LogFormat("TRACE graphicsPipelines #%ld ENTER count=%u", id, count);
    const VkResult result = g_create_graphics_pipelines ? g_create_graphics_pipelines(device, cache, count, infos, allocator, pipelines) : -3;
    LogFormat("TRACE graphicsPipelines #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkCreateComputePipelines(VkDevice device, VkPipelineCache cache, std::uint32_t count, const void* infos, const void* allocator, VkPipeline* pipelines) {
    const LONG id = InterlockedIncrement(&g_compute_pipeline_calls);
    LogFormat("TRACE computePipelines #%ld ENTER count=%u", id, count);
    const VkResult result = g_create_compute_pipelines ? g_create_compute_pipelines(device, cache, count, infos, allocator, pipelines) : -3;
    LogFormat("TRACE computePipelines #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkQueueSubmit(VkQueue queue, std::uint32_t count, const void* submits, VkFence fence) {
    const LONG id = InterlockedIncrement(&g_queue_submit_calls);
    const bool log_this = id <= 20 || (id % 100) == 0;
    if (log_this) LogFormat("TRACE queueSubmit #%ld ENTER submitCount=%u", id, count);
    const VkResult result = g_queue_submit ? g_queue_submit(queue, count, submits, fence) : -3;
    if (log_this) LogFormat("TRACE queueSubmit #%ld RETURN result=%d", id, result);
    return result;
}

static VkResult WINAPI Audit_vkEndCommandBuffer(VkCommandBuffer commandBuffer) {
    const LONG id = InterlockedIncrement(&g_end_command_buffer_calls);
    const bool log_this = id <= 20 || (id % 100) == 0;
    if (log_this) LogFormat("TRACE endCommandBuffer #%ld ENTER", id);
    const VkResult result = g_end_command_buffer ? g_end_command_buffer(commandBuffer) : -3;
    if (log_this) LogFormat("TRACE endCommandBuffer #%ld RETURN result=%d", id, result);
    return result;
}

static void WINAPI Audit_vkCmdPushDescriptorSetKHR(VkCommandBuffer commandBuffer, std::uint32_t bindPoint, VkPipelineLayout layout,
                                                    std::uint32_t set, std::uint32_t writeCount, const void* writes) {
    const LONG id = InterlockedIncrement(&g_push_descriptor_calls);
    if (id <= 32 || (id % 500) == 0) LogFormat("TRACE pushDescriptor #%ld writes=%u set=%u", id, writeCount, set);
    if (g_cmd_push_descriptor_set_khr) g_cmd_push_descriptor_set_khr(commandBuffer, bindPoint, layout, set, writeCount, writes);
}

static void WINAPI Audit_vkCmdBeginRendering(VkCommandBuffer commandBuffer, const void* renderingInfo) {
    const LONG id = InterlockedIncrement(&g_begin_rendering_calls);
    if (id <= 32 || (id % 500) == 0) LogFormat("TRACE beginRendering #%ld", id);
    if (g_cmd_begin_rendering) g_cmd_begin_rendering(commandBuffer, renderingInfo);
}

static void WINAPI Audit_vkCmdEndRendering(VkCommandBuffer commandBuffer) {
    const LONG id = InterlockedIncrement(&g_end_rendering_calls);
    if (id <= 32 || (id % 500) == 0) LogFormat("TRACE endRendering #%ld", id);
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
    if (strcmp(name, "vkEndCommandBuffer") == 0) {
        g_end_command_buffer = reinterpret_cast<PFN_vkEndCommandBuffer>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkEndCommandBuffer);
    }
    if (strcmp(name, "vkCmdPushDescriptorSetKHR") == 0) {
        g_cmd_push_descriptor_set_khr = reinterpret_cast<PFN_vkCmdPushDescriptorSetKHR>(real);
        return reinterpret_cast<PFN_vkVoidFunction>(&Audit_vkCmdPushDescriptorSetKHR);
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

extern "C" __declspec(dllexport)
PFN_vkVoidFunction WINAPI vkGetInstanceProcAddr(VkInstance instance, const char* name) {
    if (!EnsureRealVulkan() || !name) return nullptr;
    if (strcmp(name, "vkGetInstanceProcAddr") == 0) return reinterpret_cast<PFN_vkVoidFunction>(&vkGetInstanceProcAddr);
    if (strcmp(name, "vkGetDeviceProcAddr") == 0) return reinterpret_cast<PFN_vkVoidFunction>(&vkGetDeviceProcAddr);
    PFN_vkVoidFunction real = g_real_gipa(instance, name);
    if (!real) LogFormat("UNAVAILABLE GIPA %s", name);
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
    if (!real) LogFormat("UNAVAILABLE GDPA %s", name);
    return MaybeInterceptDevice(name, real);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
