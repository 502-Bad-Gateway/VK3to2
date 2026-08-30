$ErrorActionPreference = 'Stop'

# Generate Build 08, then add forward declarations required by Build 03's
# earlier destruction wrappers. This changes declaration order only; the
# Build 08 DOAX compute-isolation behavior is unchanged.
& .\ci\apply-build08.ps1

$path = 'dist\vk3to2_build08.cpp'
$src = Get-Content -Raw -LiteralPath $path
$anchor = 'static HMODULE g_self = nullptr;'
if (-not $src.Contains($anchor)) {
    throw "Build 08 final patch anchor not found: $anchor"
}

$decls = @'
static void ForgetShaderHash(VkShaderModule module);
static void ForgetComputePipelineHash(VkPipeline pipeline);

'@
$src = $src.Replace($anchor, $decls + $anchor)
Set-Content -LiteralPath $path -Value $src -Encoding UTF8
Write-Host "Build 08 final declaration-order fix applied to $path"
