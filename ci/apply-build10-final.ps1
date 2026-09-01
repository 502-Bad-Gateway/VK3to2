$ErrorActionPreference = 'Stop'

& .\ci\apply-build10.ps1

$path = 'dist\vk3to2_build10.cpp'
$src = Get-Content -Raw -LiteralPath $path
$anchor = 'static HMODULE g_self = nullptr;'
if (-not $src.Contains($anchor)) {
    throw "Build 10 final patch anchor not found: $anchor"
}

$decl = @'
static void ForgetGraphicsPipelineTarget(VkPipeline pipeline);

'@
$src = $src.Replace($anchor, $decl + $anchor)
Set-Content -LiteralPath $path -Value $src -Encoding UTF8
Write-Host "Build 10 final declaration-order fix applied to $path"
