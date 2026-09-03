# Install Cleo

This guide takes you from identifying your device to opening Cleo. You do not need to know your
processor brand, install .NET, or build anything from source.

> [!IMPORTANT]
> Download Cleo only from the official
> [`sahmsec/cleo-sqli` repository](https://github.com/sahmsec/cleo-sqli). Use it only on systems
> you own or have explicit permission to test.

## Choose your device

Start with the description you recognize:

| What you see | Follow this section |
|:--|:--|
| The device says **Chromebook** or runs **ChromeOS** | [Chromebook](#chromebook) |
| A **Windows Start** button is on the taskbar | [Windows](#windows) |
| An **Apple menu** is at the top-left of the screen | [macOS](#macos) |
| It runs Ubuntu, Debian, Fedora, Mint, Arch, or another desktop Linux—and is not a Chromebook | [Linux](#linux) |

You usually do **not** need to choose between Intel, AMD, and ARM. The guided installers detect
the supported processor automatically.

- Intel and AMD computers normally share the `x64` or `amd64` build. The name `amd64` does not
  mean that it only works on AMD processors.
- ARM may be shown as `ARM64` or `aarch64`.
- `AIM` is not a processor type; it is usually a misreading of `ARM`.

## Before installing

The guided installers:

1. detect the operating system and processor;
2. resolve the latest release to one fixed version;
3. download only the matching package from GitHub over HTTPS;
4. verify it against the release's `SHA256SUMS.txt` file;
5. inspect the package before installing anything.

They do not disable antivirus protection, add Defender exclusions, turn off Gatekeeper, install
an archive utility, or bypass certificate checks. Administrator access is not required except
when the verified Chromebook `.deb` is handed to Debian's package manager. Debian may then fetch
the package's declared desktop-library dependencies from its configured repositories.

## Windows

### Supported Windows devices

Cleo currently provides a native build for **64-bit Intel and AMD Windows 10 22H2 (build 19045)
or Windows 11**. Windows ARM64, 32-bit Windows, and older Windows releases do not currently have a
supported package. This conservative baseline follows Avalonia's current
[supported-platform table](https://docs.avaloniaui.net/docs/supported-platforms).

To check manually, open **Settings → System → About → System type**. Microsoft also provides a
[32-bit and 64-bit Windows guide](https://support.microsoft.com/en-us/windows/32-bit-and-64-bit-windows-frequently-asked-questions-c6ca9541-8dce-4d48-0415-94a3faa2e13d).

### Recommended: guided PowerShell installation

1. Right-click the **Start** button and open **Terminal** or **Windows PowerShell**.
2. Copy and run these three lines:

   ```powershell
   $installer = Join-Path $env:TEMP ("install-cleo-{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
   try {
       Invoke-WebRequest 'https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-windows.ps1' -OutFile $installer
       & $installer
   }
   finally { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }
   ```

3. The installer verifies the download, installs Cleo for your Windows account, creates a
   **Cleo** Start-menu shortcut, and opens the app.

If company or school policy prevents PowerShell scripts from running, do not weaken that policy.
Use the manual ZIP method below or ask the device administrator.

### Manual Windows installation

1. Download [`Cleo-Windows-x64.zip`](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-x64.zip).
2. In File Explorer, right-click the ZIP and select **Extract All**. Do not run the app while it is
   still inside the ZIP. See Microsoft's [ZIP extraction instructions](https://support.microsoft.com/en-us/windows/zip-and-unzip-files-f6dde0a7-0fec-8294-e1d3-703ed85e7ebc).
3. Open the extracted folder and double-click `Cleo.exe`.

The official ZIP contains only `Cleo.exe`.

### First Windows launch

The free classroom build is not commercially code-signed, so Microsoft Defender SmartScreen may
ask you to confirm the first launch. Confirm that the file came from the official repository and
that its checksum matches before choosing **More info → Run anyway**. On a managed device, follow
your organization's policy instead.

### Update or remove on Windows

- **Update:** close Cleo, then run the guided installer again. It safely replaces the managed Cleo
  installation and removes obsolete companion DLLs left by Cleo's older Windows package.
- **Remove:** close Cleo, delete `%LOCALAPPDATA%\Programs\Cleo`, and delete the **Cleo** shortcut
  from `%APPDATA%\Microsoft\Windows\Start Menu\Programs`. Then open PowerShell and run
  `reg.exe delete 'HKCU\Software\sahmsec\Cleo\Installer' /f /reg:64` to remove Cleo's per-user
  installer record. That command targets only Cleo's installer key.

## macOS

### Supported Macs

The current release supports **macOS 11 or later on Apple Silicon** Macs: M1, M2, M3, M4, and
newer Apple chips. Intel Macs do not currently have a public Cleo package.

Choose **Apple menu → About This Mac**. A line labeled **Chip** with an Apple M-series name is
supported; a line labeled **Processor** with Intel is not. See Apple's
[Mac processor guide](https://support.apple.com/en-us/116943).

### Recommended: drag-to-install

1. Download [`Cleo-macOS-Apple-Silicon.dmg`](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-macOS-Apple-Silicon.dmg).
2. Double-click the downloaded DMG.
3. Drag **Cleo** onto the **Applications** shortcut in the DMG window.
4. Eject the **Cleo** disk image.
5. Open **Applications**, then open **Cleo**.

### Optional terminal installation

Open **Terminal**, then run:

```bash
installer="$(mktemp)"
curl -fL 'https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-cleo.sh' -o "$installer" &&
  bash "$installer" --macos
rm -f "$installer"
```

This installs Cleo into `~/Applications` without requesting administrator access.

### First macOS launch

The current package is ad-hoc signed but is not Apple Developer ID signed or notarized. If macOS
blocks it, try opening Cleo once, then go to **System Settings → Privacy & Security** and choose
**Open Anyway** for Cleo. Apple's [unknown-developer app guide](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)
explains this confirmation. Do not disable Gatekeeper or remove quarantine attributes globally.

### Update or remove on macOS

- **Update:** open the newest DMG and replace the existing app, or rerun the terminal installer.
- **Remove:** close Cleo and drag `Cleo.app` from **Applications** or `~/Applications` to the Trash.

## Chromebook

You only need to know that the device is a Chromebook. The installer asks Debian which processor
architecture it uses and selects the correct `.deb` automatically.

### Step 1: enable the Linux development environment

1. Open **Settings**.
2. Select **About ChromeOS → Developers**.
3. Next to **Linux development environment**, select **Set up** and finish the prompts.

Google's [Chromebook Linux setup guide](https://support.google.com/chromebook/answer/9145439?hl=en)
has the current screenshots and requirements. A school or company administrator may disable this
feature; Cleo cannot install on that Chromebook until the administrator enables it.

### Step 2: run the guided Chromebook installer

1. Open the Chromebook Launcher.
2. Open **Linux apps → Terminal**.
3. Copy and run these two lines:

   ```bash
   installer="$(mktemp)"
   curl -fL 'https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-cleo.sh' -o "$installer" &&
     bash "$installer" --chromebook
   rm -f "$installer"
   ```

4. Enter your Linux password if `sudo` asks for it. Nothing is sent to `sudo` until the package
   checksum and package structure have been verified.
5. Open the Chromebook Launcher and select **Linux apps → Cleo**.

### Manual Chromebook package choice

The guided installer is recommended. If you must choose manually, run:

```bash
dpkg --print-architecture
```

| Result | Correct package |
|:--|:--|
| `amd64` | [`Cleo-Chromebook-x64.deb`](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-x64.deb) |
| `arm64` | [`Cleo-Chromebook-arm64.deb`](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-arm64.deb) |

After downloading, move the `.deb` into **Linux files**, double-click it, and choose
**Install with Linux**. ChromeOS documents the Linux development environment for app developers
in its [Linux setup reference](https://developers.google.com/chromeos/app-development/develop/setup).

### Update or remove on Chromebook

- **Update:** rerun the guided Chromebook installer; it selects and verifies the newest package.
- **Remove:** open the Linux Terminal and run `sudo apt-get remove cleo`.

## Linux

This section is for desktop Linux that is **not a Chromebook**.

### Supported Linux systems

Cleo supports 64-bit Intel/AMD (`x86_64`) and 64-bit ARM (`aarch64`/`arm64`) desktop Linux using
glibc and X11/XWayland. Alpine/musl, 32-bit Linux, and headless servers are not supported.

### Recommended: guided terminal installation

Open a terminal and run:

```bash
installer="$(mktemp)"
curl -fL 'https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-cleo.sh' -o "$installer" &&
  bash "$installer" --linux
rm -f "$installer"
```

The installer detects the CPU, verifies the package, installs Cleo under `~/.local`, adds the
`cleo` command, creates an application-menu entry when possible, and opens the app. If a new
terminal does not recognize `cleo`, use the application menu or run
`"$HOME/.local/share/cleo/Cleo"` directly.

### Manual Linux installation

Check the architecture:

```bash
uname -m
```

| Result | Correct package |
|:--|:--|
| `x86_64` or `amd64` | [`Cleo-Linux-x64.tar.gz`](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-x64.tar.gz) |
| `aarch64` or `arm64` | [`Cleo-Linux-arm64.tar.gz`](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-arm64.tar.gz) |

Extract the archive, then run:

```bash
chmod +x Cleo
./Cleo
```

On Debian, Ubuntu, Mint, and similar systems, install missing desktop libraries with:

```bash
sudo apt-get update
sudo apt-get install libx11-6 libice6 libsm6 libfontconfig1
```

Most full desktop installations already contain these libraries. A self-contained .NET build
still relies on normal operating-system components such as glibc, ICU, OpenSSL, zlib, libgcc, and
libstdc++. Avalonia's [Linux requirements](https://docs.avaloniaui.net/docs/platform-specific-guides/linux)
describe the native graphics dependencies.

For Fedora, the equivalent command is `sudo dnf install libX11 libICE libSM fontconfig`. For Arch,
use `sudo pacman -S libx11 libice libsm fontconfig`. Automated release tests use Ubuntu 24.04;
package names and support details can differ on other distributions.

### Update or remove on Linux

- **Update:** rerun the guided Linux installer.
- **Remove:** close Cleo, then delete `~/.local/share/cleo/Cleo`,
  `~/.local/share/cleo/.installed-by-cleo-installer`, `~/.local/bin/cleo`, and
  `~/.local/share/applications/cleo.desktop`, and
  `~/.local/share/icons/hicolor/256x256/apps/in.sahmsec.cleo.png`. Delete the
  `~/.local/share/cleo` directory only if it is empty, so anything you placed beside Cleo is
  preserved.

## Verify a download manually

The guided installers already perform this check. For a manual installation, download
[`SHA256SUMS.txt`](https://github.com/sahmsec/cleo-sqli/releases/latest/download/SHA256SUMS.txt)
beside the package.

### Windows PowerShell

```powershell
Get-FileHash .\Cleo-Windows-x64.zip -Algorithm SHA256
Get-Content .\SHA256SUMS.txt
```

### macOS

```bash
shasum -a 256 Cleo-macOS-Apple-Silicon.dmg
grep 'Cleo-macOS-Apple-Silicon.dmg' SHA256SUMS.txt
```

### Linux or Chromebook

```bash
# Linux x64 example
sha256sum Cleo-Linux-x64.tar.gz
grep 'Cleo-Linux-x64.tar.gz' SHA256SUMS.txt

# Chromebook x64 example
sha256sum Cleo-Chromebook-x64.deb
grep 'Cleo-Chromebook-x64.deb' SHA256SUMS.txt
```

For an ARM64 download, use its `arm64` filename in both commands.

The same 64 hexadecimal characters must appear beside the same filename. Uppercase versus
lowercase does not matter. The checksum detects corruption; release authenticity still depends
on downloading through the official GitHub repository over HTTPS.

## How installation is tested

CI parses both installers and runs ShellCheck on the Bash installer. It validates documented
package filenames and local file links, rejects known unsafe installation patterns, then performs
install/update and GUI smoke tests on Windows Server 2025 x64, Ubuntu 24.04 x64/ARM64, and macOS 15
ARM64. The release workflow also passes each newly built package through the same installer
validation before publishing it.

Both Chromebook package architectures are checksum-validated, inspected, installed through
Debian's package manager, and removed on matching Ubuntu x64 and ARM64 runners. Those checks cover
package identity, dependencies, processor, executable, desktop entry, icon, file permissions, and
absence of unexpected package scripts. CI does not emulate ChromeOS or test the physical
Chromebook launcher.

## Common problems

### I downloaded “Source code”

Delete it and return to the [latest release](https://github.com/sahmsec/cleo-sqli/releases/latest).
GitHub adds **Source code (zip)** and **Source code (tar.gz)** automatically, but neither one is an
installer. Choose a file whose name begins with `Cleo-Windows`, `Cleo-macOS`, `Cleo-Linux`, or
`Cleo-Chromebook`.

### The installer says the processor is unsupported

Do not try a random package. Open an issue with the detection command's result. Current releases
do not support Windows ARM64, 32-bit systems, Intel Macs, Alpine/musl Linux, or ARM32 Linux.

### The checksum does not match

Do not open or install the file. Delete it, wait a few minutes, and retry from the official release
page. If it fails again, report the filename and expected/actual hashes.

### Cleo opens and immediately closes on Linux

Run the full installed path from a terminal so the error remains visible:

```bash
"$HOME/.local/share/cleo/Cleo"
```

Install any missing desktop libraries reported by the terminal. Cleo needs a graphical desktop;
it will not run on a headless server.

### The Linux file shows a generic gear instead of the Cleo logo

That does not mean the executable is damaged. Most Linux file managers do not read an application
icon from a standalone ELF executable, so a manually extracted `Cleo` file receives a generic
gear. The guided installer adds an application-menu launcher and installs Cleo's original logo at
`~/.local/share/icons/hicolor/256x256/apps/in.sahmsec.cleo.png`; open **Cleo** from the application
menu to see the correct icon. The Linux release archive still contains only the one executable.

The Chromebook package includes the same PNG for its Linux-app launcher. The macOS package builds
the same artwork into `Cleo.icns`, so Finder and the Dock can display it.

### The Chromebook has no Linux option

Update ChromeOS and check **Settings → About ChromeOS → Developers**. On managed devices, only the
administrator can enable Linux. There is no Windows, macOS, or Android Cleo package that should be
substituted on ChromeOS.

## Asking for help

Open an [installation issue](https://github.com/sahmsec/cleo-sqli/issues) and include:

1. whether the device is Windows, Mac, Chromebook, or Linux;
2. the exact installer/package filename;
3. the complete error message;
4. the output of the matching command:

   - Windows PowerShell: `[Runtime.InteropServices.RuntimeInformation]::OSArchitecture`
   - macOS or Linux: `uname -m`
   - Chromebook Linux Terminal: `dpkg --print-architecture`

Do not include passwords, access tokens, private target URLs, or confidential scan results.
