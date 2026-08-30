#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstring>

// Minimal Vulkan ABI declarations. Milestone 00 intentionally avoids a Vulkan SDK
// dependency: the proxy only needs the two dispatch entry points used by shadPS4.
struct VkInstance_T;
struct VkDevice_T;
using VkInstance = VkInstance_T*;
using VkDevice = VkDevice_T*;
using PFN_vkVoidFunction = void (WINAPI*)();
using PFN_vkGetInstanceProcAddr = PFN_vkVoidFunction (WINAPI*)(VkInstance, const char*);
using PFN_vkGetDeviceProcAddr = PFN_vkVoidFunction (WINAPI*)(VkDevice, const char*);

static HMODULE g_self = nullptr;
static HMODULE g_real_vulkan = nullptr;
static PFN_vkGetInstanceProcAddr g_real_gipa = nullptr;
static PFN_vkGetDeviceProcAddr g_real_gdpa = nullptr;
static INIT_ONCE g_init_once = INIT_ONCE_STATIC_INIT;

static void BuildSiblingPath(const wchar_t* filename, wchar_t* output, DWORD capacity) {
    output[0] = L'\0';
    if (!g_self || !GetModuleFileNameW(g_self, output, capacity)) {
        return;
    }

    wchar_t* slash = wcsrchr(output, L'\\');
    if (!slash) {
        slash = wcsrchr(output, L'/');
    }
    if (!slash) {
        output[0] = L'\0';
        return;
    }

    *(slash + 1) = L'\0';
    const size_t used = wcslen(output);
    if (used < capacity) {
        wcsncat_s(output, capacity, filename, _TRUNCATE);
    }
}

static void LogLine(const char* text) {
    wchar_t log_path[MAX_PATH]{};
    BuildSiblingPath(L"VK3to2.log", log_path, MAX_PATH);
    if (!log_path[0]) {
        return;
    }

    HANDLE file = CreateFileW(log_path,
                              FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE,
                              nullptr,
                              OPEN_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL,
                              nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }

    SYSTEMTIME st{};
    GetLocalTime(&st);

    char line[1024]{};
    _snprintf_s(line,
                sizeof(line),
                _TRUNCATE,
                "[%02u:%02u:%02u.%03u] %s\r\n",
                st.wHour,
                st.wMinute,
                st.wSecond,
                st.wMilliseconds,
                text ? text : "");

    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(strlen(line)), &written, nullptr);
    CloseHandle(file);
}

static BOOL CALLBACK InitializeRealVulkan(PINIT_ONCE, PVOID, PVOID*) {
    wchar_t system_dir[MAX_PATH]{};
    const UINT length = GetSystemDirectoryW(system_dir, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        LogLine("ERROR: GetSystemDirectoryW failed");
        return TRUE;
    }

    wchar_t real_path[MAX_PATH]{};
    wcscpy_s(real_path, system_dir);
    wcsncat_s(real_path, L"\\vulkan-1.dll", _TRUNCATE);

    g_real_vulkan = LoadLibraryW(real_path);
    if (!g_real_vulkan) {
        LogLine("ERROR: could not load System32\\vulkan-1.dll");
        return TRUE;
    }

    g_real_gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
        GetProcAddress(g_real_vulkan, "vkGetInstanceProcAddr"));
    g_real_gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
        GetProcAddress(g_real_vulkan, "vkGetDeviceProcAddr"));

    if (!g_real_gipa) {
        LogLine("ERROR: real vkGetInstanceProcAddr export is missing");
    } else {
        LogLine("VK3to2 Milestone 00 initialized: transparent Vulkan dispatch proxy");
        LogLine("Real loader: %SystemRoot%\\System32\\vulkan-1.dll");
        LogLine("Compatibility patches: NONE");
    }

    return TRUE;
}

static bool EnsureRealVulkan() {
    InitOnceExecuteOnce(&g_init_once, InitializeRealVulkan, nullptr, nullptr);
    return g_real_vulkan != nullptr && g_real_gipa != nullptr;
}

extern "C" PFN_vkVoidFunction WINAPI vkGetDeviceProcAddr(VkDevice device, const char* name);

extern "C" __declspec(dllexport)
PFN_vkVoidFunction WINAPI vkGetInstanceProcAddr(VkInstance instance, const char* name) {
    if (!EnsureRealVulkan() || !name) {
        return nullptr;
    }

    char message[768]{};
    _snprintf_s(message, sizeof(message), _TRUNCATE,
                "GIPA  %s", name);
    LogLine(message);

    // Keep future interception centralized in these two dispatch gates.
    if (strcmp(name, "vkGetInstanceProcAddr") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&vkGetInstanceProcAddr);
    }
    if (strcmp(name, "vkGetDeviceProcAddr") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&vkGetDeviceProcAddr);
    }

    return g_real_gipa(instance, name);
}

extern "C" __declspec(dllexport)
PFN_vkVoidFunction WINAPI vkGetDeviceProcAddr(VkDevice device, const char* name) {
    if (!EnsureRealVulkan() || !name) {
        return nullptr;
    }

    char message[768]{};
    _snprintf_s(message, sizeof(message), _TRUNCATE,
                "GDPA  %s", name);
    LogLine(message);

    if (strcmp(name, "vkGetDeviceProcAddr") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&vkGetDeviceProcAddr);
    }
    if (strcmp(name, "vkGetInstanceProcAddr") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&vkGetInstanceProcAddr);
    }

    if (!g_real_gdpa) {
        // A Vulkan loader should export GDPA, but fall back through GIPA if needed.
        const auto gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
            g_real_gipa(nullptr, "vkGetDeviceProcAddr"));
        if (!gdpa) {
            LogLine("ERROR: real vkGetDeviceProcAddr is unavailable");
            return nullptr;
        }
        g_real_gdpa = gdpa;
    }

    return g_real_gdpa(device, name);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
