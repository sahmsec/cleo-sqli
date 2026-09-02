<p align="center">
  <img src="assets/cleo.png" alt="Cleo icon" width="120">
</p>

<h1 align="center">Cleo</h1>

<p align="center">
  A desktop learning tool for authorized MySQL security testing.
</p>

<p align="center">
  <a href="https://github.com/sahmsec/cleo-sqli/releases/latest"><img src="https://img.shields.io/github/v/release/sahmsec/cleo-sqli?display_name=tag&sort=semver&style=flat-square&label=latest" alt="Latest release"></a>
  <a href="https://github.com/sahmsec/cleo-sqli/releases/latest"><img src="https://img.shields.io/github/downloads/sahmsec/cleo-sqli/total?style=flat-square&label=downloads" alt="Total downloads"></a>
</p>

> [!IMPORTANT]
> Use Cleo only on systems you own or have explicit permission to test.

This repository is the official **binary distribution** for Cleo. The downloads are
self-contained, so students do not need to install .NET or build anything from source.

## Download

Choose the file that matches your device. Every button always points to the latest release.

| Platform | Device | Download |
|:--|:--|:--:|
| Windows | 64-bit Intel/AMD | [![Download Windows](https://img.shields.io/badge/Download-Windows_x64-0078D4?style=for-the-badge&logo=windows11&logoColor=white)](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-x64.zip) |
| macOS | Apple Silicon (M1, M2, M3, M4, or newer) | [![Download macOS](https://img.shields.io/badge/Download-macOS_ARM64-111111?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-macOS-Apple-Silicon.dmg) |
| Linux | 64-bit Intel/AMD | [![Download Linux x64](https://img.shields.io/badge/Download-Linux_x64-FCC624?style=for-the-badge&logo=linux&logoColor=111111)](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-x64.tar.gz) |
| Linux | ARM64 | [![Download Linux ARM64](https://img.shields.io/badge/Download-Linux_ARM64-FCC624?style=for-the-badge&logo=linux&logoColor=111111)](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-arm64.tar.gz) |
| Chromebook | Intel/AMD Linux environment | [![Download Chromebook x64](https://img.shields.io/badge/Download-Chromebook_x64-4285F4?style=for-the-badge&logo=googlechrome&logoColor=white)](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-x64.deb) |
| Chromebook | ARM Linux environment | [![Download Chromebook ARM64](https://img.shields.io/badge/Download-Chromebook_ARM64-4285F4?style=for-the-badge&logo=googlechrome&logoColor=white)](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-arm64.deb) |

You can also open the [latest release page](https://github.com/sahmsec/cleo-sqli/releases/latest)
to see every download and its checksum file.

## Install from a terminal

### Windows 10 or 11 (x64)

Open **PowerShell**, then run:

```powershell
$url = "https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-x64.zip"
Invoke-WebRequest -Uri $url -OutFile "Cleo-Windows-x64.zip"
Expand-Archive ".\Cleo-Windows-x64.zip" -DestinationPath ".\Cleo" -Force
Start-Process ".\Cleo\Cleo.exe"
```

You can move the extracted `Cleo` folder anywhere you like. Windows may show a
SmartScreen message on first launch because this free classroom build is not
commercially code-signed.

### macOS (Apple Silicon)

This build supports Apple Silicon Macs. Check yours with `uname -m`; it should print `arm64`.

```bash
curl -fL "https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-macOS-Apple-Silicon.dmg" -o Cleo.dmg
open Cleo.dmg
```

Drag **Cleo** into **Applications**. On the first launch, macOS may block the app because it
is not notarized with a paid Apple Developer account. Open **System Settings → Privacy &
Security**, find the Cleo message, and click **Open Anyway**. You only need to do this once.

### Linux (x64 or ARM64)

This command detects the processor, downloads the correct package, and starts Cleo:

```bash
case "$(uname -m)" in
  x86_64)        file="Cleo-Linux-x64.tar.gz" ;;
  aarch64|arm64) file="Cleo-Linux-arm64.tar.gz" ;;
  *) echo "Unsupported processor: $(uname -m)"; exit 1 ;;
esac

curl -fL "https://github.com/sahmsec/cleo-sqli/releases/latest/download/$file" -o "$file"
mkdir -p "$HOME/.local/opt/cleo"
tar -xzf "$file" -C "$HOME/.local/opt/cleo"
chmod +x "$HOME/.local/opt/cleo/Cleo"
"$HOME/.local/opt/cleo/Cleo"
```

If your Linux distribution reports a missing desktop library, install its packages for
X11, ICE, SM, Fontconfig, and CA certificates through your normal package manager.

### Chromebook (Linux environment)

First enable **Settings → About ChromeOS → Developers → Linux development environment**.
Then open the Linux Terminal and run:

```bash
case "$(dpkg --print-architecture)" in
  amd64) file="Cleo-Chromebook-x64.deb" ;;
  arm64) file="Cleo-Chromebook-arm64.deb" ;;
  *) echo "Unsupported processor: $(dpkg --print-architecture)"; exit 1 ;;
esac

curl -fL "https://github.com/sahmsec/cleo-sqli/releases/latest/download/$file" -o "$file"
sudo apt install "./$file"
cleo
```

After installation, Cleo also appears in the Chromebook Linux apps menu.

## Verify a download

Each release includes `SHA256SUMS.txt`. Download it from the
[latest release page](https://github.com/sahmsec/cleo-sqli/releases/latest), then compare the
listed checksum with your file.

Windows PowerShell:

```powershell
Get-FileHash ".\Cleo-Windows-x64.zip" -Algorithm SHA256
```

macOS or Linux:

```bash
shasum -a 256 Cleo-macOS-Apple-Silicon.dmg   # macOS
sha256sum Cleo-Linux-x64.tar.gz              # Linux example
```

## Support

If a download or installation fails, open an
[issue](https://github.com/sahmsec/cleo-sqli/issues) and include your operating system,
processor type, and the exact error message.

---

<p align="center"><sub>Cleo is intended for authorized security education and testing only.</sub></p>
