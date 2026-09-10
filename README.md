<p align="center">
  <img src="assets/cleo.png" alt="Cleo icon" width="120">
</p>

<h1 align="center">Cleo</h1>

<p align="center">A self-contained desktop learning tool for authorized MySQL security testing.</p>

<p align="center">
  <a href="https://github.com/sahmsec/cleo-sqli/releases/latest"><img src="https://img.shields.io/github/v/release/sahmsec/cleo-sqli?display_name=tag&sort=semver&style=flat-square&label=latest" alt="Latest release"></a>
  <a href="https://github.com/sahmsec/cleo-sqli/releases/latest"><img src="https://img.shields.io/github/downloads/sahmsec/cleo-sqli/total?style=flat-square&label=downloads" alt="Total downloads"></a>
</p>

> [!IMPORTANT]
> Use Cleo only on systems you own or have explicit permission to test.

This is Cleo's official binary-distribution repository. The downloads include the required .NET
runtime, so users do not need to build the application or install .NET.

## Install Cleo

Choose Windows, macOS, Linux, or Chromebook here:

### [INSTALLATION GUIDE](INSTALLATION.md)

The guided Windows, Linux, and Chromebook installers select the supported CPU package
automatically. The macOS command installs Cleo for the current user and reveals it in Finder.

## Direct downloads

| Platform | Supported device | Download |
|:--|:--|:--:|
| Windows | Windows 10 22H2/11, 64-bit Intel or AMD | [x64 ZIP](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-x64.zip) |
| Windows | Windows 11 on ARM64 | [ARM64 ZIP](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Windows-arm64.zip) |
| macOS | macOS 11+, Apple Silicon | [Apple Silicon DMG](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-macOS-Apple-Silicon.dmg) |
| Linux | 64-bit Intel/AMD glibc desktop | [x64 tarball](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-x64.tar.gz) |
| Linux | 64-bit ARM glibc desktop | [ARM64 tarball](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Linux-arm64.tar.gz) |
| Chromebook | Intel/AMD Linux environment | [amd64 DEB](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-x64.deb) |
| Chromebook | ARM64 Linux environment | [ARM64 DEB](https://github.com/sahmsec/cleo-sqli/releases/latest/download/Cleo-Chromebook-arm64.deb) |

Each release also provides `SHA256SUMS.txt`. Do not use GitHub's automatically generated
**Source code (zip)** or **Source code (tar.gz)** archives; they are not Cleo application packages.

Only the current stable release is downloadable. Previous versions are retained as drafts: their
draft release records, release notes, and uploaded app binaries are hidden from ordinary public
readers but remain available to repository maintainers and collaborators with push access. The
public Git tag pages and source snapshots remain available.

## Support and license

For installation problems, follow the short checklist in the
[installation guide](INSTALLATION.md#asking-for-help), then open an
[issue](https://github.com/sahmsec/cleo-sqli/issues).

Cleo is distributed under the [Cleo Educational Binary License](LICENSE.md). It is free to use for
personal learning, classroom instruction, and explicitly authorized security testing; it is not
open-source software.
