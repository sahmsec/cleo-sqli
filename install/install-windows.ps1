#requires -Version 5.1
<#
.SYNOPSIS
Installs the current 64-bit Windows release of Cleo for the current user.

.DESCRIPTION
The installer detects the native Windows architecture, resolves one immutable
release tag, downloads the Windows ZIP and its published SHA-256 manifest,
verifies both the checksum and archive layout, and installs Cleo without
requesting elevation or changing PowerShell security settings. The verified
release ZIP is retained in the terminal's original working directory.

Rerunning the installer replaces a Cleo installation recorded for the current
user. An exact four-file legacy Cleo installation is migrated automatically.
-Force is needed when the destination contains unmarked or unexpected files,
or when an existing Start Menu shortcut points somewhere else.

.PARAMETER Version
Release version to request in MAJOR.MINOR.PATCH form, with an optional leading
"v". Only the currently public release is downloadable; omit this parameter to
install the latest release.

.PARAMETER InstallDirectory
Destination directory. The default is
%LOCALAPPDATA%\Programs\Cleo.

.PARAMETER AssetDirectory
Offline/test source directory containing Cleo-Windows-x64.zip and
SHA256SUMS.txt. When supplied, no network request is made.

.PARAMETER NoShortcut
Do not create or update the current user's Start Menu shortcut.

.PARAMETER NoLaunch
Do not start Cleo after installation.

.PARAMETER Force
Allow replacement of an unrecognized destination directory or shortcut.

.NOTES
If Windows or an organization policy blocks PowerShell scripts, do not change
the machine or user execution policy. Follow the manual ZIP instructions in
the Cleo installation guide instead.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $Version,

    [Parameter()]
    [string] $InstallDirectory,

    [Parameter()]
    [string] $AssetDirectory,

    [Parameter()]
    [switch] $NoShortcut,

    [Parameter()]
    [switch] $NoLaunch,

    [Parameter()]
    [switch] $Force
)

Set-StrictMode -Version 2.0

function Test-PathContainsLineBreak {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return $Path.IndexOfAny([char[]] "`r`n") -ge 0
}

# Capture the caller's location before the installer creates or enters any
# staging location. This is intentionally based on the PowerShell location,
# not on the script file (which does not exist when invoked through irm | iex).
$invocationLocation = Get-Location
if ($null -eq $invocationLocation.Provider -or
    $invocationLocation.Provider.Name -ne 'FileSystem') {
    throw 'Run the Cleo installer from a file-system directory. The verified release package is retained in the directory where the terminal was opened.'
}
$originalWorkingDirectory = [IO.Path]::GetFullPath($invocationLocation.ProviderPath)
if (Test-PathContainsLineBreak -Path $originalWorkingDirectory) {
    throw 'The original working directory contains a line-break character and cannot be used as the retained-package destination.'
}

$Repository = 'sahmsec/cleo-sqli'
$AssetName = 'Cleo-Windows-x64.zip'
$ChecksumName = 'SHA256SUMS.txt'
$ExecutableName = 'Cleo.exe'
$InstallerPrefix = 'cleo-installer-'
$BundleIdentifier = 'in.sahmsec.cleo'
$OwnershipRegistrySubKey = 'Software\sahmsec\Cleo\Installer'
$OwnershipRegistryDisplayPath = 'HKEY_CURRENT_USER\Software\sahmsec\Cleo\Installer'
$OwnershipBundleValueName = 'BundleId'
$OwnershipPathValueName = 'InstallPath'

function Test-SamePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $First,

        [Parameter(Mandatory = $true)]
        [string] $Second
    )

    return [string]::Equals(
        [IO.Path]::GetFullPath($First).TrimEnd('\', '/'),
        [IO.Path]::GetFullPath($Second).TrimEnd('\', '/'),
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Test-PathAtOrBelowDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    if ([string]::Equals($fullPath, $fullDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $directoryPrefix = $fullDirectory + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($directoryPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-FileSystemPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Description cannot be empty."
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    $provider = $null
    $drive = $null
    try {
        $providerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
            $expanded,
            [ref] $provider,
            [ref] $drive
        )
    }
    catch {
        throw "$Description is not a valid file-system path: $Path"
    }

    if ($null -eq $provider -or $provider.Name -ne 'FileSystem') {
        throw "$Description must use the file system, not a PowerShell provider path: $Path"
    }
    return [IO.Path]::GetFullPath($providerPath)
}

function Get-NativeWindowsArchitecture {
    if (-not [string]::Equals($env:OS, 'Windows_NT', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'This installer runs only on Windows. See the installation guide for Linux, macOS, and Chromebook instructions.'
    }

    # IsWow64Process2 reports the host machine type even when this PowerShell
    # process is x86/x64 code emulated by Windows on ARM. Environment variables
    # and RuntimeInformation can report the emulated architecture in that case.
    try {
        $nativeMethods = 'CleoInstaller.NativeMethods' -as [type]
        if ($null -eq $nativeMethods) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CleoInstaller
{
    public static class NativeMethods
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWow64Process2(
            IntPtr process,
            out ushort processMachine,
            out ushort nativeMachine);
    }
}
'@
        }

        [UInt16] $processMachine = 0
        [UInt16] $nativeMachine = 0
        $processHandle = [Diagnostics.Process]::GetCurrentProcess().Handle
        if ([CleoInstaller.NativeMethods]::IsWow64Process2(
                $processHandle,
                [ref] $processMachine,
                [ref] $nativeMachine)) {
            switch ($nativeMachine) {
                0x8664 { return 'x64' }
                0x014c { return 'x86' }
                0xaa64 { return 'arm64' }
                0x01c4 { return 'arm' }
                default { return ('machine-0x{0:x4}' -f $nativeMachine) }
            }
        }
    }
    catch [EntryPointNotFoundException] {
        # Windows versions predating IsWow64Process2 cannot be Windows on ARM64;
        # use the long-established environment-variable detection below.
    }
    catch {
        # Add-Type can be restricted by enterprise PowerShell policy. Fall back
        # without weakening that policy or requesting elevation.
    }

    # PROCESSOR_ARCHITEW6432 reports the native operating-system architecture
    # when a 32-bit or emulated PowerShell process is running. This prevents a
    # 32-bit process from mistaking a 64-bit Windows installation for x86.
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = $env:PROCESSOR_ARCHITECTURE
    }

    if ([string]::IsNullOrWhiteSpace($architecture)) {
        # RuntimeInformation is present on current Windows installations, but
        # the environment-variable path above also supports older PowerShell
        # 5.1/.NET Framework combinations.
        try {
            $architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        }
        catch {
            throw 'Windows architecture could not be detected safely. Cleo currently provides a Windows x64 build only.'
        }
    }

    switch ($architecture.Trim().ToUpperInvariant()) {
        { $_ -in @('AMD64', 'X64') } { return 'x64' }
        { $_ -in @('X86', 'I386', 'I686') } { return 'x86' }
        { $_ -in @('ARM64', 'AARCH64') } { return 'arm64' }
        { $_ -in @('ARM', 'ARM32') } { return 'arm' }
        default { return $architecture.Trim().ToLowerInvariant() }
    }
}

function Get-WindowsVersionDetails {
    $baseKey = $null
    $versionKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $versionKey = $baseKey.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion', $false)
        if ($null -eq $versionKey) {
            throw 'Windows version registry key was not found.'
        }

        $buildText = [string] $versionKey.GetValue('CurrentBuildNumber', '')
        if ([string]::IsNullOrWhiteSpace($buildText)) {
            $buildText = [string] $versionKey.GetValue('CurrentBuild', '')
        }
        [Int32] $build = 0
        if (-not [Int32]::TryParse($buildText, [ref] $build) -or $build -le 0) {
            throw "Windows returned an invalid build number: $buildText"
        }

        $productName = [string] $versionKey.GetValue('ProductName', 'Windows')
        $installationType = [string] $versionKey.GetValue('InstallationType', '')
        $isServer = $installationType.StartsWith('Server', [StringComparison]::OrdinalIgnoreCase) -or
            $productName.IndexOf('Server', [StringComparison]::OrdinalIgnoreCase) -ge 0
        if (-not $isServer -and $build -ge 22000 -and
            $productName.IndexOf('Windows 10', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            # ProductName is known to retain "Windows 10" after some Windows
            # 11 upgrades; the build boundary is the authoritative distinction.
            $productName = $productName -replace '(?i)Windows 10', 'Windows 11'
        }

        return [pscustomobject] @{
            Build = $build
            ProductName = $productName
            IsServer = $isServer
        }
    }
    catch {
        # Registry access can be restricted on managed devices. CIM is a
        # read-only fallback and does not request administrator privileges.
        try {
            $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            [Int32] $build = 0
            if (-not [Int32]::TryParse([string] $operatingSystem.BuildNumber, [ref] $build) -or
                $build -le 0) {
                throw 'CIM returned an invalid Windows build number.'
            }
            return [pscustomobject] @{
                Build = $build
                ProductName = [string] $operatingSystem.Caption
                IsServer = ([Int32] $operatingSystem.ProductType -ne 1)
            }
        }
        catch {
            throw 'The Windows version could not be detected safely. Cleo requires Windows 10 22H2 (build 19045), Windows 11, or a currently supported Windows Server release.'
        }
    }
    finally {
        if ($null -ne $versionKey) { $versionKey.Dispose() }
        if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
}

function Assert-SupportedWindowsVersion {
    $details = Get-WindowsVersionDetails
    if ($details.IsServer) {
        $minimumBuild = 14393
        $minimumName = 'Windows Server 2016 (build 14393)'
    }
    else {
        $minimumBuild = 19045
        $minimumName = 'Windows 10 22H2 (build 19045)'
    }

    if ([Int32] $details.Build -lt $minimumBuild) {
        throw "Unsupported Windows version: detected $($details.ProductName), build $($details.Build). Cleo requires $minimumName or newer."
    }

    Write-Host "Detected $($details.ProductName), build $($details.Build) (x64)."
    return $details
}

function ConvertTo-ReleaseTag {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RequestedVersion
    )

    $candidate = $RequestedVersion.Trim()
    if ($candidate -notmatch '^[vV]?(?<number>[0-9]+\.[0-9]+\.[0-9]+)$') {
        throw "Version must use MAJOR.MINOR.PATCH with an optional leading 'v'. Omit -Version to install the current public release."
    }

    return 'v' + $Matches['number']
}

function Resolve-LatestReleaseTag {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryName
    )

    $apiUri = "https://api.github.com/repos/$RepositoryName/releases/latest"
    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'Cleo-Windows-Installer'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    Write-Host 'Resolving the latest Cleo release...'
    $release = $null
    $maximumAttempts = 3
    for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
        try {
            # This is deliberately the only latest-release lookup operation.
            # Failed requests may retry, but only one successful response is
            # accepted and every asset URL is pinned to its validated tag.
            $release = Invoke-RestMethod -Method Get -Uri $apiUri -Headers $headers -TimeoutSec 45
            break
        }
        catch {
            $resolutionError = $_
            if ($attempt -ge $maximumAttempts) {
                throw "Could not resolve the latest Cleo release from GitHub after $maximumAttempts attempts: $($resolutionError.Exception.Message)"
            }
            $delaySeconds = [Int32] (2 * [Math]::Pow(2, $attempt - 1))
            Write-Warning "Latest-release lookup attempt $attempt of $maximumAttempts failed. Retrying in $delaySeconds seconds."
            Start-Sleep -Seconds $delaySeconds
        }
    }

    if ($null -eq $release -or [string]::IsNullOrWhiteSpace([string] $release.tag_name)) {
        throw 'GitHub returned a latest-release response without a tag.'
    }

    return ConvertTo-ReleaseTag -RequestedVersion ([string] $release.tag_name)
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)]
        [uri] $Uri,

        [Parameter(Mandatory = $true)]
        [string] $Destination,

        [Parameter()]
        [ValidateRange(30, 1800)]
        [Int32] $TimeoutSeconds = 600,

        [Parameter()]
        [ValidateRange(1, 5)]
        [Int32] $MaximumAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Destination) {
                [IO.File]::Delete($Destination)
            }
            Invoke-WebRequest `
                -UseBasicParsing `
                -Uri $Uri `
                -OutFile $Destination `
                -Headers @{ 'User-Agent' = 'Cleo-Windows-Installer' } `
                -TimeoutSec $TimeoutSeconds | Out-Null

            if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or
                (Get-Item -LiteralPath $Destination).Length -eq 0) {
                throw 'the downloaded file is empty or missing'
            }
            return
        }
        catch {
            $downloadError = $_
            if (Test-Path -LiteralPath $Destination) {
                try { [IO.File]::Delete($Destination) } catch {}
            }
            if ($attempt -ge $MaximumAttempts) {
                throw "Download failed after $MaximumAttempts attempts for $Uri : $($downloadError.Exception.Message)"
            }

            $delaySeconds = [Int32] (2 * [Math]::Pow(2, $attempt - 1))
            Write-Warning "Download attempt $attempt of $MaximumAttempts failed for $Uri. Retrying in $delaySeconds seconds."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function Get-PublishedChecksum {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ManifestPath,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedFileName
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Checksum manifest was not found: $ManifestPath"
    }

    $escapedName = [Regex]::Escape($ExpectedFileName)
    $pattern = '^(?<hash>[0-9A-Fa-f]{64})[ \t]+[*]?' + $escapedName + '[ \t]*$'
    $matchingHashes = @()

    foreach ($line in @(Get-Content -LiteralPath $ManifestPath)) {
        if ($line -match $pattern) {
            $matchingHashes += $Matches['hash'].ToUpperInvariant()
        }
    }

    if ($matchingHashes.Count -ne 1) {
        throw "Checksum manifest must contain exactly one entry named $ExpectedFileName; found $($matchingHashes.Count)."
    }

    return $matchingHashes[0]
}

function Assert-ArchiveChecksum {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ArchivePath,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedHash
    )

    $actualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if (-not [string]::Equals($actualHash, $ExpectedHash, [StringComparison]::Ordinal)) {
        throw "SHA-256 verification failed for $AssetName. Expected $ExpectedHash but received $actualHash. The file was not installed."
    }
}

function Expand-VerifiedCleoArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ArchivePath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
        $entries = @($archive.Entries)
        if ($entries.Count -ne 1 -or
            -not [string]::Equals($entries[0].FullName, $ExecutableName, [StringComparison]::Ordinal) -or
            -not [string]::Equals($entries[0].Name, $ExecutableName, [StringComparison]::Ordinal) -or
            $entries[0].Length -le 0) {
            $entryNames = @($entries | ForEach-Object { $_.FullName }) -join ', '
            if ([string]::IsNullOrWhiteSpace($entryNames)) {
                $entryNames = '(none)'
            }
            throw "The Windows ZIP must contain exactly one non-empty top-level file named Cleo.exe. Found: $entryNames"
        }

        $inputStream = $null
        $outputStream = $null
        try {
            $inputStream = $entries[0].Open()
            $outputStream = [IO.File]::Open(
                $DestinationPath,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            $inputStream.CopyTo($outputStream)
        }
        finally {
            if ($null -ne $outputStream) { $outputStream.Dispose() }
            if ($null -ne $inputStream) { $inputStream.Dispose() }
        }

        if ((Get-Item -LiteralPath $DestinationPath).Length -ne $entries[0].Length) {
            throw 'Cleo.exe was not extracted completely.'
        }
    }
    catch {
        throw "ZIP verification or extraction failed: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
    }
}

function Assert-WindowsX64Executable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $stream = $null
    $reader = $null
    try {
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        $reader = New-Object IO.BinaryReader($stream)

        if ($stream.Length -lt 66 -or
            $reader.ReadByte() -ne 0x4d -or
            $reader.ReadByte() -ne 0x5a) {
            throw 'the DOS/PE signature is missing'
        }

        $stream.Position = 0x3c
        [UInt32] $peOffset = $reader.ReadUInt32()
        if ($peOffset -lt 0x40 -or [Int64] $peOffset -gt ($stream.Length - 6)) {
            throw 'the PE header offset is invalid'
        }

        $stream.Position = [Int64] $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw 'the PE signature is invalid'
        }
        [UInt16] $machine = $reader.ReadUInt16()
        if ($machine -ne 0x8664) {
            throw ('the PE machine type is 0x{0:x4}, not AMD64 (0x8664)' -f $machine)
        }
    }
    catch {
        throw "The packaged Cleo.exe is not a valid native Windows x64 executable: $($_.Exception.Message). The file was not installed."
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Assert-NoReparsePointTree {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    $rootItem = Get-Item -LiteralPath $Path -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description cannot be a symbolic link, junction, or other reparse point: $Path"
    }
    if (-not $rootItem.PSIsContainer) {
        return
    }

    $pending = New-Object 'Collections.Generic.Stack[IO.DirectoryInfo]'
    $pending.Push([IO.DirectoryInfo] $rootItem)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($child in $directory.GetFileSystemInfos()) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Description contains a symbolic link, junction, or other reparse point: $($child.FullName)"
            }
            if (($child.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                $pending.Push([IO.DirectoryInfo] $child)
            }
        }
    }
}

function Assert-SafeArchiveDestinationDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "The original working directory no longer exists or is not a directory: $fullPath"
    }

    # Check the destination and each existing ancestor without traversing any
    # unrelated children. A reparse point in this chain could redirect the
    # retained download outside the directory the caller selected.
    $currentPath = $fullPath
    while ($true) {
        $item = Get-Item -LiteralPath $currentPath -Force
        if (-not $item.PSIsContainer) {
            throw "The retained-package destination is not a directory: $currentPath"
        }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "The retained-package destination cannot use a symbolic link, junction, or other reparse point: $currentPath"
        }

        $root = [IO.Path]::GetPathRoot($currentPath)
        if ([string]::IsNullOrWhiteSpace($root) -or
            (Test-SamePath -First $currentPath -Second $root)) {
            break
        }
        $parent = [IO.Directory]::GetParent($currentPath)
        if ($null -eq $parent) {
            break
        }
        $currentPath = $parent.FullName
    }
}

function Test-ExistingVerifiedArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedHash
    )

    $existingItem = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $existingItem) {
        return $false
    }
    if (($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to replace a symbolic link, junction, or other reparse point at the retained-package path: $Path"
    }
    if ($existingItem.PSIsContainer -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Refusing to replace a non-file item at the retained-package path: $Path"
    }

    $existingHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if (-not [string]::Equals($existingHash, $ExpectedHash, [StringComparison]::Ordinal)) {
        throw "A different file already exists at $Path. Move or rename it, then rerun the installer; the existing file was not changed."
    }
    return $true
}

function Publish-VerifiedArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $VerifiedArchivePath,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedHash,

        [Parameter(Mandatory = $true)]
        [string] $DestinationDirectory
    )

    $destinationDirectoryPath = [IO.Path]::GetFullPath($DestinationDirectory)
    $destinationPath = Join-Path $destinationDirectoryPath $AssetName
    $stagingPath = $null

    Assert-SafeArchiveDestinationDirectory -Path $destinationDirectoryPath
    if (Test-ExistingVerifiedArchive -Path $destinationPath -ExpectedHash $ExpectedHash) {
        return $destinationPath
    }

    try {
        $stagingPath = Join-Path $destinationDirectoryPath ('.cleo-download-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        if (Test-Path -LiteralPath $stagingPath) {
            throw "A unique retained-package staging path unexpectedly already exists: $stagingPath"
        }

        $sourceStream = $null
        $destinationStream = $null
        try {
            $sourceStream = [IO.File]::Open(
                $VerifiedArchivePath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::Read
            )
            $destinationStream = [IO.File]::Open(
                $stagingPath,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            $sourceStream.CopyTo($destinationStream)
            $destinationStream.Flush()
        }
        finally {
            if ($null -ne $destinationStream) { $destinationStream.Dispose() }
            if ($null -ne $sourceStream) { $sourceStream.Dispose() }
        }

        Assert-ArchiveChecksum -ArchivePath $stagingPath -ExpectedHash $ExpectedHash
        Assert-SafeArchiveDestinationDirectory -Path $destinationDirectoryPath

        # A matching file created during the copy is a harmless concurrent
        # success. Any other collision is rejected without replacing it.
        if (Test-ExistingVerifiedArchive -Path $destinationPath -ExpectedHash $ExpectedHash) {
            return $destinationPath
        }

        try {
            # The staging file and destination are in the same directory, so
            # this rename publishes the fully written file atomically.
            [IO.File]::Move($stagingPath, $destinationPath)
        }
        catch {
            $moveError = $_
            if (Test-ExistingVerifiedArchive -Path $destinationPath -ExpectedHash $ExpectedHash) {
                return $destinationPath
            }
            throw "The verified release package could not be retained at $destinationPath : $($moveError.Exception.Message)"
        }

        if (-not (Test-ExistingVerifiedArchive -Path $destinationPath -ExpectedHash $ExpectedHash)) {
            throw "The verified release package was not retained at $destinationPath"
        }
        return $destinationPath
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($stagingPath) -and
            (Test-Path -LiteralPath $stagingPath)) {
            try {
                Remove-OwnedFile `
                    -Path $stagingPath `
                    -ExpectedParent $destinationDirectoryPath `
                    -ExpectedPrefix '.cleo-download-'
            }
            catch {
                Write-Warning "Could not clean up retained-package staging file $stagingPath : $($_.Exception.Message)"
            }
        }
    }
}

function Get-CleoOwnershipState {
    $baseKey = $null
    $ownershipKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::CurrentUser,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $ownershipKey = $baseKey.OpenSubKey($OwnershipRegistrySubKey, $false)
        if ($null -eq $ownershipKey) {
            return [pscustomobject] @{
                KeyExisted = $false
                BundleValueExisted = $false
                BundleId = $null
                BundleKind = $null
                PathValueExisted = $false
                InstallPath = $null
                PathKind = $null
            }
        }

        $valueNames = @($ownershipKey.GetValueNames())
        $bundleExists = $valueNames -contains $OwnershipBundleValueName
        $pathExists = $valueNames -contains $OwnershipPathValueName
        $bundleValue = $null
        $bundleKind = $null
        $pathValue = $null
        $pathKind = $null
        if ($bundleExists) {
            $bundleValue = $ownershipKey.GetValue($OwnershipBundleValueName)
            $bundleKind = $ownershipKey.GetValueKind($OwnershipBundleValueName)
        }
        if ($pathExists) {
            $pathValue = $ownershipKey.GetValue($OwnershipPathValueName)
            $pathKind = $ownershipKey.GetValueKind($OwnershipPathValueName)
        }

        return [pscustomobject] @{
            KeyExisted = $true
            BundleValueExisted = $bundleExists
            BundleId = $bundleValue
            BundleKind = $bundleKind
            PathValueExisted = $pathExists
            InstallPath = $pathValue
            PathKind = $pathKind
        }
    }
    finally {
        if ($null -ne $ownershipKey) { $ownershipKey.Dispose() }
        if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
}

function Test-CleoOwnershipState {
    param(
        [Parameter(Mandatory = $true)]
        [object] $State,

        [Parameter(Mandatory = $true)]
        [string] $InstallPath
    )

    if (-not $State.KeyExisted -or
        -not $State.BundleValueExisted -or
        -not $State.PathValueExisted -or
        $State.BundleKind -ne [Microsoft.Win32.RegistryValueKind]::String -or
        $State.PathKind -ne [Microsoft.Win32.RegistryValueKind]::String -or
        -not [string]::Equals([string] $State.BundleId, $BundleIdentifier, [StringComparison]::Ordinal)) {
        return $false
    }

    try {
        $recordedPath = [string] $State.InstallPath
        if ([string]::IsNullOrWhiteSpace($recordedPath)) {
            return $false
        }
        $normalizedRecordedPath = [IO.Path]::GetFullPath($recordedPath).TrimEnd('\', '/')
        $normalizedInstallPath = [IO.Path]::GetFullPath($InstallPath).TrimEnd('\', '/')
        if (-not [string]::Equals(
                $recordedPath,
                $normalizedRecordedPath,
                [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        return [string]::Equals(
            $normalizedRecordedPath,
            $normalizedInstallPath,
            [StringComparison]::OrdinalIgnoreCase
        )
    }
    catch {
        return $false
    }
}

function Set-CleoOwnershipState {
    param(
        [Parameter(Mandatory = $true)]
        [string] $InstallPath
    )

    $normalizedPath = [IO.Path]::GetFullPath($InstallPath).TrimEnd('\', '/')
    $baseKey = $null
    $ownershipKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::CurrentUser,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $ownershipKey = $baseKey.CreateSubKey($OwnershipRegistrySubKey)
        if ($null -eq $ownershipKey) {
            throw "Could not create $OwnershipRegistryDisplayPath."
        }
        # InstallPath is written last. Since both values are required, it acts
        # as the commit point for a new ownership record.
        $ownershipKey.SetValue(
            $OwnershipBundleValueName,
            $BundleIdentifier,
            [Microsoft.Win32.RegistryValueKind]::String
        )
        $ownershipKey.SetValue(
            $OwnershipPathValueName,
            $normalizedPath,
            [Microsoft.Win32.RegistryValueKind]::String
        )
        $ownershipKey.Flush()
    }
    finally {
        if ($null -ne $ownershipKey) { $ownershipKey.Dispose() }
        if ($null -ne $baseKey) { $baseKey.Dispose() }
    }

    $writtenState = Get-CleoOwnershipState
    if (-not (Test-CleoOwnershipState -State $writtenState -InstallPath $normalizedPath)) {
        throw "The Cleo ownership record could not be verified at $OwnershipRegistryDisplayPath."
    }
}

function Restore-CleoOwnershipState {
    param(
        [Parameter(Mandatory = $true)]
        [object] $State
    )

    $baseKey = $null
    $ownershipKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::CurrentUser,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $ownershipKey = $baseKey.CreateSubKey($OwnershipRegistrySubKey)
        if ($null -eq $ownershipKey) {
            throw "Could not restore $OwnershipRegistryDisplayPath."
        }

        if ($State.BundleValueExisted) {
            $ownershipKey.SetValue(
                $OwnershipBundleValueName,
                $State.BundleId,
                $State.BundleKind
            )
        }
        else {
            $ownershipKey.DeleteValue($OwnershipBundleValueName, $false)
        }
        if ($State.PathValueExisted) {
            $ownershipKey.SetValue(
                $OwnershipPathValueName,
                $State.InstallPath,
                $State.PathKind
            )
        }
        else {
            $ownershipKey.DeleteValue($OwnershipPathValueName, $false)
        }
        $ownershipKey.Flush()

        if (-not $State.KeyExisted -and
            $ownershipKey.GetValueNames().Count -eq 0 -and
            $ownershipKey.GetSubKeyNames().Count -eq 0) {
            $ownershipKey.Dispose()
            $ownershipKey = $null
            $baseKey.DeleteSubKey($OwnershipRegistrySubKey, $false)
        }
    }
    finally {
        if ($null -ne $ownershipKey) { $ownershipKey.Dispose() }
        if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
}

function Test-ExactInstallFiles {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Items,

        [Parameter(Mandatory = $true)]
        [string[]] $ExpectedNames
    )

    if ($Items.Count -ne $ExpectedNames.Count) {
        return $false
    }
    $remainingNames = New-Object 'Collections.Generic.List[string]'
    foreach ($expectedName in $ExpectedNames) {
        $remainingNames.Add($expectedName)
    }
    foreach ($item in $Items) {
        if ($item.PSIsContainer) {
            return $false
        }
        $matchedIndex = -1
        for ($index = 0; $index -lt $remainingNames.Count; $index++) {
            if ([string]::Equals(
                    $item.Name,
                    $remainingNames[$index],
                    [StringComparison]::OrdinalIgnoreCase)) {
                $matchedIndex = $index
                break
            }
        }
        if ($matchedIndex -lt 0) {
            return $false
        }
        $remainingNames.RemoveAt($matchedIndex)
    }
    return $remainingNames.Count -eq 0
}

function Test-ExactLegacyInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [object[]] $Items
    )

    $legacyNames = @(
        'Cleo.exe',
        'av_libglesv2.dll',
        'libHarfBuzzSharp.dll',
        'libSkiaSharp.dll'
    )
    if (-not (Test-ExactInstallFiles -Items $Items -ExpectedNames $legacyNames)) {
        return $false
    }

    try {
        Assert-WindowsX64Executable -Path (Join-Path $Path $ExecutableName)
        return $true
    }
    catch {
        return $false
    }
}

function Get-InstallDisposition {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [bool] $AllowUnmarked
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        throw "InstallDirectory points to a file, not a directory: $Path"
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return 'New'
    }

    Assert-NoReparsePointTree -Path $Path -Description 'InstallDirectory'
    $items = @(Get-ChildItem -LiteralPath $Path -Force)
    if ($items.Count -eq 0) {
        return 'Empty'
    }

    $singleFileNames = @($ExecutableName)
    if (Test-ExactInstallFiles -Items $items -ExpectedNames $singleFileNames) {
        $ownershipState = Get-CleoOwnershipState
        if (Test-CleoOwnershipState -State $ownershipState -InstallPath $Path) {
            return 'Owned'
        }
    }

    if (Test-ExactLegacyInstall -Path $Path -Items $items) {
        return 'Legacy'
    }
    if ($AllowUnmarked) {
        return 'Forced'
    }
    return 'Unmarked'
}

function Get-ShortcutTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ShortcutPath
    )

    $shell = $null
    $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        return [string] $shortcut.TargetPath
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $shortcut -and [Runtime.InteropServices.Marshal]::IsComObject($shortcut)) {
            [void] [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        }
        if ($null -ne $shell -and [Runtime.InteropServices.Marshal]::IsComObject($shell)) {
            [void] [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
}

function New-CleoShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ShortcutPath,

        [Parameter(Mandatory = $true)]
        [string] $ExecutablePath,

        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory
    )

    $shell = $null
    $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $ExecutablePath
        $shortcut.WorkingDirectory = $WorkingDirectory
        $shortcut.IconLocation = "$ExecutablePath,0"
        $shortcut.Description = 'Cleo authorized security testing tool'
        $shortcut.Save()
    }
    finally {
        if ($null -ne $shortcut -and [Runtime.InteropServices.Marshal]::IsComObject($shortcut)) {
            [void] [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        }
        if ($null -ne $shell -and [Runtime.InteropServices.Marshal]::IsComObject($shell)) {
            [void] [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }

    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
        throw 'Windows did not create the Start Menu shortcut.'
    }
}

function Remove-OwnedDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedParent,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedPrefix
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $fullPath = [IO.Path]::GetFullPath($Path)
    $actualParent = [IO.Directory]::GetParent($fullPath)
    if ($null -eq $actualParent -or
        -not (Test-SamePath -First $actualParent.FullName -Second $ExpectedParent) -or
        -not [IO.Path]::GetFileName($fullPath).StartsWith($ExpectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean up an unexpected directory: $fullPath"
    }

    Assert-NoReparsePointTree -Path $fullPath -Description 'Installer cleanup directory'
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function Remove-OwnedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedParent,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedPrefix
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $fullPath = [IO.Path]::GetFullPath($Path)
    $actualParent = [IO.Directory]::GetParent($fullPath)
    if ($null -eq $actualParent -or
        -not (Test-SamePath -First $actualParent.FullName -Second $ExpectedParent) -or
        -not [IO.Path]::GetFileName($fullPath).StartsWith($ExpectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean up an unexpected file: $fullPath"
    }

    Assert-NoReparsePointTree -Path $fullPath -Description 'Installer cleanup file'
    Remove-Item -LiteralPath $fullPath -Force
}

$previousErrorActionPreference = $ErrorActionPreference
$previousProgressPreference = $ProgressPreference
$previousSecurityProtocol = $null
$securityProtocolWasChanged = $false
$temporaryRoot = $null
$temporaryBase = $null
$installParent = $null
$stagingDirectory = $null
$backupDirectory = $null
$failedDirectory = $null
$shortcutParent = $null
$temporaryShortcut = $null
$backupShortcut = $null

try {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $nativeArchitecture = Get-NativeWindowsArchitecture
    if ($nativeArchitecture -ne 'x64') {
        if ($nativeArchitecture -eq 'arm64' -or $nativeArchitecture -eq 'arm') {
            throw "This Windows device uses $nativeArchitecture. Cleo currently provides a Windows x64 build only; do not install the Chromebook/Linux ARM package on Windows."
        }
        if ($nativeArchitecture -eq 'x86') {
            throw 'This device is running 32-bit Windows. Cleo requires 64-bit Windows (x64).'
        }
        throw "Unsupported Windows architecture '$nativeArchitecture'. Cleo currently provides a Windows x64 build only."
    }
    $windowsVersionDetails = Assert-SupportedWindowsVersion

    if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            throw 'Windows did not provide a Local AppData directory for the current user.'
        }
        $InstallDirectory = Join-Path (Join-Path $localAppData 'Programs') 'Cleo'
    }
    $installPath = Get-FileSystemPath -Path $InstallDirectory -Description 'InstallDirectory'
    $installRoot = [IO.Path]::GetPathRoot($installPath)
    if ([string]::IsNullOrWhiteSpace($installRoot) -or (Test-SamePath -First $installPath -Second $installRoot)) {
        throw 'InstallDirectory must be a dedicated application directory, not a drive or share root.'
    }
    $installParentInfo = [IO.Directory]::GetParent($installPath)
    if ($null -eq $installParentInfo) {
        throw 'InstallDirectory must have a parent directory.'
    }
    $installParent = $installParentInfo.FullName
    $installedExecutable = Join-Path $installPath $ExecutableName

    if (Test-PathAtOrBelowDirectory -Path $originalWorkingDirectory -Directory $installPath) {
        throw "The terminal's original working directory is the Cleo InstallDirectory or is inside it: $originalWorkingDirectory. Open a terminal in a directory outside $installPath, then rerun the installer so the retained ZIP remains separate from the managed installation."
    }

    $initialDisposition = Get-InstallDisposition -Path $installPath -AllowUnmarked ([bool] $Force)
    if ($initialDisposition -eq 'Unmarked') {
        throw "The destination is not recorded as a Cleo installation for this user: $installPath. Ownership is stored at $OwnershipRegistryDisplayPath. Choose another InstallDirectory or rerun with -Force only if it is safe to replace that entire directory."
    }
    if ($initialDisposition -eq 'Legacy') {
        Write-Host 'An exact legacy four-file Cleo installation was detected and will be migrated.'
    }

    $shortcutPath = $null
    if (-not $NoShortcut) {
        $shortcutParent = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
        if ([string]::IsNullOrWhiteSpace($shortcutParent)) {
            throw 'Windows did not provide a Start Menu Programs directory for the current user.'
        }
        $shortcutParent = [IO.Path]::GetFullPath($shortcutParent)
        $shortcutPath = Join-Path $shortcutParent 'Cleo.lnk'
        if (Test-Path -LiteralPath $shortcutPath) {
            Assert-NoReparsePointTree -Path $shortcutPath -Description 'Cleo Start Menu shortcut'
            if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
                throw "The Start Menu shortcut path is not a file: $shortcutPath"
            }
            $shortcutTarget = Get-ShortcutTarget -ShortcutPath $shortcutPath
            if (([string]::IsNullOrWhiteSpace($shortcutTarget) -or
                -not (Test-SamePath -First $shortcutTarget -Second $installedExecutable)) -and
                -not $Force) {
                throw "An existing Cleo Start Menu shortcut points somewhere else. Rerun with -NoShortcut, or use -Force only if that shortcut may be replaced."
            }
        }
    }

    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporaryRoot = Join-Path $temporaryBase ($InstallerPrefix + [Guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $temporaryRoot) {
        throw "Refusing to use a pre-existing temporary path: $temporaryRoot"
    }
    [void] [IO.Directory]::CreateDirectory($temporaryRoot)

    $archivePath = Join-Path $temporaryRoot $AssetName
    $manifestPath = Join-Path $temporaryRoot $ChecksumName

    if (-not [string]::IsNullOrWhiteSpace($AssetDirectory)) {
        $assetSourcePath = Get-FileSystemPath -Path $AssetDirectory -Description 'AssetDirectory'
        if (-not (Test-Path -LiteralPath $assetSourcePath -PathType Container)) {
            throw "AssetDirectory does not exist: $assetSourcePath"
        }
        $sourceArchive = Join-Path $assetSourcePath $AssetName
        $sourceManifest = Join-Path $assetSourcePath $ChecksumName
        if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
            throw "AssetDirectory is missing $AssetName."
        }
        if (-not (Test-Path -LiteralPath $sourceManifest -PathType Leaf)) {
            throw "AssetDirectory is missing $ChecksumName."
        }

        Copy-Item -LiteralPath $sourceArchive -Destination $archivePath
        Copy-Item -LiteralPath $sourceManifest -Destination $manifestPath
        if ([string]::IsNullOrWhiteSpace($Version) -or $Version.Trim() -ieq 'latest') {
            $releaseTag = 'offline assets'
        }
        else {
            $releaseTag = ConvertTo-ReleaseTag -RequestedVersion $Version
        }
        Write-Host "Using verified local release files from $assetSourcePath."
    }
    else {
        $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $securityProtocolWasChanged = $true

        if ([string]::IsNullOrWhiteSpace($Version) -or $Version.Trim() -ieq 'latest') {
            $releaseTag = Resolve-LatestReleaseTag -RepositoryName $Repository
        }
        else {
            $releaseTag = ConvertTo-ReleaseTag -RequestedVersion $Version
        }

        # Both URLs are pinned before either download begins. Never combine an
        # asset obtained through a moving /latest URL with another release's
        # checksum manifest.
        $releaseBaseUri = "https://github.com/$Repository/releases/download/$releaseTag"
        $archiveUri = [uri] "$releaseBaseUri/$AssetName"
        $manifestUri = [uri] "$releaseBaseUri/$ChecksumName"

        Write-Host "Downloading Cleo $releaseTag..."
        Invoke-Download -Uri $archiveUri -Destination $archivePath -TimeoutSeconds 600 -MaximumAttempts 3
        Invoke-Download -Uri $manifestUri -Destination $manifestPath -TimeoutSeconds 120 -MaximumAttempts 3
    }

    $publishedHash = Get-PublishedChecksum -ManifestPath $manifestPath -ExpectedFileName $AssetName
    Assert-ArchiveChecksum -ArchivePath $archivePath -ExpectedHash $publishedHash

    $extractedExecutable = Join-Path $temporaryRoot $ExecutableName
    Expand-VerifiedCleoArchive -ArchivePath $archivePath -DestinationPath $extractedExecutable
    Assert-WindowsX64Executable -Path $extractedExecutable
    Write-Host 'Checksum and Windows package layout verified.'

    $retainedArchivePath = Publish-VerifiedArchive `
        -VerifiedArchivePath $archivePath `
        -ExpectedHash $publishedHash `
        -DestinationDirectory $originalWorkingDirectory
    Write-Host "[OK] Verified package saved: $retainedArchivePath"

    [void] [IO.Directory]::CreateDirectory($installParent)
    $transactionId = [Guid]::NewGuid().ToString('N')
    $stagingDirectory = Join-Path $installParent ('.cleo-install-' + $transactionId)
    $backupDirectory = Join-Path $installParent ('.cleo-backup-' + $transactionId)
    $failedDirectory = Join-Path $installParent ('.cleo-failed-' + $transactionId)
    if ((Test-Path -LiteralPath $stagingDirectory) -or
        (Test-Path -LiteralPath $backupDirectory) -or
        (Test-Path -LiteralPath $failedDirectory)) {
        throw 'A unique installation transaction path unexpectedly already exists.'
    }
    [void] [IO.Directory]::CreateDirectory($stagingDirectory)
    Copy-Item -LiteralPath $extractedExecutable -Destination (Join-Path $stagingDirectory $ExecutableName)

    $temporaryShortcut = $null
    $backupShortcut = $null
    if (-not $NoShortcut) {
        [void] [IO.Directory]::CreateDirectory($shortcutParent)
        $temporaryShortcut = Join-Path $shortcutParent ('Cleo.install-' + $transactionId + '.lnk')
        $backupShortcut = Join-Path $shortcutParent ('Cleo.backup-' + $transactionId + '.lnk')
        if ((Test-Path -LiteralPath $temporaryShortcut) -or (Test-Path -LiteralPath $backupShortcut)) {
            throw 'A unique shortcut transaction path unexpectedly already exists.'
        }
        New-CleoShortcut `
            -ShortcutPath $temporaryShortcut `
            -ExecutablePath $installedExecutable `
            -WorkingDirectory $installPath
    }

    $originalInstallMoved = $false
    $newInstallMoved = $false
    $originalShortcutMoved = $false
    $newShortcutMoved = $false
    $ownershipWriteAttempted = $false
    $previousOwnershipState = Get-CleoOwnershipState

    # Re-read both the directory tree and the current-user ownership record at
    # the last possible point before an existing directory can be renamed.
    $finalDisposition = Get-InstallDisposition -Path $installPath -AllowUnmarked ([bool] $Force)
    if ($finalDisposition -eq 'Unmarked') {
        throw "InstallDirectory ownership changed during installation. Nothing was replaced. Use -Force only after checking the destination: $installPath"
    }

    try {
        if (Test-Path -LiteralPath $installPath -PathType Container) {
            [IO.Directory]::Move($installPath, $backupDirectory)
            $originalInstallMoved = $true
        }
        [IO.Directory]::Move($stagingDirectory, $installPath)
        $newInstallMoved = $true

        if (-not $NoShortcut) {
            if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
                [IO.File]::Move($shortcutPath, $backupShortcut)
                $originalShortcutMoved = $true
            }
            [IO.File]::Move($temporaryShortcut, $shortcutPath)
            $newShortcutMoved = $true
        }

        $ownershipWriteAttempted = $true
        Set-CleoOwnershipState -InstallPath $installPath
    }
    catch {
        $transactionError = $_
        $rollbackProblems = @()

        if ($ownershipWriteAttempted) {
            try {
                Restore-CleoOwnershipState -State $previousOwnershipState
            }
            catch {
                $rollbackProblems += "ownership rollback: $($_.Exception.Message)"
            }
        }

        try {
            if ($newShortcutMoved -and (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
                Remove-Item -LiteralPath $shortcutPath -Force
            }
            if ($originalShortcutMoved -and (Test-Path -LiteralPath $backupShortcut -PathType Leaf)) {
                [IO.File]::Move($backupShortcut, $shortcutPath)
            }
        }
        catch {
            $rollbackProblems += "shortcut rollback: $($_.Exception.Message)"
        }

        try {
            if ($newInstallMoved -and (Test-Path -LiteralPath $installPath -PathType Container)) {
                [IO.Directory]::Move($installPath, $failedDirectory)
            }
            if ($originalInstallMoved -and (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
                [IO.Directory]::Move($backupDirectory, $installPath)
            }
            if (Test-Path -LiteralPath $failedDirectory) {
                Remove-OwnedDirectory -Path $failedDirectory -ExpectedParent $installParent -ExpectedPrefix '.cleo-failed-'
            }
        }
        catch {
            $rollbackProblems += "application rollback: $($_.Exception.Message)"
        }

        $rollbackSuffix = ''
        if ($rollbackProblems.Count -gt 0) {
            $rollbackSuffix = ' Rollback also reported: ' + ($rollbackProblems -join '; ')
        }
        throw "Cleo was not installed: $($transactionError.Exception.Message).$rollbackSuffix"
    }

    if ($originalInstallMoved -and (Test-Path -LiteralPath $backupDirectory)) {
        try {
            Remove-OwnedDirectory -Path $backupDirectory -ExpectedParent $installParent -ExpectedPrefix '.cleo-backup-'
        }
        catch {
            Write-Warning "Cleo was installed, but the previous version could not be removed from $backupDirectory : $($_.Exception.Message)"
        }
    }
    if ($originalShortcutMoved -and (Test-Path -LiteralPath $backupShortcut)) {
        try {
            Remove-OwnedFile -Path $backupShortcut -ExpectedParent $shortcutParent -ExpectedPrefix 'Cleo.backup-'
        }
        catch {
            Write-Warning "Cleo was installed, but the previous shortcut backup could not be removed: $($_.Exception.Message)"
        }
    }

    Write-Host "Cleo $releaseTag was installed at $installedExecutable"
    if (-not $NoShortcut) {
        Write-Host 'A Cleo shortcut was added to your Start Menu.'
    }

    if (-not $NoLaunch) {
        try {
            Start-Process -FilePath $installedExecutable -WorkingDirectory $installPath
        }
        catch {
            Write-Warning "Cleo was installed successfully but could not be started automatically: $($_.Exception.Message)"
            Write-Host "Start it from the Start Menu or run: $installedExecutable"
        }
    }
}
finally {
    if ($securityProtocolWasChanged) {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
    }

    if (-not [string]::IsNullOrWhiteSpace($temporaryShortcut) -and
        -not [string]::IsNullOrWhiteSpace($shortcutParent)) {
        try {
            Remove-OwnedFile -Path $temporaryShortcut -ExpectedParent $shortcutParent -ExpectedPrefix 'Cleo.install-'
        }
        catch {
            Write-Warning "Could not clean up temporary shortcut $temporaryShortcut : $($_.Exception.Message)"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($stagingDirectory) -and
        -not [string]::IsNullOrWhiteSpace($installParent)) {
        try {
            Remove-OwnedDirectory -Path $stagingDirectory -ExpectedParent $installParent -ExpectedPrefix '.cleo-install-'
        }
        catch {
            Write-Warning "Could not clean up staging directory $stagingDirectory : $($_.Exception.Message)"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($temporaryRoot) -and
        -not [string]::IsNullOrWhiteSpace($temporaryBase)) {
        try {
            Remove-OwnedDirectory -Path $temporaryRoot -ExpectedParent $temporaryBase -ExpectedPrefix $InstallerPrefix
        }
        catch {
            Write-Warning "Could not clean up temporary directory $temporaryRoot : $($_.Exception.Message)"
        }
    }

    $ProgressPreference = $previousProgressPreference
    $ErrorActionPreference = $previousErrorActionPreference
}
