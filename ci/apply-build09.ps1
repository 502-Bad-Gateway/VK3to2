$ErrorActionPreference = 'Stop'

# Build 09 keeps all proven Build 07/08 behavior and extends the DOAX compute
# isolation target to the exact DOAX3 01.19 compute shader captured by the user:
#   cs_0x0000000023b929f2_0.spv
# FNV-1a 64 of the Vulkan SPIR-V bytes: 0x9807e7f5538f29a4
& .\ci\apply-build08-final.ps1

$sourcePath = 'dist\vk3to2_build08.cpp'
$outPath = 'dist\vk3to2_build09.cpp'
$src = Get-Content -Raw -LiteralPath $sourcePath

$old = @'
static bool IsDoaxCapturedComputeHash(std::uint64_t hash) {
    // DOAX3 01.00 cs_0x0000000003b537c5, two captured permutations.
    return hash == 0x7fa9bff1ccb6d98bull || hash == 0x2e7c73596899e13full;
}
'@
$new = @'
static bool IsDoaxCapturedComputeHash(std::uint64_t hash) {
    // DOAX3 01.00 cs_0x0000000003b537c5, two captured permutations,
    // plus DOAX3 01.19 exact cs_0x0000000023b929f2 capture.
    return hash == 0x7fa9bff1ccb6d98bull ||
           hash == 0x2e7c73596899e13full ||
           hash == 0x9807e7f5538f29a4ull;
}
'@

if (-not $src.Contains($old)) {
    throw 'Build 09 target-hash patch anchor not found'
}
$src = $src.Replace($old, $new)
Set-Content -LiteralPath $outPath -Value $src -Encoding UTF8
Write-Host "Build 09 generated $outPath with exact DOAX3 01.19 compute target"
