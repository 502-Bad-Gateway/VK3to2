$ErrorActionPreference = 'Stop'

# Build 10 keeps the proven Build 07 null-depth repair and Build 08/09 tracking,
# but turns the already-negative compute bypass off by default in the INI.
# It isolates the two Full-GPU-only graphics pipelines created while ninja_vi.mp4
# is finishing in DOAX3 01.19. SafeGPU never creates these pipelines and survives.
#
# shadPS4 pipeline 0x4989d09ab61f5fe1:
#   fs_0x6473b669 FNV64 fbb3aa7a8d59b762
#   vs_0x54e0ef3a permutation FNV64 d37df9dcdf5de3cb
# shadPS4 pipeline 0xc8c63801c5806726:
#   fs_0xa32899da FNV64 e4b70a0eecc45954
#   vs_0x5f0f6886 permutation FNV64 5f1f166ebf76e131
#
# We still let vkCreateGraphicsPipelines succeed. Only draw execution while one
# of those exact pipelines is bound is optionally suppressed. This is safer than
# returning fake pipeline handles and is close to SafeGPU's no-draw semantics.
& .\ci\apply-build09.ps1

$sourcePath = 'dist\vk3to2_build09.cpp'
$outPath = 'dist\vk3to2_build10.cpp'
$script:src = Get-Content -Raw -LiteralPath $sourcePath

function Replace-Required([string]$old, [string]$new) {
    if (-not $script:src.Contains($old)) {
        throw "Build 10 patch anchor not found: $old"
    }
    $script:src = $script:src.Replace($old, $new)
}

function Replace-CppFunction([string]$signature, [string]$replacement) {
    $start = $script:src.IndexOf($signature, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Build 10 function not found: $signature" }
    $open = $script:src.IndexOf('{', $start)
    if ($open -lt 0) { throw "Build 10 opening brace not found: $signature" }
    $depth = 0
    $close = -1
    for ($i = $open; $i -lt $script:src.Length; ++$i) {
        $ch = $script:src[$i]
        if ($ch -eq '{') { ++$depth }
        elseif ($ch -eq '}') {
            --$depth
            if ($depth -eq 0) { $close = $i; break }
        }
    }
    if ($close -lt 0) { throw "Build 10 closing brace not found: $signature" }
    $script:src = $script:src.Substring(0, $start) + $replacement + $script:src.Substring($close + 1)
}

# Minimal prefix of VkGraphicsPipelineCreateInfo; stageCount/pStages are all we
# inspect. Natural x64 alignment matches Vulkan's ABI.
Replace-Required @'
struct VkComputePipelineCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    VkPipelineShaderStageCreateInfoMini stage;
    VkPipelineLayout layout;
    VkPipeline basePipelineHandle;
    std::int32_t basePipelineIndex;
};
'@ @'
struct VkComputePipelineCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    VkPipelineShaderStageCreateInfoMini stage;
    VkPipelineLayout layout;
    VkPipeline basePipelineHandle;
    std::int32_t basePipelineIndex;
};

struct VkGraphicsPipelineCreateInfoMini {
    std::uint32_t sType;
    const void* pNext;
    std::uint32_t flags;
    std::uint32_t stageCount;
    const VkPipelineShaderStageCreateInfoMini* pStages;
};
'@

Replace-Required @'
static bool g_doax_compute_bypass = false;
'@ @'
static bool g_doax_compute_bypass = false;
static bool g_doax119_bypass_video4989 = false;
static bool g_doax119_bypass_videoc8c = false;
'@

Replace-Required @'
    g_doax_compute_bypass = GetPrivateProfileIntW(L"patches", L"doax_compute_bypass", 0, ini_path) != 0;
'@ @'
    g_doax_compute_bypass = GetPrivateProfileIntW(L"patches", L"doax_compute_bypass", 0, ini_path) != 0;
    g_doax119_bypass_video4989 = GetPrivateProfileIntW(L"patches", L"doax119_bypass_video4989", 0, ini_path) != 0;
    g_doax119_bypass_videoc8c = GetPrivateProfileIntW(L"patches", L"doax119_bypass_videoc8c", 0, ini_path) != 0;
'@

# Extend the existing fixed-size tracking scheme. No heap allocation is added to
# command recording.
Replace-Required @'
static CommandBufferComputeRecord g_command_compute_records[256]{};
'@ @'
static CommandBufferComputeRecord g_command_compute_records[256]{};

struct GraphicsPipelineTargetRecord {
    bool used;
    VkPipeline pipeline;
    std::uint32_t targetMask;
};

struct CommandBufferGraphicsRecord {
    bool used;
    VkCommandBuffer commandBuffer;
    VkPipeline pipeline;
    std::uint32_t targetMask;
};

static GraphicsPipelineTargetRecord g_graphics_target_records[2048]{};
static CommandBufferGraphicsRecord g_command_graphics_records[256]{};
'@

$graphicsTracking = @'
static std::uint32_t ClassifyDoax119VideoPipeline(const VkGraphicsPipelineCreateInfoMini* info) {
    if (!info || !info->pStages || info->stageCount == 0 || info->stageCount > 16) return 0;
    bool fs4989 = false, vs4989 = false, fsc8c = false, vsc8c = false;
    for (std::uint32_t s = 0; s < info->stageCount; ++s) {
        const std::uint64_t hash = LookupShaderHash(info->pStages[s].module);
        fs4989 |= hash == 0xfbb3aa7a8d59b762ull;
        vs4989 |= hash == 0xd37df9dcdf5de3cbull;
        fsc8c   |= hash == 0xe4b70a0eecc45954ull;
        vsc8c   |= hash == 0x5f1f166ebf76e131ull;
    }
    std::uint32_t mask = 0;
    if (fs4989 && vs4989) mask |= 1u;
    if (fsc8c && vsc8c) mask |= 2u;
    return mask;
}

static void RecordGraphicsPipelineTarget(VkPipeline pipeline, std::uint32_t targetMask) {
    if (!pipeline) return;
    AcquireSRWLockExclusive(&g_compute_track_lock);
    GraphicsPipelineTargetRecord* free_slot = nullptr;
    for (auto& record : g_graphics_target_records) {
        if (record.used && record.pipeline == pipeline) {
            record.targetMask = targetMask;
            ReleaseSRWLockExclusive(&g_compute_track_lock);
            return;
        }
        if (!record.used && !free_slot) free_slot = &record;
    }
    if (free_slot) {
        free_slot->used = true;
        free_slot->pipeline = pipeline;
        free_slot->targetMask = targetMask;
    }
    ReleaseSRWLockExclusive(&g_compute_track_lock);
}

static std::uint32_t LookupGraphicsPipelineTarget(VkPipeline pipeline) {
    std::uint32_t mask = 0;
    AcquireSRWLockShared(&g_compute_track_lock);
    for (const auto& record : g_graphics_target_records) {
        if (record.used && record.pipeline == pipeline) {
            mask = record.targetMask;
            break;
        }
    }
    ReleaseSRWLockShared(&g_compute_track_lock);
    return mask;
}

static void ForgetGraphicsPipelineTarget(VkPipeline pipeline) {
    AcquireSRWLockExclusive(&g_compute_track_lock);
    for (auto& record : g_graphics_target_records) {
        if (record.used && record.pipeline == pipeline) {
            record = {};
            break;
        }
    }
    for (auto& record : g_command_graphics_records) {
        if (record.used && record.pipeline == pipeline) record = {};
    }
    ReleaseSRWLockExclusive(&g_compute_track_lock);
}

static void SetCommandGraphicsPipeline(VkCommandBuffer commandBuffer, VkPipeline pipeline) {
    if (!commandBuffer) return;
    const std::uint32_t mask = LookupGraphicsPipelineTarget(pipeline);
    AcquireSRWLockExclusive(&g_compute_track_lock);
    CommandBufferGraphicsRecord* free_slot = nullptr;
    for (auto& record : g_command_graphics_records) {
        if (record.used && record.commandBuffer == commandBuffer) {
            record.pipeline = pipeline;
            record.targetMask = mask;
            ReleaseSRWLockExclusive(&g_compute_track_lock);
            return;
        }
        if (!record.used && !free_slot) free_slot = &record;
    }
    if (free_slot) {
        free_slot->used = true;
        free_slot->commandBuffer = commandBuffer;
        free_slot->pipeline = pipeline;
        free_slot->targetMask = mask;
    }
    ReleaseSRWLockExclusive(&g_compute_track_lock);
}

static std::uint32_t CurrentCommandGraphicsTarget(VkCommandBuffer commandBuffer, VkPipeline* outPipeline) {
    std::uint32_t mask = 0;
    VkPipeline pipeline = 0;
    AcquireSRWLockShared(&g_compute_track_lock);
    for (const auto& record : g_command_graphics_records) {
        if (record.used && record.commandBuffer == commandBuffer) {
            pipeline = record.pipeline;
            mask = record.targetMask;
            break;
        }
    }
    ReleaseSRWLockShared(&g_compute_track_lock);
    if (outPipeline) *outPipeline = pipeline;
    return mask;
}

static bool ShouldBypassDoax119VideoTarget(std::uint32_t mask) {
    return ((mask & 1u) && g_doax119_bypass_video4989) ||
           ((mask & 2u) && g_doax119_bypass_videoc8c);
}

'@
Replace-Required 'static VkResult WINAPI Audit_vkCreateShaderModule' ($graphicsTracking + 'static VkResult WINAPI Audit_vkCreateShaderModule')

$createGraphics = @'
static VkResult WINAPI Audit_vkCreateGraphicsPipelines(VkDevice device, VkPipelineCache cache, std::uint32_t count, const void* infos, const void* allocator, VkPipeline* pipelines) {
    MarkApi("vkCreateGraphicsPipelines");
    const LONG id = InterlockedIncrement(&g_graphics_pipeline_calls);
    const VkPipelineCache forwarded_cache = g_disable_pipeline_cache ? 0 : cache;
    const auto* createInfos = reinterpret_cast<const VkGraphicsPipelineCreateInfoMini*>(infos);
    LogFormat("TRACE graphicsPipelines #%ld ENTER count=%u cache=0x%llx forwarded_cache=0x%llx",
              id, count, static_cast<unsigned long long>(cache), static_cast<unsigned long long>(forwarded_cache));
    if (g_serialize_pipelines) AcquireSRWLockExclusive(&g_pipeline_lock);
    const VkResult result = g_create_graphics_pipelines ? g_create_graphics_pipelines(device, forwarded_cache, count, infos, allocator, pipelines) : -3;
    if (g_serialize_pipelines) ReleaseSRWLockExclusive(&g_pipeline_lock);
    if (result == 0 && createInfos && pipelines) {
        for (std::uint32_t i = 0; i < count; ++i) {
            const std::uint32_t mask = ClassifyDoax119VideoPipeline(&createInfos[i]);
            RecordGraphicsPipelineTarget(pipelines[i], mask);
            if (mask) {
                LogFormat("DOAX119 VIDEO_PIPELINE_CREATE #%ld[%u] pipeline=0x%llx mask=0x%x bypass4989=%d bypassc8c=%d",
                          id, i, static_cast<unsigned long long>(pipelines[i]), mask,
                          g_doax119_bypass_video4989 ? 1 : 0, g_doax119_bypass_videoc8c ? 1 : 0);
            }
        }
    }
    LogFormat("TRACE graphicsPipelines #%ld RETURN result=%d", id, result);
    return result;
}
'@
Replace-CppFunction 'static VkResult WINAPI Audit_vkCreateGraphicsPipelines(' $createGraphics

$bindPipeline = @'
static void WINAPI Audit_vkCmdBindPipeline(VkCommandBuffer commandBuffer, std::uint32_t bindPoint, VkPipeline pipeline) {
    MarkApi("vkCmdBindPipeline");
    const LONG id = InterlockedIncrement(&g_bind_pipeline_calls);
    if (bindPoint == 0u) {
        SetCommandGraphicsPipeline(commandBuffer, pipeline);
        const std::uint32_t mask = LookupGraphicsPipelineTarget(pipeline);
        if (mask) {
            LogFormat("DOAX119 VIDEO_PIPELINE_BIND cmd=%p pipeline=0x%llx mask=0x%x bypass=%d", commandBuffer,
                      static_cast<unsigned long long>(pipeline), mask,
                      ShouldBypassDoax119VideoTarget(mask) ? 1 : 0);
        }
    } else if (bindPoint == 1u) {
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
Replace-CppFunction 'static void WINAPI Audit_vkCmdBindPipeline(' $bindPipeline

$draw = @'
static void WINAPI Audit_vkCmdDraw(VkCommandBuffer commandBuffer, std::uint32_t vertexCount, std::uint32_t instanceCount,
                                   std::uint32_t firstVertex, std::uint32_t firstInstance) {
    MarkApi("vkCmdDraw");
    const LONG id = InterlockedIncrement(&g_draw_calls);
    VkPipeline targetPipeline = 0;
    const std::uint32_t mask = CurrentCommandGraphicsTarget(commandBuffer, &targetPipeline);
    if (mask) {
        const bool bypass = ShouldBypassDoax119VideoTarget(mask);
        LogFormat("DOAX119 VIDEO_DRAW #%ld cmd=%p pipeline=0x%llx mask=0x%x vertices=%u instances=%u bypass=%d",
                  id, commandBuffer, static_cast<unsigned long long>(targetPipeline), mask,
                  vertexCount, instanceCount, bypass ? 1 : 0);
        if (bypass) return;
    }
    if (SampleCall(id, 32, 1000)) LogFormat("TRACE draw #%ld vertices=%u instances=%u", id, vertexCount, instanceCount);
    if (g_cmd_draw) g_cmd_draw(commandBuffer, vertexCount, instanceCount, firstVertex, firstInstance);
}
'@
Replace-CppFunction 'static void WINAPI Audit_vkCmdDraw(' $draw

$drawIndexed = @'
static void WINAPI Audit_vkCmdDrawIndexed(VkCommandBuffer commandBuffer, std::uint32_t indexCount, std::uint32_t instanceCount,
                                          std::uint32_t firstIndex, std::int32_t vertexOffset, std::uint32_t firstInstance) {
    MarkApi("vkCmdDrawIndexed");
    const LONG id = InterlockedIncrement(&g_draw_indexed_calls);
    VkPipeline targetPipeline = 0;
    const std::uint32_t mask = CurrentCommandGraphicsTarget(commandBuffer, &targetPipeline);
    if (mask) {
        const bool bypass = ShouldBypassDoax119VideoTarget(mask);
        LogFormat("DOAX119 VIDEO_DRAW_INDEXED #%ld cmd=%p pipeline=0x%llx mask=0x%x indices=%u instances=%u bypass=%d",
                  id, commandBuffer, static_cast<unsigned long long>(targetPipeline), mask,
                  indexCount, instanceCount, bypass ? 1 : 0);
        if (bypass) return;
    }
    if (SampleCall(id, 32, 1000)) LogFormat("TRACE drawIndexed #%ld indices=%u instances=%u", id, indexCount, instanceCount);
    if (g_cmd_draw_indexed) g_cmd_draw_indexed(commandBuffer, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
}
'@
Replace-CppFunction 'static void WINAPI Audit_vkCmdDrawIndexed(' $drawIndexed

Replace-Required @'
    ForgetComputePipelineHash(pipeline);
'@ @'
    ForgetComputePipelineHash(pipeline);
    ForgetGraphicsPipelineTarget(pipeline);
'@

# Make Build 10 and all relevant switches explicit at startup.
Replace-Required @'
        LogLine("VK3to2 Build 08 initialized: DOAX compute isolation");
'@ @'
        LogLine("VK3to2 Build 10 initialized: DOAX3 01.19 video graphics-pipeline isolation");
'@
Replace-Required @'
        LogLine("DOAX target cs_0x03b537c5 SPIR-V FNV64: 7fa9bff1ccb6d98b / 2e7c73596899e13f");
'@ @'
        LogLine("DOAX compute targets include 01.19 cs_0x23b929f2 FNV64=9807e7f5538f29a4");
        LogFormat("OPTIONS patches.doax119_bypass_video4989=%d patches.doax119_bypass_videoc8c=%d",
                  g_doax119_bypass_video4989 ? 1 : 0, g_doax119_bypass_videoc8c ? 1 : 0);
        LogLine("DOAX119 video target 4989: fs=fbb3aa7a8d59b762 vs=d37df9dcdf5de3cb");
        LogLine("DOAX119 video target c8c: fs=e4b70a0eecc45954 vs=5f1f166ebf76e131");
'@

Set-Content -LiteralPath $outPath -Value $script:src -Encoding UTF8
Write-Host "Build 10 generated $outPath with exact DOAX3 01.19 video-pipeline draw isolation"
