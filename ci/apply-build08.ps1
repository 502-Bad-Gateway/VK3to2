$ErrorActionPreference = 'Stop'

# Build 08 keeps the proven Build 07 null-depth repair intact and adds one
# independent experiment for DOAX3 01.00. The compatibility thread for 01.19
# points at a problematic compute shader; our 01.00 capture contains one guest
# compute program (0x03b537c5) with two SPIR-V permutations. Track shader-module
# content -> compute pipeline -> command-buffer binding, then optionally suppress
# dispatches only for those exact two captured SPIR-V modules.
& .\ci\apply-build07.ps1

$sourcePath = 'dist\vk3to2_build07.cpp'
$outPath = 'dist\vk3to2_build08.cpp'
$script:src = Get-Content -Raw -LiteralPath $sourcePath

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:src.Contains($old)) {
        throw "Build 08 patch anchor not found: $old"
    }
    $script:src = $script:src.Replace($old, $new)
}

# ABI definitions required to inspect shader-module and compute-pipeline inputs.
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

struct VkShaderModuleCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    SIZE_T codeSize;
    const std::uint32_t* pCode;
};

struct VkPipelineShaderStageCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    std::uint32_t stage;
    VkShaderModule module;
    const char* pName;
    const void* pSpecializationInfo;
};

struct VkComputePipelineCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    VkPipelineShaderStageCreateInfoMini stage;
    VkPipelineLayout layout;
    VkPipeline basePipelineHandle;
    std::int32_t basePipelineIndex;
};
'@

Replace-Required @'
static bool g_repair_null_depth = false;
static std::uint32_t g_repair_max_dimension = 8192;
'@ @'
static bool g_repair_null_depth = false;
static std::uint32_t g_repair_max_dimension = 8192;
static bool g_doax_compute_bypass = false;
'@

# Fixed-size tracking tables avoid allocations in the Vulkan hot path.
Replace-Required @'
static VkPhysicalDeviceMemoryPropertiesMini g_memory_properties{};
static bool g_memory_properties_valid = false;
'@ @'
static VkPhysicalDeviceMemoryPropertiesMini g_memory_properties{};
static bool g_memory_properties_valid = false;

struct ShaderHashRecord {
    bool used;
    VkShaderModule module;
    std::uint64_t hash;
};

struct ComputePipelineHashRecord {
    bool used;
    VkPipeline pipeline;
    std::uint64_t hash;
    bool doaxTarget;
};

struct CommandBufferComputeRecord {
    bool used;
    VkCommandBuffer commandBuffer;
    VkPipeline pipeline;
    std::uint64_t hash;
    bool doaxTarget;
};

static SRWLOCK g_compute_track_lock = SRWLOCK_INIT;
static ShaderHashRecord g_shader_hash_records[4096]{};
static ComputePipelineHashRecord g_compute_hash_records[2048]{};
static CommandBufferComputeRecord g_command_compute_records[256]{};
'@

# Runtime option. Hash matching makes the switch inert for every other shader.
Replace-Required @'
    g_repair_null_depth = GetPrivateProfileIntW(L"patches", L"repair_null_depth", 0, ini_path) != 0;
    const int repair_limit = GetPrivateProfileIntW(L"patches", L"repair_max_dimension", 8192, ini_path);
'@ @'
    g_repair_null_depth = GetPrivateProfileIntW(L"patches", L"repair_null_depth", 0, ini_path) != 0;
    g_doax_compute_bypass = GetPrivateProfileIntW(L"patches", L"doax_compute_bypass", 0, ini_path) != 0;
    const int repair_limit = GetPrivateProfileIntW(L"patches", L"repair_max_dimension", 8192, ini_path);
'@

$computeTracking = @'
static std::uint64_t HashShaderCode(const VkShaderModuleCreateInfoMini* info) {
    if (!info || !info->pCode || info->codeSize < 20 || info->codeSize > (32u * 1024u * 1024u)) return 0;
    const auto* bytes = reinterpret_cast<const unsigned char*>(info->pCode);
    std::uint64_t hash = 0xcbf29ce484222325ull;
    for (SIZE_T i = 0; i < info->codeSize; ++i) {
        hash ^= static_cast<std::uint64_t>(bytes[i]);
        hash *= 0x100000001b3ull;
    }
    return hash;
}

static bool IsDoaxCapturedComputeHash(std::uint64_t hash) {
    // DOAX3 01.00 cs_0x0000000003b537c5, two captured permutations.
    return hash == 0x7fa9bff1ccb6d98bull || hash == 0x2e7c73596899e13full;
}

static void RecordShaderHash(VkShaderModule module, std::uint64_t hash) {
    if (!module || !hash) return;
    AcquireSRWLockExclusive(&g_compute_track_lock);
    ShaderHashRecord* free_slot = nullptr;
    for (auto& record : g_shader_hash_records) {
        if (record.used && record.module == module) {
            record.hash = hash;
            ReleaseSRWLockExclusive(&g_compute_track_lock);
            return;
        }
        if (!record.used && !free_slot) free_slot = &record;
    }
    if (free_slot) {
        free_slot->used = true;
        free_slot->module = module;
        free_slot->hash = hash;
    }
    ReleaseSRWLockExclusive(&g_compute_track_lock);
}

static std::uint64_t LookupShaderHash(VkShaderModule module) {
    std::uint64_t hash = 0;
    AcquireSRWLockShared(&g_compute_track_lock);
    for (const auto& record : g_shader_hash_records) {
        if (record.used && record.module == module) {
            hash = record.hash;
            break;
        }
    }
    ReleaseSRWLockShared(&g_compute_track_lock);
    return hash;
}

static void ForgetShaderHash(VkShaderModule module) {
    AcquireSRWLockExclusive(&g_compute_track_lock);
    for (auto& record : g_shader_hash_records) {
        if (record.used && record.module == module) {
            record = {};
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_compute_track_lock);
}

static void RecordComputePipelineHash(VkPipeline pipeline, std::uint64_t hash) {
    if (!pipeline) return;
    AcquireSRWLockExclusive(&g_compute_track_lock);
    ComputePipelineHashRecord* free_slot = nullptr;
    for (auto& record : g_compute_hash_records) {
        if (record.used && record.pipeline == pipeline) {
            record.hash = hash;
            record.doaxTarget = IsDoaxCapturedComputeHash(hash);
            ReleaseSRWLockExclusive(&g_compute_track_lock);
            return;
        }
        if (!record.used && !free_slot) free_slot = &record;
    }
    if (free_slot) {
        free_slot->used = true;
        free_slot->pipeline = pipeline;
        free_slot->hash = hash;
        free_slot->doaxTarget = IsDoaxCapturedComputeHash(hash);
    }
    ReleaseSRWLockExclusive(&g_compute_track_lock);
}

static bool LookupComputePipelineHash(VkPipeline pipeline, std::uint64_t* outHash) {
    bool target = false;
    std::uint64_t hash = 0;
    AcquireSRWLockShared(&g_compute_track_lock);
    for (const auto& record : g_compute_hash_records) {
        if (record.used && record.pipeline == pipeline) {
            hash = record.hash;
            target = record.doaxTarget;
            break;
        }
    }
    ReleaseSRWLockShared(&g_compute_track_lock);
    if (outHash) *outHash = hash;
    return target;
}

static void ForgetComputePipelineHash(VkPipeline pipeline) {
    AcquireSRWLockExclusive(&g_compute_track_lock);
    for (auto& record : g_compute_hash_records) {
        if (record.used && record.pipeline == pipeline) {
            record = {};
            break;
        }
    }
    for (auto& record : g_command_compute_records) {
        if (record.used && record.pipeline == pipeline) record = {};
    }
    ReleaseSRWLockExclusive(&g_compute_track_lock);
}

static void SetCommandComputePipeline(VkCommandBuffer commandBuffer, VkPipeline pipeline) {
    if (!commandBuffer) return;
    std::uint64_t hash = 0;
    const bool target = LookupComputePipelineHash(pipeline, &hash);
    AcquireSRWLockExclusive(&g_compute_track_lock);
    CommandBufferComputeRecord* free_slot = nullptr;
    for (auto& record : g_command_compute_records) {
        if (record.used && record.commandBuffer == commandBuffer) {
            record.pipeline = pipeline;
            record.hash = hash;
            record.doaxTarget = target;
            ReleaseSRWLockExclusive(&g_compute_track_lock);
            return;
        }
        if (!record.used && !free_slot) free_slot = &record;
    }
    if (free_slot) {
        free_slot->used = true;
        free_slot->commandBuffer = commandBuffer;
        free_slot->pipeline = pipeline;
        free_slot->hash = hash;
        free_slot->doaxTarget = target;
    }
    ReleaseSRWLockExclusive(&g_compute_track_lock);
}

static bool CurrentCommandUsesDoaxCompute(VkCommandBuffer commandBuffer, VkPipeline* outPipeline,
                                          std::uint64_t* outHash) {
    bool target = false;
    VkPipeline pipeline = 0;
    std::uint64_t hash = 0;
    AcquireSRWLockShared(&g_compute_track_lock);
    for (const auto& record : g_command_compute_records) {
        if (record.used && record.commandBuffer == commandBuffer) {
            target = record.doaxTarget;
            pipeline = record.pipeline;
            hash = record.hash;
            break;
        }
    }
    ReleaseSRWLockShared(&g_compute_track_lock);
    if (outPipeline) *outPipeline = pipeline;
    if (outHash) *outHash = hash;
    return target;
}

'@
Replace-Required 'static VkResult WINAPI Audit_vkCreateShaderModule' ($computeTracking + 'static VkResult WINAPI Audit_vkCreateShaderModule')

# Fingerprint every shader module at creation time. This also makes a future
# DOAX3 01.19 capture easy to identify without changing shadPS4.
Replace-Required @'
static VkResult WINAPI Audit_vkCreateShaderModule(VkDevice device, const void* info, const void* allocator, VkShaderModule* module) {
    MarkApi("vkCreateShaderModule");
    const LONG id = InterlockedIncrement(&g_shader_module_calls);
    LogFormat("TRACE shaderModule #%ld ENTER", id);
    const VkResult result = g_create_shader_module ? g_create_shader_module(device, info, allocator, module) : -3;
    LogFormat("TRACE shaderModule #%ld RETURN result=%d", id, result);
    return result;
}
'@ @'
static VkResult WINAPI Audit_vkCreateShaderModule(VkDevice device, const void* info, const void* allocator, VkShaderModule* module) {
    MarkApi("vkCreateShaderModule");
    const LONG id = InterlockedIncrement(&g_shader_module_calls);
    const auto* create = reinterpret_cast<const VkShaderModuleCreateInfoMini*>(info);
    const std::uint64_t hash = HashShaderCode(create);
    const bool target = IsDoaxCapturedComputeHash(hash);
    LogFormat("TRACE shaderModule #%ld ENTER bytes=%llu fnv64=0x%016llx doaxTarget=%d", id,
              static_cast<unsigned long long>(create ? create->codeSize : 0),
              static_cast<unsigned long long>(hash), target ? 1 : 0);
    const VkResult result = g_create_shader_module ? g_create_shader_module(device, info, allocator, module) : -3;
    if (result == 0 && module && *module) {
        RecordShaderHash(*module, hash);
        if (target) {
            LogFormat("DOAX TARGET_MODULE module=0x%llx fnv64=0x%016llx bytes=%llu",
                      static_cast<unsigned long long>(*module), static_cast<unsigned long long>(hash),
                      static_cast<unsigned long long>(create ? create->codeSize : 0));
        }
    }
    LogFormat("TRACE shaderModule #%ld RETURN result=%d module=0x%llx", id, result,
              static_cast<unsigned long long>((module && result == 0) ? *module : 0));
    return result;
}
'@

# Map compute pipeline handles back to the shader-module fingerprint.
Replace-Required @'
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
'@ @'
static VkResult WINAPI Audit_vkCreateComputePipelines(VkDevice device, VkPipelineCache cache, std::uint32_t count, const void* infos, const void* allocator, VkPipeline* pipelines) {
    MarkApi("vkCreateComputePipelines");
    const LONG id = InterlockedIncrement(&g_compute_pipeline_calls);
    const VkPipelineCache forwarded_cache = g_disable_pipeline_cache ? 0 : cache;
    const auto* createInfos = reinterpret_cast<const VkComputePipelineCreateInfoMini*>(infos);
    LogFormat("TRACE computePipelines #%ld ENTER count=%u cache=0x%llx forwarded_cache=0x%llx",
              id, count, static_cast<unsigned long long>(cache), static_cast<unsigned long long>(forwarded_cache));
    if (g_serialize_pipelines) AcquireSRWLockExclusive(&g_pipeline_lock);
    const VkResult result = g_create_compute_pipelines ? g_create_compute_pipelines(device, forwarded_cache, count, infos, allocator, pipelines) : -3;
    if (g_serialize_pipelines) ReleaseSRWLockExclusive(&g_pipeline_lock);
    if (result == 0 && createInfos && pipelines) {
        for (std::uint32_t i = 0; i < count; ++i) {
            const std::uint64_t hash = LookupShaderHash(createInfos[i].stage.module);
            RecordComputePipelineHash(pipelines[i], hash);
            const bool target = IsDoaxCapturedComputeHash(hash);
            LogFormat("COMPUTE PIPELINE #%ld[%u] pipeline=0x%llx module=0x%llx fnv64=0x%016llx doaxTarget=%d",
                      id, i, static_cast<unsigned long long>(pipelines[i]),
                      static_cast<unsigned long long>(createInfos[i].stage.module),
                      static_cast<unsigned long long>(hash), target ? 1 : 0);
        }
    }
    LogFormat("TRACE computePipelines #%ld RETURN result=%d", id, result);
    return result;
}
'@

# Track the currently bound compute pipeline independently for each command buffer.
Replace-Required @'
static void WINAPI Audit_vkCmdBindPipeline(VkCommandBuffer commandBuffer, std::uint32_t bindPoint, VkPipeline pipeline) {
    MarkApi("vkCmdBindPipeline");
    const LONG id = InterlockedIncrement(&g_bind_pipeline_calls);
    if (SampleCall(id, 64, 500)) LogFormat("TRACE bindPipeline #%ld bindPoint=%u pipeline=0x%llx", id, bindPoint, static_cast<unsigned long long>(pipeline));
    if (g_cmd_bind_pipeline) g_cmd_bind_pipeline(commandBuffer, bindPoint, pipeline);
}
'@ @'
static void WINAPI Audit_vkCmdBindPipeline(VkCommandBuffer commandBuffer, std::uint32_t bindPoint, VkPipeline pipeline) {
    MarkApi("vkCmdBindPipeline");
    const LONG id = InterlockedIncrement(&g_bind_pipeline_calls);
    if (bindPoint == 1u) {
        SetCommandComputePipeline(commandBuffer, pipeline);
        std::uint64_t hash = 0;
        if (LookupComputePipelineHash(pipeline, &hash)) {
            LogFormat("DOAX TARGET_BIND cmd=%p pipeline=0x%llx fnv64=0x%016llx bypass=%d", commandBuffer,
                      static_cast<unsigned long long>(pipeline), static_cast<unsigned long long>(hash),
                      g_doax_compute_bypass ? 1 : 0);
        }
    }
    if (SampleCall(id, 64, 500)) LogFormat("TRACE bindPipeline #%ld bindPoint=%u pipeline=0x%llx", id, bindPoint, static_cast<unsigned long long>(pipeline));
    if (g_cmd_bind_pipeline) g_cmd_bind_pipeline(commandBuffer, bindPoint, pipeline);
}
'@

# Single-axis experiment: only target-dispatch suppression changes behavior.
Replace-Required @'
static void WINAPI Audit_vkCmdDispatch(VkCommandBuffer commandBuffer, std::uint32_t x, std::uint32_t y, std::uint32_t z) {
    MarkApi("vkCmdDispatch");
    const LONG id = InterlockedIncrement(&g_dispatch_calls);
    if (SampleCall(id, 32, 500)) LogFormat("TRACE dispatch #%ld groups=%u,%u,%u", id, x, y, z);
    if (g_cmd_dispatch) g_cmd_dispatch(commandBuffer, x, y, z);
}
'@ @'
static void WINAPI Audit_vkCmdDispatch(VkCommandBuffer commandBuffer, std::uint32_t x, std::uint32_t y, std::uint32_t z) {
    MarkApi("vkCmdDispatch");
    const LONG id = InterlockedIncrement(&g_dispatch_calls);
    VkPipeline targetPipeline = 0;
    std::uint64_t targetHash = 0;
    const bool target = CurrentCommandUsesDoaxCompute(commandBuffer, &targetPipeline, &targetHash);
    if (target && SampleCall(id, 64, 250)) {
        LogFormat("DOAX TARGET_DISPATCH #%ld cmd=%p pipeline=0x%llx fnv64=0x%016llx groups=%u,%u,%u bypass=%d",
                  id, commandBuffer, static_cast<unsigned long long>(targetPipeline),
                  static_cast<unsigned long long>(targetHash), x, y, z,
                  g_doax_compute_bypass ? 1 : 0);
    }
    if (target && g_doax_compute_bypass) return;
    if (SampleCall(id, 32, 500)) LogFormat("TRACE dispatch #%ld groups=%u,%u,%u", id, x, y, z);
    if (g_cmd_dispatch) g_cmd_dispatch(commandBuffer, x, y, z);
}
'@

# Handle reuse safety.
Replace-Required @'
static void WINAPI Audit_vkDestroyShaderModule(VkDevice device, VkShaderModule module, const void* allocator) {
    MarkApi("vkDestroyShaderModule");
    const LONG id = InterlockedIncrement(&g_destroy_shader_module_calls);
'@ @'
static void WINAPI Audit_vkDestroyShaderModule(VkDevice device, VkShaderModule module, const void* allocator) {
    MarkApi("vkDestroyShaderModule");
    ForgetShaderHash(module);
    const LONG id = InterlockedIncrement(&g_destroy_shader_module_calls);
'@

Replace-Required @'
static void WINAPI Audit_vkDestroyPipeline(VkDevice device, VkPipeline pipeline, const void* allocator) {
    MarkApi("vkDestroyPipeline");
    const LONG id = InterlockedIncrement(&g_destroy_pipeline_calls);
'@ @'
static void WINAPI Audit_vkDestroyPipeline(VkDevice device, VkPipeline pipeline, const void* allocator) {
    MarkApi("vkDestroyPipeline");
    ForgetComputePipelineHash(pipeline);
    const LONG id = InterlockedIncrement(&g_destroy_pipeline_calls);
'@

# Identify Build 08 and make the experiment state explicit in every log.
Replace-Required @'
        LogLine("VK3to2 Build 07 initialized: null depth attachment repair");
        LogFormat("OPTIONS trace.audit=%d trace.sampled_calls=%d trace.nvidia_exceptions=%d",
                  g_audit_enabled ? 1 : 0, g_trace_sampled_calls ? 1 : 0,
                  g_trace_nvidia_exceptions ? 1 : 0);
        LogFormat("OPTIONS patches.guard_incomplete_framebuffers=%d patches.repair_null_depth=%d repair_max_dimension=%u",
                  g_guard_incomplete_framebuffers ? 1 : 0, g_repair_null_depth ? 1 : 0,
                  g_repair_max_dimension);
'@ @'
        LogLine("VK3to2 Build 08 initialized: DOAX compute isolation");
        LogFormat("OPTIONS trace.audit=%d trace.sampled_calls=%d trace.nvidia_exceptions=%d",
                  g_audit_enabled ? 1 : 0, g_trace_sampled_calls ? 1 : 0,
                  g_trace_nvidia_exceptions ? 1 : 0);
        LogFormat("OPTIONS patches.guard_incomplete_framebuffers=%d patches.repair_null_depth=%d repair_max_dimension=%u patches.doax_compute_bypass=%d",
                  g_guard_incomplete_framebuffers ? 1 : 0, g_repair_null_depth ? 1 : 0,
                  g_repair_max_dimension, g_doax_compute_bypass ? 1 : 0);
        LogLine("DOAX target cs_0x03b537c5 SPIR-V FNV64: 7fa9bff1ccb6d98b / 2e7c73596899e13f");
'@

New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
Set-Content -LiteralPath $outPath -Value $script:src -Encoding UTF8
Write-Host "Build 08 patch generated $outPath"
