# VK3to2

VK3to2 is a small local `vulkan-1.dll` compatibility/workaround proxy for a fixed shadPS4 Windows build running on the Windows 7 NVIDIA Vulkan 1.2 stack. It is designed for fast isolated experiments without rebuilding shadPS4.

## Project boundary

- One development branch: `main`.
- The shadPS4 host build is frozen and is **not** rebuilt by this repository.
- No shadPS4 source code belongs in this repository.
- The frozen host executables are kept locally by the tester; their hashes and source build are recorded below, but the binaries are not committed here.
- VK3to2 is the only component intended to change between experiments.

## Frozen host baseline

Source build: `502-Bad-Gateway/shadPS4_test_7`, Actions run `33297329016`, branch `shadps4_clone`, commit `9cc48cfa39283e97ee97e6b66ccb9fffddc6f0a7`.

Expected binaries:

| File | SHA-256 |
| --- | --- |
| `shadps4.exe` | `bd90af526f653b0250dd1875104acffafb756e96f3416431524ee67a84a19e4a` |
| `shadps4-win7-launcher.exe` | `6424656021b20192c5e7f9ddfe07cd7f3372c514cd8327f7ea62568eaca391fc` |

## Current findings

Build 00 proved that a local proxy can sit transparently between shadPS4 and `%SystemRoot%\System32\vulkan-1.dll`: We Are Doomed remained fully functional and failing titles retained their baseline behavior.

Build 01 showed that this frozen shadPS4 host already requests Vulkan **1.2.0**, while the Windows 7 NVIDIA loader/device report Vulkan 1.2. The host enables extension-form functionality including `VK_KHR_synchronization2`, `VK_KHR_push_descriptor`, `VK_EXT_extended_dynamic_state`, `VK_EXT_extended_dynamic_state2`, and `VK_EXT_vertex_input_dynamic_state`. Graphics/shader pipeline creation observed in the failing tests returned success before the common `nvoglv64.dll` access violation. Therefore the immediate problem is not simply a Vulkan 1.3 API-version gate; VK3to2 is now also used as a targeted NVIDIA-driver compatibility/workaround shim.

## Build 02

Build 02 remains pass-through by default and adds:

- Windows thread IDs to trace lines.
- Execution tracing for synchronization2, vertex-input dynamic state, render passes, pipeline binds, draws/dispatches, submits, and presents.
- A first-chance NVIDIA access-violation observer that logs the Vulkan call active on the faulting thread plus the latest global Vulkan call.
- Optional `VK3to2.ini` switches for pipeline serialization and pipeline-cache bypass. Both are **OFF by default** and should remain off for the baseline Build 02 test.

Typical test layout:

```text
shadps4.exe
shadps4-win7-launcher.exe
vulkan-1.dll             <- VK3to2 build
VK3to2.ini
VK3to2.log
```
