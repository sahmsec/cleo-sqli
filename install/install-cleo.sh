#!/usr/bin/env bash
#
# Install Cleo from its verified GitHub release assets.
#
# This script deliberately downloads data only. It must be saved and run with
# Bash; it is not designed to be piped from curl into a shell.

set -euo pipefail

readonly CLEO_REPOSITORY="sahmsec/cleo-sqli"
readonly CLEO_RELEASES_URL="https://github.com/${CLEO_REPOSITORY}/releases"
readonly CLEO_LATEST_URL="${CLEO_RELEASES_URL}/latest"
readonly CLEO_CHECKSUMS_NAME="SHA256SUMS.txt"
readonly CLEO_LINUX_ICON_NAME="in.sahmsec.cleo.png"
readonly CLEO_LINUX_ICON_SHA256="23bda574fdfd28e570a9f4ef1f825c793e96f420ce8dcf6dfcfd2e5a13b5bef8"
readonly CLEO_ROOT_STAGE_PARENT="/var/tmp"
readonly CLEO_ROOT_STAGE_PREFIX="/var/tmp/cleo-install-root."

NO_LAUNCH=0
DETECT_ONLY=0
REQUESTED_PLATFORM=""
ASSET_DIR_INPUT=""
DOWNLOAD_ONLY_INPUT=""
REQUESTED_TAG=""

PLATFORM=""
ARCHITECTURE=""
ARCHITECTURE_LABEL=""
CHROMEBOOK_DEB_ARCH=""
LINUX_LIBC_LABEL=""
ASSET_NAME=""
RELEASE_LABEL=""
EXPECTED_SHA256=""

WORK_DIR=""
WORK_PARENT=""
WORK_PREFIX=""
MOUNT_POINT=""
MOUNT_ACTIVE=0
LINUX_EXTRACTED_BINARY=""
LINUX_INSTALL_STAGE=""
LINUX_DESKTOP_STAGE=""
LINUX_ICON_STAGE=""
LINUX_BINARY_DESTINATION=""
LINUX_DESKTOP_DESTINATION=""
LINUX_ICON_DESTINATION=""
LINUX_COMMAND_PATH=""
LINUX_BINARY_BACKUP=""
LINUX_DESKTOP_BACKUP=""
LINUX_ICON_BACKUP=""
LINUX_NEW_BINARY_SHA256=""
LINUX_NEW_DESKTOP_SHA256=""
LINUX_NEW_ICON_SHA256=""
LINUX_OLD_BINARY_SHA256=""
LINUX_OLD_DESKTOP_SHA256=""
LINUX_OLD_ICON_SHA256=""
LINUX_HAD_BINARY=0
LINUX_HAD_DESKTOP=0
LINUX_HAD_ICON=0
LINUX_HAD_COMMAND=0
LINUX_BINARY_REPLACED=0
LINUX_DESKTOP_REPLACED=0
LINUX_ICON_REPLACED=0
LINUX_COMMAND_CREATED=0
LINUX_TRANSACTION_ACTIVE=0
LINUX_TRANSACTION_COMMITTED=0
LINUX_ROLLBACK_FAILED=0
LINUX_INSTALL_DIRECTORY=""
LINUX_OWNERSHIP_MARKER=""
LINUX_CREATED_INSTALL_DIRECTORY=0
DOWNLOAD_STAGE=""
ROOT_STAGE_DIR=""
ROOT_STAGE_PACKAGE=""
ROOT_STAGE_CREATED=0
ROOT_STAGE_READY=0
USE_SUDO=0
MAC_INSTALL_ROOT=""
MAC_STAGE_ROOT=""
MAC_DESTINATION=""
MAC_BACKUP=""
MAC_SWAP_COMPLETE=0

usage() {
  cat <<'USAGE'
Install Cleo for Linux, macOS, or a Chromebook Linux environment.

Usage:
  bash install-cleo.sh [options]

With no platform option, desktop Linux or macOS is detected automatically.
Chromebook installation always requires --chromebook.
Normal installations use a private temporary workspace and remove the release
package automatically after Cleo has been installed.

Options:
  --linux            Require desktop Linux and install the Linux archive.
  --macos            Require macOS and install the Apple Silicon disk image.
  --chromebook        Install the Chromebook .deb package. Use this only in
                      the Chromebook Linux Terminal.
  --asset-dir DIR     Use an already-downloaded package and SHA256SUMS.txt
                      from DIR. No network request or release lookup is made.
  --download-only DIR Verify the right package and copy it to DIR without
                      installing, launching, or using sudo.
  --no-launch         Install Cleo but do not open it afterward.
  --version VERSION   Request MAJOR.MINOR.PATCH, optionally starting with v.
                      Only the currently public release is downloadable; omit
                      this option to resolve and install the latest release.
  --detect-only       Print the detected system and selected package, then exit.
  -h, --help          Show this help.

Examples:
  bash install-cleo.sh --linux
  bash install-cleo.sh --macos
  bash install-cleo.sh --chromebook
  bash install-cleo.sh --no-launch
  bash install-cleo.sh --download-only "$HOME/Downloads"
  bash install-cleo.sh --asset-dir "$HOME/Downloads" --no-launch

Chromebook note:
  First enable Settings > About ChromeOS > Developers > Linux development
  environment. Then open its Terminal and use --chromebook. The script cannot
  reliably distinguish that Linux container from another Linux computer.

Security:
  Save and inspect this script before running it. Do not use "curl | bash".
  Downloads use HTTPS and must match the release's exact SHA-256 entry before
  package contents are inspected or anything is installed.
USAGE
}

say() {
  printf '%s\n' "$*"
}

step() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf '\nError: %s\n' "$*" >&2
  exit 1
}

usage_error() {
  printf '\nError: %s\n\n' "$*" >&2
  usage >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    die "Required command '$1' was not found. $2"
}

run_privileged() {
  if [ "$USE_SUDO" -eq 1 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

run_privileged_cleanup() {
  if [ "$USE_SUDO" -eq 1 ]; then
    sudo -n "$@"
  else
    "$@"
  fi
}

root_stage_has_safe_identity() {
  local owner_mode
  local sentinel_owner_mode

  [ "$ROOT_STAGE_READY" -eq 1 ] || return 1
  [ -n "$ROOT_STAGE_DIR" ] || return 1
  [ "${ROOT_STAGE_DIR%/*}" = "$CLEO_ROOT_STAGE_PARENT" ] || return 1
  case "$ROOT_STAGE_DIR" in
    "$CLEO_ROOT_STAGE_PREFIX"*) ;;
    *) return 1 ;;
  esac
  run_privileged_cleanup test -d "$ROOT_STAGE_DIR" || return 1
  run_privileged_cleanup test ! -L "$ROOT_STAGE_DIR" || return 1
  run_privileged_cleanup test -f "$ROOT_STAGE_DIR/.cleo-installer-owned" || return 1
  run_privileged_cleanup test ! -L "$ROOT_STAGE_DIR/.cleo-installer-owned" || return 1
  owner_mode=$(run_privileged_cleanup stat -c '%u:%a' "$ROOT_STAGE_DIR" 2>/dev/null) ||
    return 1
  [ "$owner_mode" = "0:700" ] || return 1
  sentinel_owner_mode=$(run_privileged_cleanup stat -c '%u:%a' \
    "$ROOT_STAGE_DIR/.cleo-installer-owned" 2>/dev/null) || return 1
  [ "$sentinel_owner_mode" = "0:600" ]
}

root_stage_directory_has_safe_identity() {
  local owner_mode

  [ "$ROOT_STAGE_CREATED" -eq 1 ] || return 1
  [ -n "$ROOT_STAGE_DIR" ] || return 1
  [ "${ROOT_STAGE_DIR%/*}" = "$CLEO_ROOT_STAGE_PARENT" ] || return 1
  case "$ROOT_STAGE_DIR" in
    "$CLEO_ROOT_STAGE_PREFIX"*) ;;
    *) return 1 ;;
  esac
  run_privileged_cleanup test -d "$ROOT_STAGE_DIR" || return 1
  run_privileged_cleanup test ! -L "$ROOT_STAGE_DIR" || return 1
  owner_mode=$(run_privileged_cleanup stat -c '%u:%a' "$ROOT_STAGE_DIR" 2>/dev/null) ||
    return 1
  [ "$owner_mode" = "0:700" ]
}

regular_file_has_sha256() {
  local path="$1"
  local expected="$2"
  local actual

  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  actual=$(file_sha256 "$path" 2>/dev/null) || return 1
  [ "$actual" = "$expected" ]
}

rollback_linux_transaction() {
  local link_target

  [ "$LINUX_TRANSACTION_ACTIVE" -eq 1 ] || return 0
  [ "$LINUX_TRANSACTION_COMMITTED" -eq 0 ] || return 0

  if [ "$LINUX_COMMAND_CREATED" -eq 1 ]; then
    if [ -L "$LINUX_COMMAND_PATH" ]; then
      link_target=$(readlink "$LINUX_COMMAND_PATH" 2>/dev/null || true)
      if [ "$link_target" = "$LINUX_BINARY_DESTINATION" ]; then
        rm -f "$LINUX_COMMAND_PATH" >/dev/null 2>&1 || LINUX_ROLLBACK_FAILED=1
      else
        LINUX_ROLLBACK_FAILED=1
        printf 'Warning: preserving changed command link during rollback: %s\n' \
          "$LINUX_COMMAND_PATH" >&2
      fi
    elif [ -e "$LINUX_COMMAND_PATH" ]; then
      LINUX_ROLLBACK_FAILED=1
      printf 'Warning: preserving changed command path during rollback: %s\n' \
        "$LINUX_COMMAND_PATH" >&2
    fi
  fi

  if [ "$LINUX_DESKTOP_REPLACED" -eq 1 ]; then
    if regular_file_has_sha256 "$LINUX_DESKTOP_DESTINATION" \
        "$LINUX_NEW_DESKTOP_SHA256"; then
      if [ "$LINUX_HAD_DESKTOP" -eq 1 ]; then
        if regular_file_has_sha256 "$LINUX_DESKTOP_BACKUP" \
             "$LINUX_OLD_DESKTOP_SHA256" && \
           mv -f "$LINUX_DESKTOP_BACKUP" "$LINUX_DESKTOP_DESTINATION"; then
          LINUX_DESKTOP_BACKUP=""
        else
          LINUX_ROLLBACK_FAILED=1
        fi
      elif ! rm -f "$LINUX_DESKTOP_DESTINATION"; then
        LINUX_ROLLBACK_FAILED=1
      fi
    elif [ "$LINUX_HAD_DESKTOP" -eq 1 ] && \
         regular_file_has_sha256 "$LINUX_DESKTOP_DESTINATION" \
           "$LINUX_OLD_DESKTOP_SHA256"; then
      rm -f "$LINUX_DESKTOP_BACKUP" >/dev/null 2>&1
      LINUX_DESKTOP_BACKUP=""
    elif [ "$LINUX_HAD_DESKTOP" -eq 0 ] && \
         ! { [ -e "$LINUX_DESKTOP_DESTINATION" ] || \
             [ -L "$LINUX_DESKTOP_DESTINATION" ]; }; then
      :
    else
      LINUX_ROLLBACK_FAILED=1
      printf 'Warning: preserving changed desktop entry during rollback: %s\n' \
        "$LINUX_DESKTOP_DESTINATION" >&2
    fi
  elif [ -n "$LINUX_DESKTOP_BACKUP" ]; then
    rm -f "$LINUX_DESKTOP_BACKUP" >/dev/null 2>&1
    LINUX_DESKTOP_BACKUP=""
  fi

  if [ "$LINUX_ICON_REPLACED" -eq 1 ]; then
    if regular_file_has_sha256 "$LINUX_ICON_DESTINATION" \
        "$LINUX_NEW_ICON_SHA256"; then
      if [ "$LINUX_HAD_ICON" -eq 1 ]; then
        if regular_file_has_sha256 "$LINUX_ICON_BACKUP" \
             "$LINUX_OLD_ICON_SHA256" && \
           mv -f "$LINUX_ICON_BACKUP" "$LINUX_ICON_DESTINATION"; then
          LINUX_ICON_BACKUP=""
        else
          LINUX_ROLLBACK_FAILED=1
        fi
      elif ! rm -f "$LINUX_ICON_DESTINATION"; then
        LINUX_ROLLBACK_FAILED=1
      fi
    elif [ "$LINUX_HAD_ICON" -eq 1 ] && \
         regular_file_has_sha256 "$LINUX_ICON_DESTINATION" \
           "$LINUX_OLD_ICON_SHA256"; then
      rm -f "$LINUX_ICON_BACKUP" >/dev/null 2>&1
      LINUX_ICON_BACKUP=""
    elif [ "$LINUX_HAD_ICON" -eq 0 ] && \
         ! { [ -e "$LINUX_ICON_DESTINATION" ] || \
             [ -L "$LINUX_ICON_DESTINATION" ]; }; then
      :
    else
      LINUX_ROLLBACK_FAILED=1
      printf 'Warning: preserving changed application icon during rollback: %s\n' \
        "$LINUX_ICON_DESTINATION" >&2
    fi
  elif [ -n "$LINUX_ICON_BACKUP" ]; then
    rm -f "$LINUX_ICON_BACKUP" >/dev/null 2>&1
    LINUX_ICON_BACKUP=""
  fi

  if [ "$LINUX_BINARY_REPLACED" -eq 1 ]; then
    if regular_file_has_sha256 "$LINUX_BINARY_DESTINATION" \
        "$LINUX_NEW_BINARY_SHA256"; then
      if [ "$LINUX_HAD_BINARY" -eq 1 ]; then
        if regular_file_has_sha256 "$LINUX_BINARY_BACKUP" \
             "$LINUX_OLD_BINARY_SHA256" && \
           mv -f "$LINUX_BINARY_BACKUP" "$LINUX_BINARY_DESTINATION"; then
          LINUX_BINARY_BACKUP=""
        else
          LINUX_ROLLBACK_FAILED=1
        fi
      elif ! rm -f "$LINUX_BINARY_DESTINATION"; then
        LINUX_ROLLBACK_FAILED=1
      fi
    elif [ "$LINUX_HAD_BINARY" -eq 1 ] && \
         regular_file_has_sha256 "$LINUX_BINARY_DESTINATION" \
           "$LINUX_OLD_BINARY_SHA256"; then
      rm -f "$LINUX_BINARY_BACKUP" >/dev/null 2>&1
      LINUX_BINARY_BACKUP=""
    elif [ "$LINUX_HAD_BINARY" -eq 0 ] && \
         ! { [ -e "$LINUX_BINARY_DESTINATION" ] || \
             [ -L "$LINUX_BINARY_DESTINATION" ]; }; then
      :
    else
      LINUX_ROLLBACK_FAILED=1
      printf 'Warning: preserving changed executable during rollback: %s\n' \
        "$LINUX_BINARY_DESTINATION" >&2
    fi
  elif [ -n "$LINUX_BINARY_BACKUP" ]; then
    rm -f "$LINUX_BINARY_BACKUP" >/dev/null 2>&1
    LINUX_BINARY_BACKUP=""
  fi

  if [ "$LINUX_ROLLBACK_FAILED" -eq 0 ]; then
    LINUX_TRANSACTION_ACTIVE=0
  else
    printf 'Warning: a Linux update could not be fully rolled back; preserved rollback files remain beside the install.\n' >&2
  fi
}

cleanup() {
  local exit_code="$1"

  trap - EXIT HUP INT TERM
  set +e

  if [ "$MOUNT_ACTIVE" -eq 1 ] && [ -n "$MOUNT_POINT" ]; then
    if hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1; then
      MOUNT_ACTIVE=0
    else
      printf 'Warning: could not eject the temporary Cleo disk image at %s.\n' \
        "$MOUNT_POINT" >&2
    fi
  fi

  rollback_linux_transaction

  # If a signal or error occurs during the two atomic rename operations used
  # for a macOS upgrade, put the user's prior application back.
  if [ "$MAC_SWAP_COMPLETE" -eq 0 ] && [ -n "$MAC_BACKUP" ] && \
     { [ -e "$MAC_BACKUP" ] || [ -L "$MAC_BACKUP" ]; }; then
    if [ -n "$MAC_DESTINATION" ] && \
       ! { [ -e "$MAC_DESTINATION" ] || [ -L "$MAC_DESTINATION" ]; }; then
      /bin/mv -h "$MAC_BACKUP" "$MAC_DESTINATION" >/dev/null 2>&1 ||
        printf 'Warning: the previous Cleo.app remains at %s.\n' "$MAC_BACKUP" >&2
    fi
  fi

  if [ -n "$LINUX_INSTALL_STAGE" ]; then
    rm -f "$LINUX_INSTALL_STAGE" >/dev/null 2>&1
  fi
  if [ -n "$LINUX_DESKTOP_STAGE" ]; then
    rm -f "$LINUX_DESKTOP_STAGE" >/dev/null 2>&1
  fi
  if [ -n "$LINUX_ICON_STAGE" ]; then
    rm -f "$LINUX_ICON_STAGE" >/dev/null 2>&1
  fi
  if [ -n "$LINUX_BINARY_BACKUP" ]; then
    if [ "$LINUX_TRANSACTION_COMMITTED" -eq 1 ] || \
       [ "$LINUX_ROLLBACK_FAILED" -eq 0 ]; then
      rm -f "$LINUX_BINARY_BACKUP" >/dev/null 2>&1
    else
      printf 'Warning: preserving executable rollback copy at %s.\n' \
        "$LINUX_BINARY_BACKUP" >&2
    fi
  fi
  if [ -n "$LINUX_DESKTOP_BACKUP" ]; then
    if [ "$LINUX_TRANSACTION_COMMITTED" -eq 1 ] || \
       [ "$LINUX_ROLLBACK_FAILED" -eq 0 ]; then
      rm -f "$LINUX_DESKTOP_BACKUP" >/dev/null 2>&1
    else
      printf 'Warning: preserving desktop-entry rollback copy at %s.\n' \
        "$LINUX_DESKTOP_BACKUP" >&2
    fi
  fi
  if [ -n "$LINUX_ICON_BACKUP" ]; then
    if [ "$LINUX_TRANSACTION_COMMITTED" -eq 1 ] || \
       [ "$LINUX_ROLLBACK_FAILED" -eq 0 ]; then
      rm -f "$LINUX_ICON_BACKUP" >/dev/null 2>&1
    else
      printf 'Warning: preserving application-icon rollback copy at %s.\n' \
        "$LINUX_ICON_BACKUP" >&2
    fi
  fi

  # A failed first installation must not leave an ownership marker that makes
  # a partial directory look like a valid Cleo installation. Remove only the
  # exact marker and exact empty directory created by this run; rmdir never
  # removes adjacent or newly introduced user files.
  if [ "$LINUX_CREATED_INSTALL_DIRECTORY" -eq 1 ] && \
     [ "$LINUX_TRANSACTION_COMMITTED" -eq 0 ] && \
     [ "$LINUX_ROLLBACK_FAILED" -eq 0 ] && \
     [ -n "$LINUX_INSTALL_DIRECTORY" ] && \
     [ -n "$LINUX_OWNERSHIP_MARKER" ]; then
    if [ -d "$LINUX_INSTALL_DIRECTORY" ] && \
       [ ! -L "$LINUX_INSTALL_DIRECTORY" ]; then
      if [ -e "$LINUX_OWNERSHIP_MARKER" ] || \
         [ -L "$LINUX_OWNERSHIP_MARKER" ]; then
        if [ -f "$LINUX_OWNERSHIP_MARKER" ] && \
           [ ! -L "$LINUX_OWNERSHIP_MARKER" ] && \
           grep -Fqx 'bundle-id=in.sahmsec.cleo' "$LINUX_OWNERSHIP_MARKER"; then
          rm -f "$LINUX_OWNERSHIP_MARKER" >/dev/null 2>&1 || true
        else
          printf 'Warning: preserving changed Cleo ownership marker %s.\n' \
            "$LINUX_OWNERSHIP_MARKER" >&2
        fi
      fi
      if [ ! -e "$LINUX_OWNERSHIP_MARKER" ] && \
         [ ! -L "$LINUX_OWNERSHIP_MARKER" ]; then
        rmdir "$LINUX_INSTALL_DIRECTORY" >/dev/null 2>&1 ||
          printf 'Warning: preserving non-empty Cleo installation directory %s.\n' \
            "$LINUX_INSTALL_DIRECTORY" >&2
      fi
    elif [ -e "$LINUX_INSTALL_DIRECTORY" ] || \
         [ -L "$LINUX_INSTALL_DIRECTORY" ]; then
      printf 'Warning: preserving changed Cleo installation directory %s.\n' \
        "$LINUX_INSTALL_DIRECTORY" >&2
    fi
  fi
  if [ -n "$DOWNLOAD_STAGE" ]; then
    rm -f "$DOWNLOAD_STAGE" >/dev/null 2>&1
  fi

  if [ "$ROOT_STAGE_READY" -eq 1 ]; then
    if root_stage_has_safe_identity; then
      if ! run_privileged_cleanup rm -rf -- "$ROOT_STAGE_DIR" >/dev/null 2>&1; then
        printf 'Warning: could not remove verified-package staging directory %s.\n' \
          "$ROOT_STAGE_DIR" >&2
      fi
    else
      printf 'Warning: preserving root staging path because its ownership marker or path changed: %s.\n' \
        "$ROOT_STAGE_DIR" >&2
    fi
  elif [ "$ROOT_STAGE_CREATED" -eq 1 ]; then
    # A signal can arrive between privileged mktemp and sentinel creation.
    # In that narrow window, remove only an exact safe sentinel (if install
    # partially created it) and then use non-recursive rmdir.
    if root_stage_directory_has_safe_identity; then
      if run_privileged_cleanup test -e \
          "$ROOT_STAGE_DIR/.cleo-installer-owned" 2>/dev/null ||
         run_privileged_cleanup test -L \
          "$ROOT_STAGE_DIR/.cleo-installer-owned" 2>/dev/null; then
        if run_privileged_cleanup test -f \
             "$ROOT_STAGE_DIR/.cleo-installer-owned" &&
           run_privileged_cleanup test ! -L \
             "$ROOT_STAGE_DIR/.cleo-installer-owned" &&
           [ "$(run_privileged_cleanup stat -c '%u:%a' \
               "$ROOT_STAGE_DIR/.cleo-installer-owned" 2>/dev/null)" = "0:600" ]; then
          run_privileged_cleanup rm -f -- \
            "$ROOT_STAGE_DIR/.cleo-installer-owned" >/dev/null 2>&1 || true
        fi
      fi
      if ! run_privileged_cleanup rmdir -- "$ROOT_STAGE_DIR" >/dev/null 2>&1; then
        printf 'Warning: preserving incomplete root staging directory %s.\n' \
          "$ROOT_STAGE_DIR" >&2
      fi
    else
      printf 'Warning: preserving incomplete root staging path because its identity changed: %s.\n' \
        "$ROOT_STAGE_DIR" >&2
    fi
  fi

  # Recursive cleanup is limited to directories created by this process with
  # mktemp, under their exact expected parents, and carrying our sentinel.
  if [ -n "$MAC_STAGE_ROOT" ] && [ -n "$MAC_INSTALL_ROOT" ]; then
    case "$MAC_STAGE_ROOT" in
      "$MAC_INSTALL_ROOT"/.cleo-install.*)
        if [ ! -L "$MAC_STAGE_ROOT" ] && \
           [ -f "$MAC_STAGE_ROOT/.cleo-installer-owned" ]; then
          # Never erase a previous app that could not be restored after an
          # interrupted upgrade. Leave the exact recovery path for the user.
          if [ "$MAC_SWAP_COMPLETE" -eq 1 ] || [ -z "$MAC_BACKUP" ] || \
             ! { [ -e "$MAC_BACKUP" ] || [ -L "$MAC_BACKUP" ]; }; then
            rm -rf "$MAC_STAGE_ROOT" >/dev/null 2>&1
          else
            printf 'Warning: preserving the previous Cleo.app at %s.\n' \
              "$MAC_BACKUP" >&2
          fi
        fi
        ;;
    esac
  fi

  if [ "$MOUNT_ACTIVE" -eq 0 ] && [ -n "$WORK_DIR" ] && [ -n "$WORK_PARENT" ]; then
    case "$WORK_DIR" in
      "$WORK_PREFIX"*)
        if [ ! -L "$WORK_DIR" ] && \
           [ -f "$WORK_DIR/.cleo-installer-owned" ]; then
          rm -rf "$WORK_DIR" >/dev/null 2>&1
        fi
        ;;
    esac
  fi

  exit "$exit_code"
}

on_signal() {
  exit "$1"
}

select_requested_platform() {
  local requested="$1"

  if [ -n "$REQUESTED_PLATFORM" ] && [ "$REQUESTED_PLATFORM" != "$requested" ]; then
    usage_error "Choose only one of --linux, --macos, or --chromebook."
  fi
  REQUESTED_PLATFORM="$requested"
}

parse_options() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --linux)
        select_requested_platform linux
        ;;
      --macos)
        select_requested_platform macos
        ;;
      --chromebook)
        select_requested_platform chromebook
        ;;
      --asset-dir)
        [ "$#" -ge 2 ] || usage_error "--asset-dir needs a directory."
        ASSET_DIR_INPUT="$2"
        shift
        ;;
      --asset-dir=*)
        ASSET_DIR_INPUT=${1#*=}
        [ -n "$ASSET_DIR_INPUT" ] || usage_error "--asset-dir needs a directory."
        ;;
      --download-only)
        [ "$#" -ge 2 ] || usage_error "--download-only needs a directory."
        DOWNLOAD_ONLY_INPUT="$2"
        shift
        ;;
      --download-only=*)
        DOWNLOAD_ONLY_INPUT=${1#*=}
        [ -n "$DOWNLOAD_ONLY_INPUT" ] ||
          usage_error "--download-only needs a directory."
        ;;
      --no-launch)
        NO_LAUNCH=1
        ;;
      --version)
        [ "$#" -ge 2 ] || usage_error "--version needs MAJOR.MINOR.PATCH."
        REQUESTED_TAG="$2"
        shift
        ;;
      --version=*)
        REQUESTED_TAG=${1#*=}
        [ -n "$REQUESTED_TAG" ] ||
          usage_error "--version needs MAJOR.MINOR.PATCH."
        ;;
      --detect-only)
        DETECT_ONLY=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        [ "$#" -eq 0 ] || usage_error "This installer does not accept positional arguments."
        break
        ;;
      -*)
        usage_error "Unknown option: $1"
        ;;
      *)
        usage_error "Unexpected argument: $1"
        ;;
    esac
    shift
  done

  if [ -n "$ASSET_DIR_INPUT" ] && [ -n "$REQUESTED_TAG" ]; then
    usage_error "--asset-dir and --version cannot be used together. Local assets skip release lookup."
  fi
}

detect_system() {
  local kernel
  local machine
  local native_arm64
  local debian_arch

  require_command uname "Install the standard system utilities and try again."
  kernel=$(uname -s 2>/dev/null) || die "Could not identify this operating system."
  machine=$(uname -m 2>/dev/null) || die "Could not identify this computer's CPU."

  case "$kernel" in
    Linux)
      [ "$REQUESTED_PLATFORM" != "macos" ] ||
        die "--macos was requested, but this computer is running Linux."

      if [ "$REQUESTED_PLATFORM" = "chromebook" ]; then
        require_command dpkg \
          "Run --chromebook inside the Chromebook Linux Terminal, where dpkg is available."
        debian_arch=$(dpkg --print-architecture 2>/dev/null) ||
          die "Debian could not report this Chromebook Linux environment's architecture."
        CHROMEBOOK_DEB_ARCH="$debian_arch"
        case "$debian_arch" in
          amd64)
            ARCHITECTURE="x64"
            ARCHITECTURE_LABEL="Intel/AMD 64-bit (Debian amd64)"
            ;;
          arm64)
            ARCHITECTURE="arm64"
            ARCHITECTURE_LABEL="ARM 64-bit (Debian arm64)"
            ;;
          *)
            die "Cleo has no Chromebook package for Debian architecture '$debian_arch'. Supported results are amd64 and arm64."
            ;;
        esac
        PLATFORM="chromebook"
      else
        case "$machine" in
          x86_64|amd64)
            ARCHITECTURE="x64"
            ARCHITECTURE_LABEL="Intel/AMD 64-bit (x64)"
            ;;
          aarch64|arm64)
            ARCHITECTURE="arm64"
            ARCHITECTURE_LABEL="ARM 64-bit (arm64)"
            ;;
          *)
            die "Cleo does not currently provide a Linux package for CPU '$machine'. Supported CPUs are x86_64 and arm64."
            ;;
        esac
        PLATFORM="linux"
      fi
      ;;
    Darwin)
      case "$REQUESTED_PLATFORM" in
        linux)
          die "--linux was requested, but this computer is running macOS."
          ;;
        chromebook)
          die "--chromebook must be run inside a Chromebook's Linux Terminal, not on macOS."
          ;;
      esac

      # A Bash process running through Rosetta reports x86_64 even on an Apple
      # Silicon Mac. hw.optional.arm64 identifies the actual hardware.
      native_arm64=""
      if command -v sysctl >/dev/null 2>&1; then
        native_arm64=$(sysctl -n hw.optional.arm64 2>/dev/null || true)
      fi
      case "$machine" in
        arm64|aarch64)
          ARCHITECTURE="arm64"
          ;;
        x86_64)
          if [ "$native_arm64" = "1" ]; then
            ARCHITECTURE="arm64"
          else
            die "This is an Intel Mac. The current Cleo macOS release supports Apple Silicon (M1 or newer) only."
          fi
          ;;
        *)
          die "Cleo does not currently provide a macOS package for CPU '$machine'."
          ;;
      esac
      PLATFORM="macos"
      ARCHITECTURE_LABEL="Apple Silicon (arm64)"
      ;;
    *)
      die "This installer supports Linux, Chromebook Linux, and macOS. Detected system: $kernel."
      ;;
  esac

  case "$PLATFORM:$ARCHITECTURE" in
    linux:x64)          ASSET_NAME="Cleo-Linux-x64.tar.gz" ;;
    linux:arm64)        ASSET_NAME="Cleo-Linux-arm64.tar.gz" ;;
    chromebook:x64)     ASSET_NAME="Cleo-Chromebook-x64.deb" ;;
    chromebook:arm64)   ASSET_NAME="Cleo-Chromebook-arm64.deb" ;;
    macos:arm64)        ASSET_NAME="Cleo-macOS-Apple-Silicon.dmg" ;;
    *)                  die "No Cleo package matches $PLATFORM on $ARCHITECTURE." ;;
  esac
}

validate_linux_userspace() {
  local long_bit
  local libc_version

  case "$PLATFORM" in
    linux|chromebook) ;;
    *) return ;;
  esac

  require_command getconf \
    "Cleo's Linux packages require a standard 64-bit glibc userspace."
  long_bit=$(getconf LONG_BIT 2>/dev/null) ||
    die "Could not determine the Linux userspace bit width. Cleo requires 64-bit glibc Linux."
  [ "$long_bit" = "64" ] ||
    die "This is a ${long_bit}-bit Linux userspace. Cleo requires a 64-bit userspace."

  if ! libc_version=$(LC_ALL=C getconf GNU_LIBC_VERSION 2>/dev/null); then
    die "This Linux system does not report GNU glibc. Alpine/musl and other non-glibc systems are not supported."
  fi
  if [[ ! "$libc_version" =~ ^glibc[[:space:]][0-9]+\.[0-9]+$ ]]; then
    die "Unsupported Linux C library '$libc_version'. Cleo requires 64-bit GNU glibc."
  fi
  LINUX_LIBC_LABEL="$libc_version, 64-bit"
}

print_detection() {
  case "$PLATFORM" in
    linux)
      say "Detected system: Linux"
      say "Detected CPU:    $ARCHITECTURE_LABEL"
      say "Userspace:       $LINUX_LIBC_LABEL"
      say "Selected file:   $ASSET_NAME"
      say "Chromebook? Run this command again with --chromebook from its Linux Terminal."
      ;;
    chromebook)
      say "Detected system: Chromebook Linux environment (selected explicitly)"
      say "Detected CPU:    $ARCHITECTURE_LABEL"
      say "Userspace:       $LINUX_LIBC_LABEL"
      say "Selected file:   $ASSET_NAME"
      ;;
    macos)
      say "Detected system: macOS"
      say "Detected CPU:    $ARCHITECTURE_LABEL"
      say "Selected file:   $ASSET_NAME"
      ;;
  esac
}

create_work_directory() {
  local temporary_base
  local template

  require_command mktemp "Install the standard system utilities and try again."
  temporary_base=${TMPDIR:-/tmp}
  [ -d "$temporary_base" ] || die "Temporary directory does not exist: $temporary_base"
  WORK_PARENT=$(cd "$temporary_base" 2>/dev/null && pwd -P) ||
    die "Cannot access temporary directory: $temporary_base"

  if [ "$WORK_PARENT" = "/" ]; then
    WORK_PREFIX="/cleo-install."
  else
    WORK_PREFIX="$WORK_PARENT/cleo-install."
  fi
  template="${WORK_PREFIX}XXXXXXXX"
  WORK_DIR=$(mktemp -d "$template") || die "Could not create a private temporary directory."
  if ! { [ -d "$WORK_DIR" ] && [ ! -L "$WORK_DIR" ]; }; then
    die "Temporary workspace was not created safely."
  fi
  case "$WORK_DIR" in
    "$WORK_PREFIX"*) ;;
    *) die "Temporary workspace was created outside the expected directory." ;;
  esac
  : > "$WORK_DIR/.cleo-installer-owned"

  trap 'cleanup "$?"' EXIT
  trap 'on_signal 129' HUP
  trap 'on_signal 130' INT
  trap 'on_signal 143' TERM
}

validate_release_tag() {
  local candidate="$1"
  candidate=${candidate#v}
  if [[ ! "$candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 1
  fi
  printf 'v%s\n' "$candidate"
}

curl_download() {
  local url="$1"
  local destination="$2"
  local partial="${destination}.partial"

  case "$url" in
    https://*) ;;
    *) die "Refusing a non-HTTPS download URL: $url" ;;
  esac

  rm -f "$partial"
  if ! curl --fail --location --silent --show-error \
      --proto '=https' --proto-redir '=https' --tlsv1.2 \
      --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 900 \
      --output "$partial" "$url"; then
    rm -f "$partial"
    die "Download failed: $url"
  fi
  [ -s "$partial" ] || {
    rm -f "$partial"
    die "The downloaded file was empty: $url"
  }
  mv "$partial" "$destination"
}

resolve_latest_tag() {
  local effective_url
  local prefix="${CLEO_RELEASES_URL}/tag/"
  local candidate
  local normalized

  require_command curl "Install curl, or use --asset-dir with trusted files downloaded elsewhere."
  step "Finding the latest Cleo release" >&2

  # This is the only request to /releases/latest. The redirect result is then
  # validated and used as a fixed tag for both subsequent asset URLs.
  if ! effective_url=$(curl --fail --location --silent --show-error \
      --proto '=https' --proto-redir '=https' --tlsv1.2 \
      --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 \
      --output /dev/null --write-out '%{url_effective}' "$CLEO_LATEST_URL"); then
    die "Could not resolve the latest release. Check the internet connection and try again."
  fi

  case "$effective_url" in
    "$prefix"*) candidate=${effective_url#"$prefix"} ;;
    *) die "GitHub returned an unexpected latest-release URL: $effective_url" ;;
  esac
  if ! normalized=$(validate_release_tag "$candidate"); then
    die "GitHub returned an invalid Cleo release tag: $candidate"
  fi
  printf '%s\n' "$normalized"
}

prepare_assets() {
  local asset_source
  local checksum_source
  local normalized
  local release_base

  if [ -n "$ASSET_DIR_INPUT" ]; then
    [ -d "$ASSET_DIR_INPUT" ] || die "Asset directory does not exist: $ASSET_DIR_INPUT"
    ASSET_DIR_INPUT=$(cd "$ASSET_DIR_INPUT" 2>/dev/null && pwd -P) ||
      die "Cannot access asset directory: $ASSET_DIR_INPUT"
    asset_source="$ASSET_DIR_INPUT/$ASSET_NAME"
    checksum_source="$ASSET_DIR_INPUT/$CLEO_CHECKSUMS_NAME"
    if ! { [ -f "$asset_source" ] && [ ! -L "$asset_source" ] && \
           [ -s "$asset_source" ]; }; then
      die "The asset directory must contain a non-empty $ASSET_NAME file (not a symbolic link)."
    fi
    if ! { [ -f "$checksum_source" ] && [ ! -L "$checksum_source" ] && \
           [ -s "$checksum_source" ]; }; then
      die "The asset directory must contain a non-empty $CLEO_CHECKSUMS_NAME file (not a symbolic link)."
    fi

    step "Loading trusted local release files"
    cp "$asset_source" "$WORK_DIR/$ASSET_NAME"
    cp "$checksum_source" "$WORK_DIR/$CLEO_CHECKSUMS_NAME"
    RELEASE_LABEL="local assets"
    return
  fi

  require_command curl "Install curl, or use --asset-dir with trusted files downloaded elsewhere."
  if [ -n "$REQUESTED_TAG" ]; then
    if ! normalized=$(validate_release_tag "$REQUESTED_TAG"); then
      die "Invalid release version '$REQUESTED_TAG'. Use MAJOR.MINOR.PATCH, or omit --version to install the current public release."
    fi
    RELEASE_LABEL="$normalized"
  else
    RELEASE_LABEL=$(resolve_latest_tag)
  fi

  release_base="${CLEO_RELEASES_URL}/download/${RELEASE_LABEL}"
  step "Downloading Cleo ${RELEASE_LABEL} checksums"
  curl_download "$release_base/$CLEO_CHECKSUMS_NAME" \
    "$WORK_DIR/$CLEO_CHECKSUMS_NAME"
  step "Downloading $ASSET_NAME"
  curl_download "$release_base/$ASSET_NAME" "$WORK_DIR/$ASSET_NAME"
}

expected_checksum_for_asset() {
  local checksum_file="$1"
  local asset="$2"

  # Accept the two standard sha256sum separators (two spaces for text or a
  # space plus * for binary), but require one and only one exact filename.
  LC_ALL=C awk -v wanted="$asset" '
    {
      line = $0
      sub(/\r$/, "", line)
      hash = substr(line, 1, 64)
      separator = substr(line, 65, 2)
      filename = substr(line, 67)
      if (length(hash) == 64 && hash !~ /[^0-9A-Fa-f]/ &&
          (separator == "  " || separator == " *") && filename == wanted) {
        matches++
        selected = hash
      }
    }
    END {
      if (matches == 1) {
        print selected
        exit 0
      }
      exit 1
    }
  ' "$checksum_file"
}

file_sha256() {
  local path="$1"
  local output
  local hash

  if command -v sha256sum >/dev/null 2>&1; then
    output=$(sha256sum "$path") || return 1
  elif command -v shasum >/dev/null 2>&1; then
    output=$(shasum -a 256 "$path") || return 1
  else
    die "No SHA-256 tool was found. Install sha256sum, or use the macOS shasum command."
  fi
  hash=${output%% *}
  [ "${#hash}" -eq 64 ] || return 1
  case "$hash" in
    *[!0-9A-Fa-f]*) return 1 ;;
  esac
  printf '%s' "$hash" | tr 'A-F' 'a-f'
  printf '\n'
}

verify_checksum() {
  local actual
  local expected

  step "Verifying the SHA-256 checksum"
  if ! expected=$(expected_checksum_for_asset \
      "$WORK_DIR/$CLEO_CHECKSUMS_NAME" "$ASSET_NAME"); then
    die "$CLEO_CHECKSUMS_NAME must contain exactly one valid checksum entry for $ASSET_NAME."
  fi
  expected=$(printf '%s' "$expected" | tr 'A-F' 'a-f')
  if ! actual=$(file_sha256 "$WORK_DIR/$ASSET_NAME"); then
    die "Could not calculate the SHA-256 checksum for $ASSET_NAME."
  fi
  if [ "$actual" != "$expected" ]; then
    die "Checksum mismatch for $ASSET_NAME. The file was not installed."
  fi
  EXPECTED_SHA256="$expected"
  say "[OK] SHA-256 matches: $EXPECTED_SHA256"
}

validate_linux_binary_architecture() {
  local binary="$1"
  local header
  local machine_bytes
  local expected_machine
  local expected_name
  local optional_detail=""

  require_command od "Install the standard od utility and try again."
  header=$(LC_ALL=C od -An -v -tx1 -N20 "$binary" 2>/dev/null | tr -d '[:space:]') ||
    die "Could not read the Cleo executable header."
  [ "${#header}" -eq 40 ] ||
    die "The Cleo executable has a truncated ELF header."

  # Bytes 0-6 must be ELF magic, 64-bit class, little-endian encoding, and
  # ELF version 1. Linux x64 and ARM64 release executables use this format.
  case "$header" in
    7f454c46020101*) ;;
    *)
      if command -v file >/dev/null 2>&1; then
        optional_detail=$(LC_ALL=C file -b "$binary" 2>/dev/null || true)
      fi
      die "The payload is not a 64-bit little-endian ELF executable${optional_detail:+ ($optional_detail)}."
      ;;
  esac

  # ELF e_machine is the little-endian 16-bit value at byte offset 18.
  machine_bytes=${header:36:4}
  case "$ARCHITECTURE" in
    x64)
      expected_machine="3e00"
      expected_name="x86-64 (0x003e)"
      ;;
    arm64)
      expected_machine="b700"
      expected_name="AArch64 (0x00b7)"
      ;;
    *) die "Internal error: unsupported ELF architecture '$ARCHITECTURE'." ;;
  esac
  if [ "$machine_bytes" != "$expected_machine" ]; then
    if command -v file >/dev/null 2>&1; then
      optional_detail=$(LC_ALL=C file -b "$binary" 2>/dev/null || true)
    fi
    die "The ELF machine bytes are 0x$machine_bytes; expected $expected_name${optional_detail:+ ($optional_detail)}."
  fi
}

validate_linux_archive() {
  local archive="$WORK_DIR/$ASSET_NAME"
  local entries
  local extraction="$WORK_DIR/linux-payload"
  local files

  require_command tar "Install tar and try again."
  step "Checking the Linux archive contents"
  if ! entries=$(LC_ALL=C tar -tzf "$archive"); then
    die "$ASSET_NAME is not a readable gzip-compressed tar archive."
  fi
  [ "$entries" = "./Cleo" ] ||
    die "The Linux archive must contain exactly one entry named ./Cleo."

  mkdir "$extraction"
  if ! tar -xzf "$archive" -C "$extraction" ./Cleo; then
    die "Could not extract the verified Linux archive."
  fi
  if ! { [ -f "$extraction/Cleo" ] && [ ! -L "$extraction/Cleo" ] && \
         [ -x "$extraction/Cleo" ]; }; then
    die "The archive's Cleo entry is not a regular executable file."
  fi
  files=$(find "$extraction" -type f -print)
  [ "$files" = "$extraction/Cleo" ] ||
    die "Unexpected files appeared while extracting the Linux archive."
  validate_linux_binary_architecture "$extraction/Cleo"
  LINUX_EXTRACTED_BINARY="$extraction/Cleo"
  say "[OK] Archive contains one executable for $ARCHITECTURE_LABEL."
}

validate_chromebook_package() {
  local package="$WORK_DIR/$ASSET_NAME"
  local package_name
  local package_arch
  local expected_arch
  local payload_root="$WORK_DIR/deb-payload"
  local control_root="$WORK_DIR/deb-control"
  local actual_files
  local expected_files
  local unexpected_nodes
  local control_files
  local control_fields
  local expected_control_fields
  local package_version
  local package_section
  local package_priority
  local package_maintainer
  local package_homepage
  local package_depends
  local package_description
  local forbidden_field
  local forbidden_value
  local binary_mode
  local desktop_mode
  local icon_mode
  local payload_metadata_error

  require_command dpkg-deb \
    "Open the Chromebook Linux Terminal and install the standard dpkg tools."
  step "Checking the Chromebook package contents"

  dpkg-deb --info "$package" >/dev/null 2>&1 ||
    die "$ASSET_NAME is not a readable Debian package."
  package_name=$(dpkg-deb --field "$package" Package 2>/dev/null) ||
    die "The Debian package has no Package field."
  package_arch=$(dpkg-deb --field "$package" Architecture 2>/dev/null) ||
    die "The Debian package has no Architecture field."
  [ "$package_name" = "cleo" ] ||
    die "Unexpected Debian package name: $package_name"
  expected_arch="$CHROMEBOOK_DEB_ARCH"
  case "$expected_arch" in
    amd64|arm64) ;;
    *) die "Internal error: unsupported Chromebook Debian architecture '$expected_arch'." ;;
  esac
  [ "$package_arch" = "$expected_arch" ] ||
    die "The package architecture is $package_arch, but this Chromebook needs $expected_arch."

  control_fields=$(dpkg-deb --field "$package" 2>/dev/null | LC_ALL=C awk '
    /^[A-Za-z0-9][A-Za-z0-9-]*:/ {
      field = $1
      sub(/:.*/, "", field)
      print field
    }
  ' | LC_ALL=C sort) || die "Could not enumerate Debian control fields."
  expected_control_fields='Architecture
Depends
Description
Homepage
Maintainer
Package
Priority
Section
Version'
  [ "$control_fields" = "$expected_control_fields" ] ||
    die "The Debian package contains missing or unexpected control fields."

  for forbidden_field in Pre-Depends Conflicts Breaks Replaces; do
    forbidden_value=$(dpkg-deb --field "$package" "$forbidden_field" 2>/dev/null || true)
    [ -z "$forbidden_value" ] ||
      die "The Debian package contains a forbidden $forbidden_field relationship."
  done

  package_version=$(dpkg-deb --field "$package" Version 2>/dev/null) ||
    die "The Debian package has no Version field."
  package_section=$(dpkg-deb --field "$package" Section 2>/dev/null) ||
    die "The Debian package has no Section field."
  package_priority=$(dpkg-deb --field "$package" Priority 2>/dev/null) ||
    die "The Debian package has no Priority field."
  package_maintainer=$(dpkg-deb --field "$package" Maintainer 2>/dev/null) ||
    die "The Debian package has no Maintainer field."
  package_homepage=$(dpkg-deb --field "$package" Homepage 2>/dev/null) ||
    die "The Debian package has no Homepage field."
  package_depends=$(dpkg-deb --field "$package" Depends 2>/dev/null) ||
    die "The Debian package has no Depends field."
  package_description=$(dpkg-deb --field "$package" Description 2>/dev/null) ||
    die "The Debian package has no Description field."

  [[ "$package_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "Unexpected Debian package version: $package_version"
  [ "$package_section" = "education" ] ||
    die "Unexpected Debian package section: $package_section"
  [ "$package_priority" = "optional" ] ||
    die "Unexpected Debian package priority: $package_priority"
  [ "$package_maintainer" = "Cleo Project <noreply@github.com>" ] ||
    die "Unexpected Debian package maintainer: $package_maintainer"
  case "$package_homepage" in
    https://github.com/sahmsec/cleo-sqli|https://github.com/sahmsec/cleo_sc) ;;
    *) die "Unexpected Debian package homepage: $package_homepage" ;;
  esac
  [ "$package_depends" = "libx11-6, libice6, libsm6, libfontconfig1, ca-certificates" ] ||
    die "The Debian package requests unexpected dependencies: $package_depends"
  case "$package_description" in
    'Cleo desktop app for authorized security-testing education'*) ;;
    *) die "Unexpected Debian package description." ;;
  esac

  # Inspect the archive metadata itself, not just the files after extraction.
  # dpkg-deb preserves archive owners and directory modes during installation;
  # accepting extra directories or non-root owners would therefore let a
  # checksum-valid but malformed package modify paths outside this allowlist.
  if ! payload_metadata_error=$(LC_ALL=C dpkg-deb --contents "$package" |
      LC_ALL=C awk '
        BEGIN {
          expected["./"] = "drwxr-xr-x"
          expected["./usr/"] = "drwxr-xr-x"
          expected["./usr/bin/"] = "drwxr-xr-x"
          expected["./usr/bin/cleo"] = "-rwxr-xr-x"
          expected["./usr/share/"] = "drwxr-xr-x"
          expected["./usr/share/applications/"] = "drwxr-xr-x"
          expected["./usr/share/applications/cleo.desktop"] = "-rw-r--r--"
          expected["./usr/share/icons/"] = "drwxr-xr-x"
          expected["./usr/share/icons/hicolor/"] = "drwxr-xr-x"
          expected["./usr/share/icons/hicolor/256x256/"] = "drwxr-xr-x"
          expected["./usr/share/icons/hicolor/256x256/apps/"] = "drwxr-xr-x"
          expected["./usr/share/icons/hicolor/256x256/apps/cleo.png"] = "-rw-r--r--"
        }
        {
          if (NF != 6) {
            print "an entry has an unexpected listing format"
            next
          }
          path = $6
          if (!(path in expected)) {
            print "unexpected payload path " path
            next
          }
          if (++seen[path] != 1) {
            print "duplicate payload path " path
          }
          if ($1 != expected[path]) {
            print "unexpected mode for " path ": " $1
          }
          if ($2 != "root/root") {
            print "unexpected owner for " path ": " $2
          }
        }
        END {
          for (path in expected) {
            if (!(path in seen)) {
              print "missing payload path " path
            }
          }
        }
      '); then
    die "Could not enumerate Debian payload metadata."
  fi
  [ -z "$payload_metadata_error" ] ||
    die "The Debian package has unsafe payload metadata: $payload_metadata_error"

  mkdir "$payload_root" "$control_root"
  dpkg-deb -x "$package" "$payload_root" >/dev/null 2>&1 ||
    die "Could not inspect the Debian package payload."
  dpkg-deb -e "$package" "$control_root" >/dev/null 2>&1 ||
    die "Could not inspect the Debian package metadata."

  unexpected_nodes=$(cd "$payload_root" && find . ! -type d ! -type f -print | LC_ALL=C sort)
  [ -z "$unexpected_nodes" ] ||
    die "The Debian package contains an unexpected link or special file."
  actual_files=$(cd "$payload_root" && find . -type f -print | LC_ALL=C sort)
  expected_files='./usr/bin/cleo
./usr/share/applications/cleo.desktop
./usr/share/icons/hicolor/256x256/apps/cleo.png'
  [ "$actual_files" = "$expected_files" ] ||
    die "The Debian package does not have the expected three-file application payload."

  if ! { [ -f "$payload_root/usr/bin/cleo" ] && \
         [ ! -L "$payload_root/usr/bin/cleo" ] && \
         [ -x "$payload_root/usr/bin/cleo" ]; }; then
    die "The Debian package's /usr/bin/cleo is not a regular executable."
  fi
  [ -s "$payload_root/usr/share/applications/cleo.desktop" ] ||
    die "The Debian package's desktop entry is missing or empty."
  [ -s "$payload_root/usr/share/icons/hicolor/256x256/apps/cleo.png" ] ||
    die "The Debian package's icon is missing or empty."
  require_command stat "The Chromebook Linux environment needs the standard stat utility."
  binary_mode=$(stat -c '%a' "$payload_root/usr/bin/cleo" 2>/dev/null) ||
    die "Could not inspect the Debian executable permissions."
  desktop_mode=$(stat -c '%a' \
    "$payload_root/usr/share/applications/cleo.desktop" 2>/dev/null) ||
    die "Could not inspect the Debian desktop-entry permissions."
  icon_mode=$(stat -c '%a' \
    "$payload_root/usr/share/icons/hicolor/256x256/apps/cleo.png" 2>/dev/null) ||
    die "Could not inspect the Debian icon permissions."
  [ "$binary_mode" = "755" ] ||
    die "The Debian executable mode is $binary_mode; expected 0755."
  [ "$desktop_mode" = "644" ] ||
    die "The Debian desktop-entry mode is $desktop_mode; expected 0644."
  [ "$icon_mode" = "644" ] ||
    die "The Debian icon mode is $icon_mode; expected 0644."
  grep -q '^Exec=/usr/bin/cleo$' \
    "$payload_root/usr/share/applications/cleo.desktop" ||
    die "The Debian desktop entry does not launch /usr/bin/cleo."

  unexpected_nodes=$(cd "$control_root" && find . ! -type d ! -type f -print | LC_ALL=C sort)
  [ -z "$unexpected_nodes" ] ||
    die "The Debian control archive contains an unexpected link or special file."
  control_files=$(cd "$control_root" && find . -type f -print | LC_ALL=C sort)
  [ "$control_files" = "./control" ] ||
    die "The Debian package contains unexpected control scripts or metadata."

  validate_linux_binary_architecture "$payload_root/usr/bin/cleo"
  say "[OK] Debian package name, CPU, control files, and payload are valid."
}

validate_macos_app() {
  local application="$1"
  local contents_directory="$application/Contents"
  local executable="$application/Contents/MacOS/Cleo"
  local macos_directory="$application/Contents/MacOS"
  local plist="$application/Contents/Info.plist"
  local payload_entries
  local bundle_executable
  local bundle_identifier
  local architectures

  if ! { [ -d "$application" ] && [ ! -L "$application" ]; }; then
    die "The disk image does not contain a regular Cleo.app bundle."
  fi
  if ! { [ -d "$contents_directory" ] && [ ! -L "$contents_directory" ]; }; then
    die "Cleo.app has no regular Contents directory."
  fi
  if ! { [ -f "$plist" ] && [ ! -L "$plist" ]; }; then
    die "Cleo.app has no regular Contents/Info.plist file."
  fi
  if ! { [ -d "$macos_directory" ] && [ ! -L "$macos_directory" ]; }; then
    die "Cleo.app has no regular Contents/MacOS directory."
  fi
  if ! { [ -f "$executable" ] && [ ! -L "$executable" ] && \
         [ -x "$executable" ]; }; then
    die "Cleo.app does not contain its expected executable."
  fi

  payload_entries=$(find "$macos_directory" ! -path "$macos_directory" -print)
  [ "$payload_entries" = "$executable" ] ||
    die "Cleo.app must contain exactly one executable in Contents/MacOS."

  plutil -lint "$plist" >/dev/null 2>&1 ||
    die "Cleo.app contains an invalid Info.plist."
  bundle_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$plist" 2>/dev/null) || die "Cleo.app does not declare CFBundleExecutable."
  bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$plist" 2>/dev/null) || die "Cleo.app does not declare CFBundleIdentifier."
  [ "$bundle_executable" = "Cleo" ] ||
    die "Cleo.app declares an unexpected executable: $bundle_executable"
  [ "$bundle_identifier" = "in.sahmsec.cleo" ] ||
    die "Cleo.app declares an unexpected bundle identifier: $bundle_identifier"

  codesign --verify --deep --strict "$application" >/dev/null 2>&1 ||
    die "Cleo.app failed its internal code-signature verification."
  architectures=$(lipo -archs "$executable" 2>/dev/null) ||
    die "Could not inspect the Cleo.app executable architecture."
  case " $architectures " in
    *" arm64 "*) ;;
    *) die "Cleo.app is not an Apple Silicon application." ;;
  esac
}

validate_macos_package() {
  local package="$WORK_DIR/$ASSET_NAME"

  require_command hdiutil "This macOS installer requires Apple's hdiutil command."
  require_command plutil "This macOS installer requires Apple's plutil command."
  require_command codesign "This macOS installer requires Apple's codesign command."
  require_command lipo "This macOS installer requires Apple's lipo command."
  [ -x /usr/libexec/PlistBuddy ] ||
    die "This macOS installer requires Apple's /usr/libexec/PlistBuddy tool."

  step "Checking the macOS disk image and application"
  hdiutil verify "$package" >/dev/null 2>&1 ||
    die "$ASSET_NAME failed disk-image verification."
  MOUNT_POINT="$WORK_DIR/cleo-disk-image"
  mkdir "$MOUNT_POINT"
  if ! hdiutil attach -readonly -nobrowse -noautoopen \
      -mountpoint "$MOUNT_POINT" "$package" >/dev/null; then
    die "Could not open the verified Cleo disk image."
  fi
  MOUNT_ACTIVE=1
  validate_macos_app "$MOUNT_POINT/Cleo.app"
  say "[OK] Disk image, application structure, signature, and CPU are valid."
}

detach_macos_package() {
  if [ "$MOUNT_ACTIVE" -eq 1 ]; then
    if ! hdiutil detach "$MOUNT_POINT" >/dev/null; then
      die "Cleo was copied, but its temporary disk image could not be ejected."
    fi
    MOUNT_ACTIVE=0
  fi
}

is_recognizable_macos_install() {
  local application="$1"
  local contents_directory="$application/Contents"
  local macos_directory="$application/Contents/MacOS"
  local plist="$application/Contents/Info.plist"
  local executable="$application/Contents/MacOS/Cleo"
  local bundle_identifier

  [ -d "$application" ] && [ ! -L "$application" ] || return 1
  [ -d "$contents_directory" ] && [ ! -L "$contents_directory" ] || return 1
  [ -d "$macos_directory" ] && [ ! -L "$macos_directory" ] || return 1
  [ -f "$plist" ] && [ ! -L "$plist" ] || return 1
  [ -f "$executable" ] && [ ! -L "$executable" ] || return 1
  bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$plist" 2>/dev/null) || return 1
  [ "$bundle_identifier" = "in.sahmsec.cleo" ]
}

copy_download_only() {
  local destination_dir="$DOWNLOAD_ONLY_INPUT"
  local destination
  local copied_hash

  step "Saving the verified package without installing it"
  mkdir -p "$destination_dir" || die "Could not create download directory: $destination_dir"
  destination_dir=$(cd "$destination_dir" 2>/dev/null && pwd -P) ||
    die "Cannot access download directory: $destination_dir"
  destination="$destination_dir/$ASSET_NAME"
  [ ! -d "$destination" ] ||
    die "The download destination is a directory: $destination"

  DOWNLOAD_STAGE=$(mktemp "$destination_dir/.cleo-download.XXXXXXXX") ||
    die "Could not create a temporary download file in $destination_dir."
  cp "$WORK_DIR/$ASSET_NAME" "$DOWNLOAD_STAGE"
  chmod 0644 "$DOWNLOAD_STAGE"
  copied_hash=$(file_sha256 "$DOWNLOAD_STAGE") ||
    die "Could not verify the copied download."
  [ "$copied_hash" = "$EXPECTED_SHA256" ] ||
    die "The copied download failed its final checksum verification."

  [ ! -L "$destination" ] ||
    die "Refusing to replace a symbolic link at the download destination: $destination"
  mv -f "$DOWNLOAD_STAGE" "$destination"
  DOWNLOAD_STAGE=""
  say "[OK] Saved: $destination"
  say "SHA-256: $EXPECTED_SHA256"
  say "Nothing was installed or launched."
}

launch_linux_application() {
  local executable="$1"

  if [ "$NO_LAUNCH" -eq 1 ]; then
    say "Launch skipped because --no-launch was used."
    return
  fi
  if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    say "Cleo was installed, but no graphical desktop session was detected."
    say "Open it later by running: $executable"
    return
  fi
  if command -v nohup >/dev/null 2>&1; then
    nohup "$executable" >/dev/null 2>&1 &
  else
    "$executable" >/dev/null 2>&1 &
  fi
  say "Cleo is starting."
}

ensure_real_directory() {
  local directory="$1"
  local description="$2"

  [ ! -L "$directory" ] ||
    die "Refusing to use a symbolic link as $description: $directory"
  if [ -e "$directory" ]; then
    [ -d "$directory" ] || die "$description is not a directory: $directory"
  else
    mkdir "$directory" || die "Could not create $description: $directory"
  fi
  if ! { [ -d "$directory" ] && [ ! -L "$directory" ]; }; then
    die "$description was not created safely: $directory"
  fi
}

desktop_exec_escape() {
  # Freedesktop Exec values use double-quoted arguments. Backslash-escape the
  # four shell-like characters that remain special inside those quotes, and
  # double percent signs so paths cannot be interpreted as desktop field codes.
  # shellcheck disable=SC2016
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/`/\\`/g' \
    -e 's/\$/\\$/g' \
    -e 's/%/%%/g'
}

write_embedded_linux_icon() {
  local destination="$1"

  base64 -d > "$destination" <<'CLEO_LINUX_ICON_BASE64'
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
CLEO_LINUX_ICON_BASE64
}

revalidate_linux_owned_paths() {
  local install_directory="$1"
  local ownership_marker="$2"
  local command_target

  [ -d "$install_directory" ] && [ ! -L "$install_directory" ] || return 1
  [ -f "$ownership_marker" ] && [ ! -L "$ownership_marker" ] &&
    grep -Fqx 'bundle-id=in.sahmsec.cleo' "$ownership_marker" || return 1

  if [ "$LINUX_HAD_BINARY" -eq 1 ]; then
    [ -f "$LINUX_BINARY_DESTINATION" ] && \
      [ ! -L "$LINUX_BINARY_DESTINATION" ] || return 1
  else
    ! { [ -e "$LINUX_BINARY_DESTINATION" ] || \
        [ -L "$LINUX_BINARY_DESTINATION" ]; } || return 1
  fi

  if [ "$LINUX_HAD_DESKTOP" -eq 1 ]; then
    [ -f "$LINUX_DESKTOP_DESTINATION" ] && \
      [ ! -L "$LINUX_DESKTOP_DESTINATION" ] &&
      grep -Fqx 'X-Cleo-Installer=in.sahmsec.cleo' \
        "$LINUX_DESKTOP_DESTINATION" || return 1
  else
    ! { [ -e "$LINUX_DESKTOP_DESTINATION" ] || \
        [ -L "$LINUX_DESKTOP_DESTINATION" ]; } || return 1
  fi

  if [ "$LINUX_HAD_ICON" -eq 1 ]; then
    [ -f "$LINUX_ICON_DESTINATION" ] && \
      [ ! -L "$LINUX_ICON_DESTINATION" ] && \
      grep -Fqx 'Icon=in.sahmsec.cleo' \
        "$LINUX_DESKTOP_DESTINATION" || return 1
  else
    ! { [ -e "$LINUX_ICON_DESTINATION" ] || \
        [ -L "$LINUX_ICON_DESTINATION" ]; } || return 1
  fi

  if [ "$LINUX_HAD_COMMAND" -eq 1 ]; then
    [ -L "$LINUX_COMMAND_PATH" ] || return 1
    command_target=$(readlink "$LINUX_COMMAND_PATH" 2>/dev/null) || return 1
    [ "$command_target" = "$LINUX_BINARY_DESTINATION" ] || return 1
  else
    ! { [ -e "$LINUX_COMMAND_PATH" ] || [ -L "$LINUX_COMMAND_PATH" ]; } ||
      return 1
  fi
}

linux_command_path_matches_preflight() {
  local command_target

  if [ "$LINUX_HAD_COMMAND" -eq 1 ]; then
    [ -L "$LINUX_COMMAND_PATH" ] || return 1
    command_target=$(readlink "$LINUX_COMMAND_PATH" 2>/dev/null) || return 1
    [ "$command_target" = "$LINUX_BINARY_DESTINATION" ]
  else
    if [ -e "$LINUX_COMMAND_PATH" ] || [ -L "$LINUX_COMMAND_PATH" ]; then
      return 1
    fi
    return 0
  fi
}

linux_icon_path_matches_preflight() {
  if [ "$LINUX_HAD_ICON" -eq 1 ]; then
    [ -f "$LINUX_DESKTOP_DESTINATION" ] && \
      [ ! -L "$LINUX_DESKTOP_DESTINATION" ] && \
      grep -Fqx 'X-Cleo-Installer=in.sahmsec.cleo' \
        "$LINUX_DESKTOP_DESTINATION" && \
      grep -Fqx 'Icon=in.sahmsec.cleo' \
        "$LINUX_DESKTOP_DESTINATION" && \
    regular_file_has_sha256 "$LINUX_ICON_DESTINATION" \
      "$LINUX_OLD_ICON_SHA256"
  else
    if [ -e "$LINUX_ICON_DESTINATION" ] || \
       [ -L "$LINUX_ICON_DESTINATION" ]; then
      return 1
    fi
    return 0
  fi
}

linux_desktop_path_matches_preflight() {
  if [ "$LINUX_HAD_DESKTOP" -eq 1 ]; then
    [ -f "$LINUX_DESKTOP_DESTINATION" ] && \
      [ ! -L "$LINUX_DESKTOP_DESTINATION" ] && \
      grep -Fqx 'X-Cleo-Installer=in.sahmsec.cleo' \
        "$LINUX_DESKTOP_DESTINATION" && \
    regular_file_has_sha256 "$LINUX_DESKTOP_DESTINATION" \
      "$LINUX_OLD_DESKTOP_SHA256"
  else
    if [ -e "$LINUX_DESKTOP_DESTINATION" ] || \
       [ -L "$LINUX_DESKTOP_DESTINATION" ]; then
      return 1
    fi
    return 0
  fi
}

linux_install_identity_is_valid() {
  [ -n "$LINUX_INSTALL_DIRECTORY" ] && \
    [ -d "$LINUX_INSTALL_DIRECTORY" ] && \
    [ ! -L "$LINUX_INSTALL_DIRECTORY" ] && \
    [ -n "$LINUX_OWNERSHIP_MARKER" ] && \
    [ -f "$LINUX_OWNERSHIP_MARKER" ] && \
    [ ! -L "$LINUX_OWNERSHIP_MARKER" ] && \
    grep -Fqx 'bundle-id=in.sahmsec.cleo' "$LINUX_OWNERSHIP_MARKER"
}

install_linux_archive() {
  local user_home=${HOME:-}
  local local_root
  local share_root
  local install_directory
  local bin_directory
  local applications_directory
  local icons_directory
  local hicolor_directory
  local icon_size_directory
  local icon_applications_directory
  local destination
  local command_path
  local desktop_path
  local icon_path
  local ownership_marker
  local link_target
  local escaped_executable
  local new_install_directory=0
  local existing_install_owned=0
  local unexpected_new_entries
  local backup_hash
  local icon_mode

  [ -n "$user_home" ] || die "HOME is not set; a user-local installation path cannot be selected."
  case "$user_home" in
    /*) ;;
    *) die "HOME must be an absolute path for a safe user-local installation." ;;
  esac
  case "$user_home" in
    *$'\n'*|*$'\r'*) die "HOME contains a line break and cannot be used safely." ;;
  esac

  local_root="$user_home/.local"
  share_root="$local_root/share"
  install_directory="$share_root/cleo"
  bin_directory="$local_root/bin"
  applications_directory="$share_root/applications"
  icons_directory="$share_root/icons"
  hicolor_directory="$icons_directory/hicolor"
  icon_size_directory="$hicolor_directory/256x256"
  icon_applications_directory="$icon_size_directory/apps"
  destination="$install_directory/Cleo"
  command_path="$bin_directory/cleo"
  desktop_path="$applications_directory/cleo.desktop"
  icon_path="$icon_applications_directory/$CLEO_LINUX_ICON_NAME"
  ownership_marker="$install_directory/.installed-by-cleo-installer"
  LINUX_BINARY_DESTINATION="$destination"
  LINUX_DESKTOP_DESTINATION="$desktop_path"
  LINUX_ICON_DESTINATION="$icon_path"
  LINUX_COMMAND_PATH="$command_path"
  LINUX_INSTALL_DIRECTORY="$install_directory"
  LINUX_OWNERSHIP_MARKER="$ownership_marker"

  step "Installing Cleo for the current Linux user"
  require_command base64 "Install the standard base64 utility and try again."
  require_command stat "Install the standard stat utility and try again."

  # Inspect every path that may be replaced before changing anything. The
  # marker and exact symlink target distinguish our layout from an unrelated
  # program that happens to be named cleo.
  if [ -e "$install_directory" ] || [ -L "$install_directory" ]; then
    if ! { [ -d "$install_directory" ] && [ ! -L "$install_directory" ]; }; then
      die "Refusing to replace an unrelated path: $install_directory"
    fi
    if ! { [ -f "$ownership_marker" ] && [ ! -L "$ownership_marker" ] && \
           grep -Fqx 'bundle-id=in.sahmsec.cleo' "$ownership_marker"; }; then
      die "Refusing to update $install_directory because it is not marked as a Cleo installer directory."
    fi
    existing_install_owned=1
    if [ -e "$destination" ] || [ -L "$destination" ]; then
      if ! { [ -f "$destination" ] && [ ! -L "$destination" ]; }; then
        die "Refusing to replace an unrelated Cleo executable path: $destination"
      fi
      LINUX_HAD_BINARY=1
    fi
  else
    new_install_directory=1
  fi

  if [ -e "$command_path" ] || [ -L "$command_path" ]; then
    [ "$existing_install_owned" -eq 1 ] ||
      die "Refusing to overwrite a Cleo command link without an installer-owned Cleo directory: $command_path"
    [ -L "$command_path" ] ||
      die "Refusing to overwrite the existing command because it is not an installer-owned link: $command_path"
    link_target=$(readlink "$command_path" 2>/dev/null) ||
      die "Could not inspect the existing command link: $command_path"
    [ "$link_target" = "$destination" ] ||
      die "Refusing to overwrite an unrelated command link: $command_path -> $link_target"
    LINUX_HAD_COMMAND=1
  fi

  if [ -e "$desktop_path" ] || [ -L "$desktop_path" ]; then
    [ "$existing_install_owned" -eq 1 ] ||
      die "Refusing to overwrite a Cleo desktop entry without an installer-owned Cleo directory: $desktop_path"
    if ! { [ -f "$desktop_path" ] && [ ! -L "$desktop_path" ] && \
           grep -Fqx 'X-Cleo-Installer=in.sahmsec.cleo' "$desktop_path"; }; then
      die "Refusing to overwrite an unrelated application-menu entry: $desktop_path"
    fi
    LINUX_HAD_DESKTOP=1
  fi

  if [ -e "$icon_path" ] || [ -L "$icon_path" ]; then
    if ! { [ -f "$icon_path" ] && [ ! -L "$icon_path" ] && \
           [ "$existing_install_owned" -eq 1 ] && \
           [ "$LINUX_HAD_DESKTOP" -eq 1 ] && \
           grep -Fqx 'Icon=in.sahmsec.cleo' "$desktop_path"; }; then
      die "Refusing to overwrite an application icon that is not claimed by the existing Cleo desktop entry: $icon_path"
    fi
    LINUX_HAD_ICON=1
  fi

  ensure_real_directory "$local_root" "the user-local data directory"
  ensure_real_directory "$share_root" "the user-local share directory"
  ensure_real_directory "$bin_directory" "the user-local command directory"
  ensure_real_directory "$applications_directory" "the user application-menu directory"
  ensure_real_directory "$icons_directory" "the user icon directory"
  ensure_real_directory "$hicolor_directory" "the hicolor icon directory"
  ensure_real_directory "$icon_size_directory" "the 256x256 icon directory"
  ensure_real_directory "$icon_applications_directory" "the application icon directory"
  if [ "$new_install_directory" -eq 1 ]; then
    ! { [ -e "$install_directory" ] || [ -L "$install_directory" ]; } ||
      die "The Cleo installation path appeared before it could be created safely: $install_directory"
    mkdir "$install_directory" ||
      die "Could not create the Cleo installation directory: $install_directory"
    LINUX_CREATED_INSTALL_DIRECTORY=1
    if ! { [ -d "$install_directory" ] && [ ! -L "$install_directory" ]; }; then
      die "The Cleo installation directory was not created safely: $install_directory"
    fi
    unexpected_new_entries=$(find "$install_directory" ! -path "$install_directory" -print)
    [ -z "$unexpected_new_entries" ] ||
      die "The new Cleo installation directory changed before it could be marked; no files were replaced."
    ( set -o noclobber
      printf '%s\n' 'bundle-id=in.sahmsec.cleo' > "$ownership_marker"
    ) || die "Could not create the Cleo ownership marker safely."
    chmod 0644 "$ownership_marker"
  else
    ensure_real_directory "$install_directory" "the Cleo installation directory"
  fi

  LINUX_INSTALL_STAGE=$(mktemp "$install_directory/.cleo-install.XXXXXXXX") ||
    die "Could not create an installation staging file in $install_directory."
  cp "$LINUX_EXTRACTED_BINARY" "$LINUX_INSTALL_STAGE"
  chmod 0755 "$LINUX_INSTALL_STAGE"
  if ! { [ -f "$LINUX_INSTALL_STAGE" ] && [ -x "$LINUX_INSTALL_STAGE" ]; }; then
    die "The staged Linux executable is invalid."
  fi

  LINUX_ICON_STAGE=$(mktemp \
    "$icon_applications_directory/.cleo-icon.XXXXXXXX") ||
    die "Could not create an application-icon staging file."
  write_embedded_linux_icon "$LINUX_ICON_STAGE" ||
    die "Could not decode the embedded Cleo application icon."
  chmod 0644 "$LINUX_ICON_STAGE"
  if ! { [ -f "$LINUX_ICON_STAGE" ] && [ ! -L "$LINUX_ICON_STAGE" ] && \
         [ -s "$LINUX_ICON_STAGE" ]; }; then
    die "The staged Cleo application icon is invalid."
  fi
  LINUX_NEW_ICON_SHA256=$(file_sha256 "$LINUX_ICON_STAGE") ||
    die "Could not hash the staged Cleo application icon."
  [ "$LINUX_NEW_ICON_SHA256" = "$CLEO_LINUX_ICON_SHA256" ] ||
    die "The embedded Cleo application icon failed its built-in SHA-256 check."
  icon_mode=$(stat -c '%a' "$LINUX_ICON_STAGE" 2>/dev/null) ||
    die "Could not inspect the staged Cleo application icon permissions."
  [ "$icon_mode" = "644" ] ||
    die "The staged Cleo application icon mode is $icon_mode; expected 0644."

  escaped_executable=$(desktop_exec_escape "$destination") ||
    die "Could not prepare the desktop-menu command."
  LINUX_DESKTOP_STAGE=$(mktemp "$applications_directory/.cleo.desktop.XXXXXXXX") ||
    die "Could not create an application-menu staging file."
  cat > "$LINUX_DESKTOP_STAGE" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Cleo
Comment=Authorized MySQL security-testing education tool
Exec="$escaped_executable"
Icon=in.sahmsec.cleo
Categories=Education;Development;
Terminal=false
X-Cleo-Installer=in.sahmsec.cleo
DESKTOP
  chmod 0644 "$LINUX_DESKTOP_STAGE"

  LINUX_NEW_BINARY_SHA256=$(file_sha256 "$LINUX_INSTALL_STAGE") ||
    die "Could not hash the staged Linux executable."
  LINUX_NEW_DESKTOP_SHA256=$(file_sha256 "$LINUX_DESKTOP_STAGE") ||
    die "Could not hash the staged Linux desktop entry."

  # Recheck ownership and path types after staging, immediately before creating
  # rollback copies and again immediately before the first replacement.
  revalidate_linux_owned_paths "$install_directory" "$ownership_marker" ||
    die "An installer-owned Linux path changed during staging; no files were replaced."
  if [ "$LINUX_HAD_BINARY" -eq 1 ]; then
    LINUX_OLD_BINARY_SHA256=$(file_sha256 "$destination") ||
      die "Could not hash the existing Cleo executable for rollback."
    LINUX_BINARY_BACKUP=$(mktemp "$install_directory/.cleo-rollback.XXXXXXXX") ||
      die "Could not create the executable rollback copy."
    cp -p "$destination" "$LINUX_BINARY_BACKUP"
    backup_hash=$(file_sha256 "$LINUX_BINARY_BACKUP") ||
      die "Could not verify the executable rollback copy."
    [ "$backup_hash" = "$LINUX_OLD_BINARY_SHA256" ] ||
      die "The executable rollback copy did not verify."
  fi
  if [ "$LINUX_HAD_ICON" -eq 1 ]; then
    LINUX_OLD_ICON_SHA256=$(file_sha256 "$icon_path") ||
      die "Could not hash the existing Cleo application icon for rollback."
    LINUX_ICON_BACKUP=$(mktemp \
      "$icon_applications_directory/.cleo-rollback.XXXXXXXX") ||
      die "Could not create the application-icon rollback copy."
    cp -p "$icon_path" "$LINUX_ICON_BACKUP"
    backup_hash=$(file_sha256 "$LINUX_ICON_BACKUP") ||
      die "Could not verify the application-icon rollback copy."
    [ "$backup_hash" = "$LINUX_OLD_ICON_SHA256" ] ||
      die "The application-icon rollback copy did not verify."
  fi
  if [ "$LINUX_HAD_DESKTOP" -eq 1 ]; then
    LINUX_OLD_DESKTOP_SHA256=$(file_sha256 "$desktop_path") ||
      die "Could not hash the existing desktop entry for rollback."
    LINUX_DESKTOP_BACKUP=$(mktemp "$applications_directory/.cleo-rollback.XXXXXXXX") ||
      die "Could not create the desktop-entry rollback copy."
    cp -p "$desktop_path" "$LINUX_DESKTOP_BACKUP"
    backup_hash=$(file_sha256 "$LINUX_DESKTOP_BACKUP") ||
      die "Could not verify the desktop-entry rollback copy."
    [ "$backup_hash" = "$LINUX_OLD_DESKTOP_SHA256" ] ||
      die "The desktop-entry rollback copy did not verify."
  fi
  revalidate_linux_owned_paths "$install_directory" "$ownership_marker" ||
    die "An installer-owned Linux path changed immediately before update; no files were replaced."
  if [ "$LINUX_HAD_BINARY" -eq 1 ]; then
    regular_file_has_sha256 "$destination" "$LINUX_OLD_BINARY_SHA256" ||
      die "The existing Cleo executable changed immediately before update; no files were replaced."
  fi
  if [ "$LINUX_HAD_DESKTOP" -eq 1 ]; then
    regular_file_has_sha256 "$desktop_path" "$LINUX_OLD_DESKTOP_SHA256" ||
      die "The existing desktop entry changed immediately before update; no files were replaced."
  fi
  if [ "$LINUX_HAD_ICON" -eq 1 ]; then
    regular_file_has_sha256 "$icon_path" "$LINUX_OLD_ICON_SHA256" ||
      die "The existing Cleo application icon changed immediately before update; no files were replaced."
  fi
  regular_file_has_sha256 "$LINUX_INSTALL_STAGE" "$LINUX_NEW_BINARY_SHA256" ||
    die "The staged Cleo executable changed immediately before update; no files were replaced."
  regular_file_has_sha256 "$LINUX_ICON_STAGE" "$LINUX_NEW_ICON_SHA256" ||
    die "The staged Cleo application icon changed immediately before update; no files were replaced."
  regular_file_has_sha256 "$LINUX_DESKTOP_STAGE" "$LINUX_NEW_DESKTOP_SHA256" ||
    die "The staged desktop entry changed immediately before update; no files were replaced."
  if [ "$LINUX_HAD_BINARY" -eq 1 ]; then
    regular_file_has_sha256 "$LINUX_BINARY_BACKUP" "$LINUX_OLD_BINARY_SHA256" ||
      die "The executable rollback copy changed before update; no files were replaced."
  fi
  if [ "$LINUX_HAD_DESKTOP" -eq 1 ]; then
    regular_file_has_sha256 "$LINUX_DESKTOP_BACKUP" "$LINUX_OLD_DESKTOP_SHA256" ||
      die "The desktop rollback copy changed before update; no files were replaced."
  fi
  if [ "$LINUX_HAD_ICON" -eq 1 ]; then
    regular_file_has_sha256 "$LINUX_ICON_BACKUP" "$LINUX_OLD_ICON_SHA256" ||
      die "The application-icon rollback copy changed before update; no files were replaced."
  fi
  revalidate_linux_owned_paths "$install_directory" "$ownership_marker" ||
    die "An installer-owned Linux path changed at the commit boundary; no files were replaced."

  LINUX_TRANSACTION_ACTIVE=1
  LINUX_BINARY_REPLACED=1
  mv -f "$LINUX_INSTALL_STAGE" "$destination" ||
    die "Could not commit the staged Cleo executable."
  LINUX_INSTALL_STAGE=""

  # Every destination and rollback object is checked again immediately before
  # its own rename. The full preflight helper cannot be reused after the first
  # component changes because it intentionally describes the old state.
  regular_file_has_sha256 "$destination" "$LINUX_NEW_BINARY_SHA256" ||
    die "The committed Cleo executable changed before the icon update."
  linux_install_identity_is_valid ||
    die "The Cleo installation marker changed before the icon update."
  if ! { [ -d "$icons_directory" ] && [ ! -L "$icons_directory" ] && \
         [ -d "$hicolor_directory" ] && [ ! -L "$hicolor_directory" ] && \
         [ -d "$icon_size_directory" ] && [ ! -L "$icon_size_directory" ] && \
         [ -d "$icon_applications_directory" ] && \
         [ ! -L "$icon_applications_directory" ]; }; then
    die "The Cleo application-icon directory changed before commit."
  fi
  linux_command_path_matches_preflight ||
    die "The Cleo command path changed before the icon update."
  linux_icon_path_matches_preflight ||
    die "The Cleo application icon changed at its commit boundary."
  regular_file_has_sha256 "$LINUX_ICON_STAGE" "$LINUX_NEW_ICON_SHA256" ||
    die "The staged Cleo application icon changed at its commit boundary."
  if [ "$LINUX_HAD_ICON" -eq 1 ]; then
    regular_file_has_sha256 "$LINUX_ICON_BACKUP" "$LINUX_OLD_ICON_SHA256" ||
      die "The application-icon rollback copy changed at the commit boundary."
  fi
  LINUX_ICON_REPLACED=1
  mv -f "$LINUX_ICON_STAGE" "$icon_path" ||
    die "Could not commit the staged Cleo application icon."
  LINUX_ICON_STAGE=""

  regular_file_has_sha256 "$destination" "$LINUX_NEW_BINARY_SHA256" ||
    die "The committed Cleo executable changed before the desktop update."
  regular_file_has_sha256 "$icon_path" "$LINUX_NEW_ICON_SHA256" ||
    die "The committed Cleo application icon changed before the desktop update."
  linux_install_identity_is_valid ||
    die "The Cleo installation marker changed before the desktop update."
  if ! { [ -d "$applications_directory" ] && \
         [ ! -L "$applications_directory" ]; }; then
    die "The user application-menu directory changed before commit."
  fi
  linux_command_path_matches_preflight ||
    die "The Cleo command path changed before the desktop update."
  linux_desktop_path_matches_preflight ||
    die "The Cleo desktop entry changed at its commit boundary."
  regular_file_has_sha256 "$LINUX_DESKTOP_STAGE" "$LINUX_NEW_DESKTOP_SHA256" ||
    die "The staged Cleo desktop entry changed at its commit boundary."
  if [ "$LINUX_HAD_DESKTOP" -eq 1 ]; then
    regular_file_has_sha256 "$LINUX_DESKTOP_BACKUP" \
      "$LINUX_OLD_DESKTOP_SHA256" ||
      die "The desktop-entry rollback copy changed at the commit boundary."
  fi
  LINUX_DESKTOP_REPLACED=1
  mv -f "$LINUX_DESKTOP_STAGE" "$desktop_path" ||
    die "Could not commit the staged application-menu entry."
  LINUX_DESKTOP_STAGE=""

  linux_command_path_matches_preflight ||
    die "The Cleo command path changed at its commit boundary."
  linux_install_identity_is_valid ||
    die "The Cleo installation marker changed before command creation."
  if [ "$LINUX_HAD_COMMAND" -eq 0 ]; then
    LINUX_COMMAND_CREATED=1
    ln -s "$destination" "$command_path" ||
      die "Cleo was installed, but its command link could not be created at $command_path."
  fi

  regular_file_has_sha256 "$destination" "$LINUX_NEW_BINARY_SHA256" ||
    die "The committed Cleo executable failed final verification."
  regular_file_has_sha256 "$icon_path" "$LINUX_NEW_ICON_SHA256" ||
    die "The committed Cleo application icon failed final verification."
  icon_mode=$(stat -c '%a' "$icon_path" 2>/dev/null) ||
    die "Could not inspect the committed Cleo application icon permissions."
  [ "$icon_mode" = "644" ] ||
    die "The committed Cleo application icon mode is $icon_mode; expected 0644."
  regular_file_has_sha256 "$desktop_path" "$LINUX_NEW_DESKTOP_SHA256" ||
    die "The committed application-menu entry failed final verification."
  grep -Fqx 'Icon=in.sahmsec.cleo' "$desktop_path" ||
    die "The committed application-menu entry does not reference the Cleo icon."
  [ -L "$command_path" ] || die "The committed Cleo command is not a symbolic link."
  link_target=$(readlink "$command_path" 2>/dev/null) ||
    die "Could not verify the committed Cleo command link."
  [ "$link_target" = "$destination" ] ||
    die "The committed Cleo command link points to an unexpected path."
  if ! linux_install_identity_is_valid; then
    die "The Linux ownership marker changed before commit completed."
  fi
  LINUX_TRANSACTION_COMMITTED=1

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$applications_directory" >/dev/null 2>&1 || true
  fi

  say "[OK] Installed: $destination"
  say "[OK] Command:   $command_path"
  say "[OK] App menu:  $desktop_path"
  say "[OK] App icon:  $icon_path"
  case ":${PATH:-}:" in
    *":$bin_directory:"*) ;;
    *)
      say "Note: $bin_directory is not currently on PATH."
      say "You can always start Cleo with: $destination"
      ;;
  esac
  launch_linux_application "$destination"
}

install_chromebook_package() {
  local package="$WORK_DIR/$ASSET_NAME"
  local current_uid
  local parent_owner
  local root_stage_metadata
  local root_hash_output
  local root_hash

  require_command apt-get \
    "The Chromebook Linux environment needs apt-get to install this package."
  require_command install \
    "The Chromebook Linux environment needs the standard install utility."
  require_command sha256sum \
    "The Chromebook Linux environment needs sha256sum for the privileged recheck."
  require_command stat \
    "The Chromebook Linux environment needs the standard stat utility."
  current_uid=$(id -u 2>/dev/null) || die "Could not determine the current user."

  step "Installing the verified Chromebook package"
  say "The package has passed every check. Administrator access is requested only now."
  if [ "$current_uid" != "0" ]; then
    require_command sudo \
      "This Chromebook user cannot install a .deb package without sudo access."
    USE_SUDO=1
  fi

  if ! { [ -d "$CLEO_ROOT_STAGE_PARENT" ] && \
         [ ! -L "$CLEO_ROOT_STAGE_PARENT" ]; }; then
    die "Root staging parent is not a regular directory: $CLEO_ROOT_STAGE_PARENT"
  fi
  parent_owner=$(stat -c '%u' "$CLEO_ROOT_STAGE_PARENT" 2>/dev/null) ||
    die "Could not inspect $CLEO_ROOT_STAGE_PARENT."
  [ "$parent_owner" = "0" ] ||
    die "Root staging parent is not owned by root: $CLEO_ROOT_STAGE_PARENT"

  # Only now, after checksum, structure, metadata, mode, and ELF validation,
  # create an inaccessible root-owned copy. A same-user process cannot change
  # the bytes that apt will consume after the final hash check below.
  if ! ROOT_STAGE_DIR=$(run_privileged mktemp -d \
      "${CLEO_ROOT_STAGE_PREFIX}XXXXXXXX"); then
    die "Could not create a root-owned private package staging directory."
  fi
  ROOT_STAGE_CREATED=1
  [ "${ROOT_STAGE_DIR%/*}" = "$CLEO_ROOT_STAGE_PARENT" ] ||
    die "The root staging directory was created outside $CLEO_ROOT_STAGE_PARENT."
  case "$ROOT_STAGE_DIR" in
    "$CLEO_ROOT_STAGE_PREFIX"*) ;;
    *) die "The root staging directory has an unexpected path: $ROOT_STAGE_DIR" ;;
  esac
  if ! run_privileged install -m 0600 /dev/null \
      "$ROOT_STAGE_DIR/.cleo-installer-owned"; then
    die "Could not mark the root-owned package staging directory."
  fi
  ROOT_STAGE_READY=1
  root_stage_has_safe_identity ||
    die "The root-owned package staging directory failed its ownership checks."

  ROOT_STAGE_PACKAGE="$ROOT_STAGE_DIR/$ASSET_NAME"
  run_privileged install -m 0600 "$package" "$ROOT_STAGE_PACKAGE" ||
    die "Could not copy the verified package into root-owned staging."
  if ! { run_privileged test -f "$ROOT_STAGE_PACKAGE" &&
         run_privileged test ! -L "$ROOT_STAGE_PACKAGE"; }; then
    die "The root-staged package is not a regular file."
  fi
  root_stage_metadata=$(run_privileged stat -c '%u:%a' \
    "$ROOT_STAGE_PACKAGE" 2>/dev/null) ||
    die "Could not inspect the root-staged package."
  [ "$root_stage_metadata" = "0:600" ] ||
    die "The root-staged package has unexpected owner or mode: $root_stage_metadata"

  # Keep this SHA-256 calculation immediately adjacent to apt. The directory
  # is root-owned mode 0700 and the package is root-owned mode 0600.
  root_hash_output=$(run_privileged sha256sum "$ROOT_STAGE_PACKAGE") ||
    die "Could not hash the root-staged package."
  root_hash=${root_hash_output%% *}
  [ "${#root_hash}" -eq 64 ] || die "The privileged SHA-256 output was invalid."
  case "$root_hash" in
    *[!0-9A-Fa-f]*) die "The privileged SHA-256 output was invalid." ;;
  esac
  root_hash=$(printf '%s' "$root_hash" | tr 'A-F' 'a-f')
  [ "$root_hash" = "$EXPECTED_SHA256" ] ||
    die "The package changed before privileged installation; apt was not run."
  run_privileged apt-get install -y "$ROOT_STAGE_PACKAGE"

  [ -x /usr/bin/cleo ] ||
    die "The package manager finished, but /usr/bin/cleo was not installed correctly."
  say "[OK] Installed: /usr/bin/cleo"
  launch_linux_application /usr/bin/cleo
}

install_macos_package() {
  local user_home=${HOME:-}
  local staged_application
  local staged_identity
  local installed_identity

  require_command ditto "This macOS installer requires Apple's ditto command."
  require_command open "This macOS installer requires Apple's open command."
  [ -x /usr/bin/stat ] || die "This macOS installer requires Apple's /usr/bin/stat tool."
  [ -x /bin/mv ] || die "This macOS installer requires Apple's /bin/mv tool."
  [ -n "$user_home" ] || die "HOME is not set; a user-local installation path cannot be selected."
  case "$user_home" in
    /*) ;;
    *) die "HOME must be an absolute path for a safe user-local installation." ;;
  esac
  case "$user_home" in
    *$'\n'*|*$'\r'*) die "HOME contains a line break and cannot be used safely." ;;
  esac

  MAC_INSTALL_ROOT="$user_home/Applications"
  MAC_DESTINATION="$MAC_INSTALL_ROOT/Cleo.app"
  step "Installing Cleo for the current macOS user"
  ensure_real_directory "$MAC_INSTALL_ROOT" "the user Applications folder"
  if [ -e "$MAC_DESTINATION" ] || [ -L "$MAC_DESTINATION" ]; then
    is_recognizable_macos_install "$MAC_DESTINATION" ||
      die "Refusing to replace $MAC_DESTINATION because it is not a recognizable in.sahmsec.cleo application bundle."
  fi
  MAC_STAGE_ROOT=$(mktemp -d "$MAC_INSTALL_ROOT/.cleo-install.XXXXXXXX") ||
    die "Could not create an installation staging directory in $MAC_INSTALL_ROOT."
  case "$MAC_STAGE_ROOT" in
    "$MAC_INSTALL_ROOT"/.cleo-install.*) ;;
    *) die "The macOS staging directory was created in an unexpected location." ;;
  esac
  : > "$MAC_STAGE_ROOT/.cleo-installer-owned"
  staged_application="$MAC_STAGE_ROOT/Cleo.app"

  ditto "$MOUNT_POINT/Cleo.app" "$staged_application" ||
    die "Could not copy Cleo.app from the verified disk image."
  validate_macos_app "$staged_application"
  staged_identity=$(/usr/bin/stat -f '%d:%i' "$staged_application" 2>/dev/null) ||
    die "Could not identify the staged Cleo.app before installation."
  [ -n "$staged_identity" ] ||
    die "The staged Cleo.app returned an empty filesystem identity."
  detach_macos_package

  # Repeat the destination checks after the comparatively slow image copy and
  # immediately before any rename. In particular, never follow or replace a
  # Cleo.app symlink introduced while the disk image was mounted.
  ensure_real_directory "$MAC_INSTALL_ROOT" "the user Applications folder"
  if [ -e "$MAC_DESTINATION" ] || [ -L "$MAC_DESTINATION" ]; then
    is_recognizable_macos_install "$MAC_DESTINATION" ||
      die "Cleo.app changed before replacement and is no longer a recognizable in.sahmsec.cleo bundle."
    MAC_BACKUP="$MAC_STAGE_ROOT/previous-Cleo.app"
    ! { [ -e "$MAC_BACKUP" ] || [ -L "$MAC_BACKUP" ]; } ||
      die "The macOS rollback destination changed unexpectedly."
    /bin/mv -h "$MAC_DESTINATION" "$MAC_BACKUP" ||
      die "Could not stage the existing Cleo.app for a safe upgrade."
    # Validate the object actually renamed, closing the check/rename gap. If a
    # same-user process swapped the destination after the preceding check, the
    # unexpected object is restored by cleanup rather than ever being erased.
    is_recognizable_macos_install "$MAC_BACKUP" ||
      die "The application moved for rollback is not a recognizable in.sahmsec.cleo bundle; it will not be deleted."
  fi
  ensure_real_directory "$MAC_INSTALL_ROOT" "the user Applications folder"
  ! { [ -e "$MAC_DESTINATION" ] || [ -L "$MAC_DESTINATION" ]; } ||
    die "Cleo.app reappeared at the install destination before commit; the previous app is preserved."
  if ! /bin/mv -h "$staged_application" "$MAC_DESTINATION"; then
    if [ -n "$MAC_BACKUP" ] && \
       { [ -e "$MAC_BACKUP" ] || [ -L "$MAC_BACKUP" ]; }; then
      /bin/mv -h "$MAC_BACKUP" "$MAC_DESTINATION" >/dev/null 2>&1 || true
    fi
    die "Could not move Cleo.app into $MAC_INSTALL_ROOT."
  fi
  installed_identity=$(/usr/bin/stat -f '%d:%i' "$MAC_DESTINATION" 2>/dev/null) ||
    die "Could not identify Cleo.app after its final rename; the previous app is preserved."
  [ "$installed_identity" = "$staged_identity" ] ||
    die "The final Cleo.app path is not the staged application; the previous app is preserved."
  validate_macos_app "$MAC_DESTINATION"
  MAC_SWAP_COMPLETE=1
  say "[OK] Installed: $MAC_DESTINATION"

  if [ "$NO_LAUNCH" -eq 1 ]; then
    say "Launch skipped because --no-launch was used."
  elif open "$MAC_DESTINATION"; then
    say "Cleo is starting."
    say "If macOS blocks the first launch, use System Settings > Privacy & Security > Open Anyway."
  else
    say "Cleo is installed, but macOS could not open it automatically."
    say "Open it later from: $MAC_DESTINATION"
  fi
}

main() {
  umask 077
  parse_options "$@"
  detect_system
  validate_linux_userspace

  step "System detection"
  print_detection
  if [ "$DETECT_ONLY" -eq 1 ]; then
    exit 0
  fi

  create_work_directory
  prepare_assets
  say "Release source: $RELEASE_LABEL"
  verify_checksum

  case "$PLATFORM" in
    linux)      validate_linux_archive ;;
    chromebook) validate_chromebook_package ;;
    macos)      validate_macos_package ;;
    *)          die "Internal error: unsupported platform '$PLATFORM'." ;;
  esac

  if [ -n "$DOWNLOAD_ONLY_INPUT" ]; then
    if [ "$PLATFORM" = "macos" ]; then
      detach_macos_package
    fi
    copy_download_only
    exit 0
  fi

  case "$PLATFORM" in
    linux)      install_linux_archive ;;
    chromebook) install_chromebook_package ;;
    macos)      install_macos_package ;;
  esac

  say ""
  say "Installation complete. Use Cleo only on systems you are authorized to test."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
