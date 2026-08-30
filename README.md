# VK3to2

VK3to2 is a small local `vulkan-1.dll` compatibility proxy intended to let a fixed shadPS4 Windows build run against an older Vulkan 1.2 driver while selectively translating only the Vulkan 1.3 functionality that proves necessary.

## Project boundary

- One development branch: `main`.
- The shadPS4 host build is frozen and is **not** rebuilt by this repository.
- No shadPS4 source code belongs in this repository.
- Only the frozen `shadps4.exe` and `shadps4-win7-launcher.exe` binaries are retained as host backups.
- VK3to2 is the only component intended to change between experiments.

## Frozen host baseline

Source build: `502-Bad-Gateway/shadPS4_test_7`, Actions run `33297329016`, branch `shadps4_clone`, commit `9cc48cfa39283e97ee97e6b66ccb9fffddc6f0a7`.

Expected binaries:

| File | SHA-256 |
| --- | --- |
| `shadps4.exe` | `bd90af526f653b0250dd1875104acffafb756e96f3416431524ee67a84a19e4a` |
| `shadps4-win7-launcher.exe` | `6424656021b20192c5e7f9ddfe07cd7f3372c514cd8327f7ea62568eaca391fc` |

## Development model

The first milestone is deliberately a transparent pass-through proxy. It must not fake Vulkan 1.3 support or change application behavior. It loads the real `%SystemRoot%\\System32\\vulkan-1.dll`, forwards Vulkan dispatch, and records which entry points shadPS4 requests. Compatibility translations are added later one isolated axis at a time.

Typical test layout:

```text
shadps4.exe
shadps4-win7-launcher.exe
vulkan-1.dll             <- VK3to2 build
VK3to2.log
```
