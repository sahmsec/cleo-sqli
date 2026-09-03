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

This repository is the official binary distribution for Cleo. You do not need to build the
application or install .NET.

Each supported platform has **one file to download**. Windows and Linux unpack to one executable.
The DMG and DEB are single OS-native installer files; their internal app metadata, menu entry, and
icon are packaging components, not companion runtime DLLs.

## Start here

Choose your system—**Windows, Mac, Linux, or Chromebook**—in the
[step-by-step installation guide](INSTALLATION.md). You do not need to know the processor: the
guided installer selects the correct supported architecture and verifies the download.

The guided installer keeps the checksum-verified release package in the folder where you run its
terminal command and prints that package's absolute path. The installed app still goes to the
normal location for your system; the ZIP, DMG, tarball, or DEB left in your chosen folder is your
download copy to keep or delete later.

## Direct downloads

Every button points to the latest release. Only the current version remains publicly listed;
previous versions are retained as drafts so they cannot be mistaken for the recommended download.
Their draft release records, release notes, and uploaded app binaries are hidden from ordinary
public readers and visible only to repository maintainers and collaborators with push access. The
public Git tag pages and automatically generated repository source snapshots remain available, but
old app binaries and pinned release-download URLs do not. If you are uncertain, use the guide above
instead of guessing.

| Platform | Supported device | Package | Download |
|:--|:--|:--:|:--:|
| Windows | Windows 10 22H2/11, 64-bit Intel or AMD | `.zip` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-x64.zip"><img src="https://img.shields.io/badge/Download-0078D4?style=for-the-badge" alt="Download Windows x64" width="132" height="32"></a> |
| macOS | macOS 11+, Apple Silicon | `.dmg` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-macOS-Apple-Silicon.dmg"><img src="https://img.shields.io/badge/Download-111111?style=for-the-badge" alt="Download macOS Apple Silicon" width="132" height="32"></a> |
| Linux | 64-bit Intel/AMD Linux | `.tar.gz` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-x64.tar.gz"><img src="https://img.shields.io/badge/Download-FCC624?style=for-the-badge" alt="Download Linux x64" width="132" height="32"></a> |
| Linux | 64-bit ARM Linux | `.tar.gz` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-arm64.tar.gz"><img src="https://img.shields.io/badge/Download-FCC624?style=for-the-badge" alt="Download Linux ARM64" width="132" height="32"></a> |
| Chromebook | Intel/AMD Linux environment | `.deb` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-x64.deb"><img src="https://img.shields.io/badge/Download-4285F4?style=for-the-badge" alt="Download Chromebook x64" width="132" height="32"></a> |
| Chromebook | 64-bit ARM (ARM64) Linux environment | `.deb` | <a href="https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-arm64.deb"><img src="https://img.shields.io/badge/Download-4285F4?style=for-the-badge" alt="Download Chromebook ARM64" width="132" height="32"></a> |

The [latest release page](https://github.com/sahmsec/cleo-sqli/releases/latest) also contains
`SHA256SUMS.txt`. That file is verification data, not an installer. Do not download GitHub's
automatically generated **Source code** archives; those are repository snapshots, not Cleo.

## Installation summary

| Platform | Recommended method |
|:--|:--|
| **Windows** | Run the guided PowerShell installer, or extract the ZIP and open `Cleo.exe`. |
| **macOS** | Open the DMG and drag **Cleo** into **Applications**. Apple Silicon only. |
| **Linux** | Run the guided terminal installer; it detects x64 versus ARM64. |
| **Chromebook** | Enable the Linux development environment, then run the Chromebook command in the guide. It detects the package automatically. |

See [Detailed installation instructions](INSTALLATION.md) for exact commands, first-launch
warnings, updates, uninstallation, and troubleshooting.

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
> Discovered tables and columns stay available during the current session. Use **Clean All** when
> you want to reset the workspace and begin with a different target.

## Support

If installation fails, use the support checklist at the bottom of the
[installation guide](INSTALLATION.md#asking-for-help), then open an
[issue](https://github.com/sahmsec/cleo-sqli/issues).

## License

Cleo is free to use for personal learning, classroom instruction, and explicitly authorized
security testing. The application is distributed under the
[Cleo Educational Binary License](LICENSE.md); it is not open-source software.

---

<p align="center"><sub>Cleo is intended for authorized security education and testing only.</sub></p>
