# Install Cleo

Choose your system below. Cleo is self-contained: you do not need .NET or the source code.

> [!IMPORTANT]
> Download Cleo only from [`sahmsec/cleo-sqli`](https://github.com/sahmsec/cleo-sqli), and use it
> only on systems you own or have explicit permission to test.

## Choose your system

1. [Windows](#windows)
2. [macOS](#macos)
3. [Linux](#linux)
4. [Chromebook](#chromebook)

The guided installers pin one release, download the matching CPU package over HTTPS, verify its
entry in `SHA256SUMS.txt`, inspect the package, and remove temporary files. They do not weaken
Defender, Gatekeeper, TLS, or execution-policy settings.

You can run a guided command from any terminal folder. A normal installation uses a private
temporary workspace and removes the temporary release package automatically. Use the explicit
`--download-only` option when you want to keep a verified package without installing it.

| System | Guided installation location |
|:--|:--|
| Windows | The current user's real `Desktop\Cleo.exe`, including a redirected or OneDrive Desktop |
| macOS | `~/Applications/Cleo.app` |
| Linux | `~/.local/share/cleo/Cleo`, plus a command and application-menu launcher |
| Chromebook | Debian-managed `/usr/bin/cleo` and launcher files |

## Windows

Cleo supports Windows 10 22H2 and Windows 11 on 64-bit Intel/AMD computers. Native Windows ARM64
is supported on Windows 11. Windows ARM32, x86/32-bit Windows, and older Windows versions are not
supported.

### Guided installation

Open Terminal or Windows PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-windows.ps1 | iex
```

The installer detects x64 versus ARM64, downloads the matching ZIP, verifies it, places the one
`Cleo.exe` file directly on the Desktop (not inside another folder), and opens Cleo. It does not
create a shortcut. Rerun the same command to update.

If policy blocks PowerShell scripts, do not change the policy. Use the manual ZIP method.

### Manual installation

In **Settings → System → About**, check **System type**, then download the matching file:

- [Intel/AMD x64 ZIP](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-x64.zip)
- [Windows ARM64 ZIP](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-arm64.zip)

Extract the ZIP before opening `Cleo.exe`; do not run it from inside the ZIP.
Windows 10 and Windows 11 both include ZIP extraction in File Explorer, so no third-party unzip
program is required. Right-click the downloaded ZIP, select **Extract All**, and follow the prompt.

The free classroom build is not commercially code-signed. Defender SmartScreen may ask you to
confirm the first launch. Verify the source and checksum before selecting **More info → Run
anyway**, and follow organizational policy on managed devices.

### Remove Windows installation

Close Cleo and delete `Desktop\Cleo.exe`. To remove the installer's per-user ownership record, run:

```powershell
reg.exe delete 'HKCU\Software\sahmsec\Cleo\Installer' /f /reg:64
```

## macOS

Cleo supports macOS 11 or later on Apple Silicon Macs. Intel Macs are not supported.

### Guided terminal installation

Open Terminal and run:

```bash
installer="$(mktemp)"
curl -fL 'https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-cleo.sh' -o "$installer" &&
  bash "$installer" --macos
rm -f "$installer"
```

The command verifies the DMG and installs Cleo without administrator access at:

```text
~/Applications/Cleo.app
```

This is your personal Applications folder, not the system `/Applications` folder opened by
Finder's usual Applications shortcut. After installation, the command reveals Cleo in Finder,
attempts its first launch, and prints both the exact path and a reusable launch command.

The build is ad-hoc signed but is not Apple Developer ID signed or notarized. If the first launch
is blocked, open **System Settings → Privacy & Security**, select **Open Anyway** for Cleo, and open
it again. Do not disable Gatekeeper or remove quarantine protection globally.

### Download only or install manually

To save a verified DMG in the current Terminal folder without installing or launching Cleo:

```bash
installer="$(mktemp)"
curl -fL 'https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-cleo.sh' -o "$installer" &&
  bash "$installer" --macos --download-only "$PWD"
rm -f "$installer"
```

Alternatively, download
[`Cleo-macOS-Apple-Silicon.dmg`](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-macOS-Apple-Silicon.dmg),
open it, drag **Cleo** to **Applications**, and eject the disk image.

To update, rerun the terminal installer or replace the app from the newest DMG. To remove it, close
Cleo and move `~/Applications/Cleo.app` or `/Applications/Cleo.app` to the Trash.

## Linux

Cleo supports graphical 64-bit glibc Linux on Intel/AMD (`x86_64`) and ARM64
(`aarch64`/`arm64`). Alpine/musl, ARM32, 32-bit, and headless systems are not supported.

Open a terminal and run:

```bash
installer="$(mktemp)"
curl -fL 'https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-cleo.sh' -o "$installer" &&
  bash "$installer" --linux
rm -f "$installer"
```

The installer selects the CPU package, installs Cleo under `~/.local`, adds the `cleo` command and
an application-menu entry, then opens it. Rerun the command to update. Remove these managed paths
to uninstall:

```text
~/.local/share/cleo
~/.local/bin/cleo
~/.local/share/applications/cleo.desktop
~/.local/share/icons/hicolor/256x256/apps/in.sahmsec.cleo.png
```

For a package-only download, add `--download-only "$PWD"`. Manual packages are
`Cleo-Linux-x64.tar.gz` and `Cleo-Linux-arm64.tar.gz` on the
[latest release](https://github.com/sahmsec/cleo-sqli/releases/latest).

## Chromebook

Cleo runs inside the ChromeOS Linux development environment on amd64 and ARM64 devices.

1. Enable **Settings → About ChromeOS → Developers → Linux development environment**.
2. Open the Linux Terminal and run:

```bash
installer="$(mktemp)"
curl -fL 'https://raw.githubusercontent.com/sahmsec/cleo-sqli/main/install/install-cleo.sh' -o "$installer" &&
  bash "$installer" --chromebook
rm -f "$installer"
```

The installer uses `dpkg --print-architecture` to select `Cleo-Chromebook-x64.deb` or
`Cleo-Chromebook-arm64.deb`, verifies it, and gives it to Debian's package manager. Debian may ask
for the Linux password and download declared desktop-library dependencies. Update by rerunning the
command; remove with `sudo apt-get remove cleo`.

## Verify a download manually

Download `SHA256SUMS.txt` from the same release as the package.

Windows:

```powershell
Get-FileHash .\Cleo-Windows-x64.zip -Algorithm SHA256
Get-FileHash .\Cleo-Windows-arm64.zip -Algorithm SHA256
Get-Content .\SHA256SUMS.txt
```

macOS:

```bash
shasum -a 256 Cleo-macOS-Apple-Silicon.dmg
grep 'Cleo-macOS-Apple-Silicon.dmg' SHA256SUMS.txt
```

Linux or Chromebook:

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
```

The value for your file must match exactly. **Source code (zip)** and **Source code (tar.gz)** are
GitHub repository snapshots, not application downloads.

## How installation is tested

Each release is built and checked on native GitHub-hosted x64 and ARM64 runners. Windows and Linux
applications receive native launch smoke tests. Chromebook packages are inspected and installed in
their matching Debian architecture. On Apple Silicon, CI verifies the DMG, app bundle, signature,
ARM64 executable, installation/update path, and download-only path without launching the GUI.

The workflows also verify exact package layouts, published checksums, repeatable updates, cleanup,
and anonymous access to the public files.

## Common problems

- **The installer says the architecture is unsupported:** use a supported 64-bit device. Windows
  ARM64 requires Windows 11; Intel Macs are unsupported.
- **Cleo seems missing on macOS:** the terminal installer uses `~/Applications/Cleo.app`. Rerun it
  to reveal the app, or run `open -R "$HOME/Applications/Cleo.app"`.
- **macOS blocks Cleo:** approve the one-time launch under **Privacy & Security → Open Anyway**.
- **A checksum fails:** delete the package and download it again from the official release. Do not
  install a package whose checksum does not match.
- **A requested old version returns 404:** only the currently public release is downloadable;
  previous versions are retained as drafts.
- **Chromebook reports `dpkg` is missing:** run the command inside the Chromebook Linux Terminal.

## Asking for help

Open an [issue](https://github.com/sahmsec/cleo-sqli/issues) with your operating system version,
CPU architecture, the package name, and the complete installer error. Do not include passwords,
tokens, private target URLs, or other secrets.
