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

## Download Cleo

Choose the build that matches your device. Every button points directly to the latest
release—no account or extra runtime is required.

| Platform | Device | Binary type | Download |
|:--|:--|:--:|:--:|
| Windows | 64-bit Intel/AMD | `.zip` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-x64.zip"><img src="https://img.shields.io/badge/Download-0078D4?style=for-the-badge" alt="Download Windows x64" width="132" height="32"></a> |
| macOS | Apple Silicon (M1, M2, M3, M4, or newer) | `.dmg` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-macOS-Apple-Silicon.dmg"><img src="https://img.shields.io/badge/Download-111111?style=for-the-badge" alt="Download macOS ARM64" width="132" height="32"></a> |
| Linux | 64-bit Intel/AMD | `.tar.gz` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-x64.tar.gz"><img src="https://img.shields.io/badge/Download-FCC624?style=for-the-badge" alt="Download Linux x64" width="132" height="32"></a> |
| Linux | ARM64 | `.tar.gz` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-arm64.tar.gz"><img src="https://img.shields.io/badge/Download-FCC624?style=for-the-badge" alt="Download Linux ARM64" width="132" height="32"></a> |
| Chromebook | Intel/AMD Linux environment | `.deb` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-x64.deb"><img src="https://img.shields.io/badge/Download-4285F4?style=for-the-badge" alt="Download Chromebook x64" width="132" height="32"></a> |
| Chromebook | ARM Linux environment | `.deb` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-arm64.deb"><img src="https://img.shields.io/badge/Download-4285F4?style=for-the-badge" alt="Download Chromebook ARM64" width="132" height="32"></a> |

You can also open the [latest release page](https://github.com/sahmsec/cleo-sqli/releases/latest)
to see every download and its checksum file.

## Install

| Platform | What to do |
|:--|:--|
| **Windows** | Download the ZIP, choose **Extract All**, open the extracted folder, and double-click `Cleo.exe`. |
| **macOS** | Open the DMG and drag **Cleo** into **Applications**. This build supports Apple Silicon Macs. |
| **Linux** | Extract the `.tar.gz`, allow the `Cleo` file to run as a program in its file properties, then open it. |
| **Chromebook** | Enable **Linux development environment**, download the correct `.deb`, double-click it, and choose **Install with Linux**. |

> [!NOTE]
> Windows may show a SmartScreen message because the app is not commercially code-signed.
> On macOS, use **System Settings → Privacy & Security → Open Anyway** if the first launch
> is blocked. These warnings are expected for the free classroom builds.

## How to use Cleo

<p align="center">
  <strong>Target</strong> &nbsp;→&nbsp; <strong>Scan</strong> &nbsp;→&nbsp;
  <strong>Tables</strong> &nbsp;→&nbsp; <strong>Columns</strong> &nbsp;→&nbsp; <strong>Data</strong>
</p>

1. Paste the URL of an **authorized practice target** into the target field.
2. Click <kbd>Load Target</kbd>, then <kbd>Start Scan</kbd> and wait for the scan to finish.
3. Click <kbd>Get Tables</kbd> to discover the database structure shown in the left sidebar.
4. Open a table and click <kbd>Get Columns</kbd> to load its available columns.
5. Select up to **six columns**, then click <kbd>Get Data</kbd>.
6. Review the extracted rows in the main output table. Use **Save Results** or **Export Data**
   when you want to keep them.

> [!TIP]
> Discovered tables and columns stay available during the current session. You can collapse
> and reopen them without running the same step again. Use **Clean All** when you want to
> reset the workspace and begin with a different target.

## Support

If a download or installation fails, open an
[issue](https://github.com/sahmsec/cleo-sqli/issues) and include your operating system,
processor type, and the exact error message.

---

<p align="center"><sub>Cleo is intended for authorized security education and testing only.</sub></p>
