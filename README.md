# FIMountKit

Swift Package for mounting forensic and general-purpose disk images on macOS.

| | |
|---|---|
| **SPM package name** | `FIMountKit` |
| **Library product** | `FIMountKit` — `import FIMountKit` in app code |
| **Platform** | macOS 13+ |
| **Swift** | 5.9+ |

Designed for forensic workflows and system-level analysis: DMG, RAW/DD, EWF, AFF4, VMDK, VHD, and split RAW images behind a single `ImageMountingService` API.

---

## ⚠️ Important: You Must Use a Local Package — Not the Xcode URL Flow

**Do not add FIMountKit via Xcode's "Add Package Dependencies" dialog or via a `url:` reference in `Package.swift`.**

FIMountKit's submodules (`libewf-spm`, `libvmdk-spm`, `libvhdi-spm`) use
`unsafeFlags` in their `Package.swift` to link pre-built static libraries.
Swift Package Manager **silently blocks `unsafeFlags` for remote packages**,
which causes the build to fail with cryptic linker errors.

The only supported way to use FIMountKit is to **clone it locally** and add it
as a **local package** in Xcode. This is a one-time setup step.

---

## Adding FIMountKit to Your App

### Step 1 — Clone with submodules

Always clone with `--recurse-submodules`. The bundled forensic libraries
(`libewf`, `libvmdk`, `libvhdi`, `libcaff4`) are git submodules and will
not be present without this flag.

```bash
git clone --recurse-submodules https://github.com/saadtahir-dev/FIMountKit.git
```

If you already cloned without the flag:

```bash
git submodule update --init --recursive
```

### Step 2 — Add as a local package in Xcode

1. Open your app project in Xcode
2. Go to **File → Add Package Dependencies**
3. Click **Add Local...** (bottom-left of the dialog)
4. Navigate to the folder where you cloned FIMountKit and select it
5. Click **Add Package**
6. In the target dependency sheet, select **FIMountKit** and click **Add Package**

> Do **not** paste the GitHub URL into the search field. Remote packages
> with `unsafeFlags` will fail to build.

### Step 3 — Import and use

```swift
import FIMountKit
```

---

## Keeping FIMountKit Up to Date

Since FIMountKit is a local package, updates are managed via git:

```bash
cd /path/to/FIMountKit
git pull
git submodule update --recursive
```

Then in Xcode: **File → Packages → Reset Package Caches** to pick up changes.

---

## Features

- Plug-and-play SwiftPM library (`FIMountKit` product)
- Extension-based format detection (`ImageFormatDetector`)
- Native macOS attach via `hdiutil` for block-device presentation
- EWF / VMDK / VHD via bundled FUSE tools (`ewfmount`, `vmdkmount`, `vhdimount`) — no Homebrew tool install
- AFF4 via in-process **Libcaff4** reads (no CLI, no FUSE)
- Split RAW merge (chunked, memory-safe) before attach
- Structured logging with per-mount correlation IDs
- `TemporaryResource` tracking and LIFO cleanup on unmount
- Safe for concurrent use (`async`/`await`, TaskGroup-friendly mounters)
- Injectable mounter list for testing or partial format support

---

## Supported formats

| Category | Extensions | Pipeline |
|---|---|---|
| Apple disk images | `.dmg`, `.sparseimage`, `.sparsebundle` | `hdiutil attach` |
| Raw images | `.raw`, `.dd` | `hdiutil attach` (`CRawDiskImage`) |
| EWF (EnCase) | `.e01`, `.ex01`, `.s01` | `ewfmount` (FUSE) → `ewf1` → `hdiutil` |
| AFF4 | `.aff4` | **Libcaff4** full extract → temp `.img` → `hdiutil` |
| VMware VMDK | `.vmdk` | `vmdkmount` (FUSE) → `vmdk1` → `hdiutil` |
| Microsoft VHD | `.vhd` | `vhdimount` (FUSE) → `vhdi1` → `hdiutil` |
| Split RAW | `.001`, `.002`, … | merge segments → `hdiutil` |

**Detection vs merge:** `ImageFormatDetector` also maps `.000` and `.00001` to split RAW, but `SplitRawMerger` only merges sets that **start at `.001`**. Use a `.001` first segment for reliable split mounts.

**Not supported:** `.vhdx`, `.iso`, `.img` (unmapped alias), and formats outside the table above.

---

## How it works

```
Input URL
   ↓
ImageFormatDetector          (file extension → ImageType)
   ↓
ImageMountingService         (path validation, logging, mounter selection)
   ↓
ImageMounter (per format)
   ↓
  ├─ DMG / RAW / sparse     → ProcessExecutor → hdiutil
  ├─ EWF / VMDK / VHD       → bundled *mount (FUSE) → RawImageMounter → hdiutil
  ├─ AFF4                   → Libcaff4 AFF4Image → temp file → RawImageMounter → hdiutil
  └─ Split RAW              → SplitRawMerger → RawImageMounter → hdiutil
   ↓
MountResult                  (mount points, devices, temporaryResources)
```

Most non-native formats are **two-stage**: produce or expose a flat raw image, then reuse `RawImageMounter`.

---

## Requirements

| Requirement | Needed for |
|---|---|
| macOS 13+ | Package platform (`Package.swift`) |
| Swift 5.9+ / Xcode 15+ | Build |
| `hdiutil` (system) | All mounts that attach a volume |
| [macFUSE](https://osxfuse.github.io/) 4.x or 5.x | **EWF, VMDK, VHD only** (FUSE tools) |

AFF4, DMG, RAW, and split RAW do **not** require macFUSE. AFF4 **does** require enough disk space to hold a full extracted copy of the image.

---

## Dependencies

FIMountKit bundles four forensic libraries as **git submodules** under `Dependencies/`. They are resolved automatically when cloning with `--recurse-submodules`.

| Submodule | Path | Repo |
|---|---|---|
| `libewf-spm` | `Dependencies/libewf-spm` | [github.com/saadtahir-dev/libewf-spm](https://github.com/saadtahir-dev/libewf-spm) |
| `libvmdk-spm` | `Dependencies/libvmdk-spm` | [github.com/saadtahir-dev/libvmdk-spm](https://github.com/saadtahir-dev/libvmdk-spm) |
| `libvhdi-spm` | `Dependencies/libvhdi-spm` | [github.com/saadtahir-dev/libvhdi-spm](https://github.com/saadtahir-dev/libvhdi-spm) |
| `libcaff4-spm` | `Dependencies/libcaff4-spm` | [github.com/saadtahir-dev/libcaff4-spm](https://github.com/saadtahir-dev/libcaff4-spm) |

Each submodule ships **universal fat static archives** (arm64 + x86_64) and **bundled CLI tools** in SPM resource bundles. OpenSSL/zlib deps are linked statically or via the system where applicable.

**Dependency graph:**

```
FIMountKit
├── libewf-spm
│   ├── CLibEWF / CLibEWFFuse (static libs)
│   ├── CLibEWFResources (bin: ewfmount, …)
│   └── libewf (Swift: EWFToolLocator)
├── libcaff4-spm
│   ├── Ccaff4 (static libaff4 + headers)
│   └── Libcaff4 (Swift: AFF4Image)
├── libvmdk-spm
│   ├── CLibVMDK (static libs)
│   ├── CLibVMDKResources (bin: vmdkmount, vmdkinfo)
│   └── LibVMDK (Swift: VMDKToolLocator)
└── libvhdi-spm
    ├── CLibVHDI (static libs)
    ├── CLibVHDIResources (bin: vhdimount, vhdiinfo)
    └── LibVHDI (Swift: VHDIToolLocator)
```

---

## Usage

### Default service

```swift
import FIMountKit

let service = ImageMountingService(
    log: { message, level, component in
        print("[\(component.rawValue)] [\(level.rawValue)] \(message)")
    }
)

let result = try await service.mount(
    url: URL(fileURLWithPath: "/path/to/image.vmdk")
)

for mountPoint in result.mountPointURLs {
    print(mountPoint.path)
}

try await service.unmount(result)
```

### Mount options

```swift
let options = MountOptions(
    workspaceDirectory: URL(fileURLWithPath: "/tmp/fimountkit-workspace"),
    volumeMountPoint: URL(fileURLWithPath: "/Volumes/CaseImage")
)

let result = try await service.mount(
    url: URL(fileURLWithPath: "/path/to/image.e01"),
    options: options
)
```

| Option | Purpose |
|---|---|
| `workspaceDirectory` | FUSE mount dirs (EWF/VMDK/VHD), optional split-merge output parent |
| `volumeMountPoint` | Passed to `hdiutil -mountpoint` (must be empty or creatable) |

### Custom mounter set

```swift
let service = ImageMountingService(
    mounters: [
        DMGImageMounter(),
        RawImageMounter(),
        EWFImageMounter(),
    ]
)
```

Default factory (`ImageMounterFactory.makeDefaultMounters()`): DMG, Raw, AFF4, EWF, VMDK, VHDI, SplitRaw — in that order. The service picks the **first** mounter whose `supportedTypes` contains the detected type.

---

## Tool resolution

`ProcessExecutor` always receives an **absolute executable path**; it does not search `PATH`.

| Component | Tool resolution |
|---|---|
| `DMGImageMounter` | `SystemToolLocator` → `hdiutil` |
| `RawImageMounter` | `SystemToolLocator` → `hdiutil` |
| `EWFMountManager` | `EWFToolLocator.bundledToolPath("ewfmount")` or system fallback |
| `VMDKMountManager` | `VMDKToolLocator.vmdkmount` or system fallback |
| `VHDIMountManager` | `VHDIToolLocator.vhdimount` or system fallback |
| `AFF4ImageMounter` | **Libcaff4** in-process (`AFF4Image`) — no bundled CLI |
| `SplitRawMerger` | Pure Swift / Foundation I/O |

---

## Public API surface

| Type | Role |
|---|---|
| `ImageMountingService` | `mount(url:options:)`, `unmount(_:)` |
| `ImageFormatDetector` | Extension → `ImageType` |
| `ImageMounter` | Per-format mount/unmount protocol |
| `MountResult` | `sourceURL`, `type`, `deviceIdentifiers`, `mountPointURLs`, `temporaryResources`, `metadata` |
| `MountOptions` | Workspace and volume mount point |
| `MountError` | Typed failures (`unsupportedType`, `detectionFailed`, …) |
| `ImageMounterFactory` | Default mounter list |
| `*ImageMounter` | `DMG`, `Raw`, `AFF4`, `EWF`, `VMDK`, `VHDI`, `SplitRaw` |

---

## Resource management

- FUSE mount directories, merged split RAW files, and AFF4 temp extracts are recorded in `MountResult.temporaryResources`.
- Unmount runs format-specific detach, then removes temporary artifacts in **reverse order**.
- On mount failure after partial setup, mounters attempt cleanup (e.g. tear down FUSE if `hdiutil` fails).

---

## Source layout

```
Sources/ImageMounter/
├── ImageMountingService.swift
├── Detection/ImageFormatDetector.swift
├── Core/                    ImageType, MountResult, MountError, MountOptions
├── Mounters/
│   ├── DMG/                 DMGImageMounter
│   ├── RAW/                 RawImageMounter
│   ├── EWF/                 EWFImageMounter, EWFMountManager
│   ├── AFF4/                AFF4ImageMounter
│   ├── VMDK/                VMDKImageMounter, VMDKMountManager
│   ├── VHD/                 VHDIImageMounter, VHDIMountManager
│   ├── SplitRAW/            SplitRawImageMounter, SplitRawMerger
│   └── ImageMounterFactory.swift
├── Infrastructure/          ProcessExecutor, HDIUtil helpers, SystemToolLocator, MountPathValidator
└── Logging/                 ImageMounterLogHandler, Logger

Dependencies/
├── libewf-spm/              (git submodule)
├── libvmdk-spm/             (git submodule)
├── libvhdi-spm/             (git submodule)
└── libcaff4-spm/            (git submodule)
```

---

## Build & test

```bash
git clone --recurse-submodules https://github.com/saadtahir-dev/FIMountKit.git
cd FIMountKit
swift package resolve
swift build
swift test
```

---

## Notes

- **macFUSE** must be installed and loaded for EWF, VMDK, and VHD mounts.
- **AFF4** mounts read the entire logical image into a temp file before attach — large images need proportional free disk space and time.
- **Multi-part EWF** (`.e01` + `.e02` + …): open the first segment; libewf / `ewfmount` resolve the set.
- **Multiple partitions** per image are supported where `hdiutil` exposes them.
- Host apps embedding bundled binaries may need **Hardened Runtime** exceptions (e.g. disable library validation) when not using App Sandbox.

---

## Status

- Core mounting paths implemented for all listed formats
- Extensible `ImageMounter` protocol and injectable service
- Validated on Apple Silicon macOS via `image-mounter-poc` bulk regression UI
