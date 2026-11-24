#!/usr/bin/env bash
# VIctory under Proton: run the Windows build of victory inside a Proton
# prefix, which supplies exactly what victory hosts on — a Win32 process
# environment with real D3D12 (via dxvk/vkd3d-proton). See docs/proton.md.
#
# The executable is built here with the gnu target (cargo win); nothing in
# this script touches the game itself.
set -euo pipefail

usage() {
    cat <<'USAGE'
usage: proton/run.sh [options] [--] [victory args...]

  --prefix DIR   Proton/Wine prefix (default: $XDG_DATA_HOME/victory/proton)
  --exe FILE     victory.exe to run (default: the cargo win output under target/)
  --proton DIR   Proton directory, or a plain wine binary
                 (default: newest GE-Proton under Steam's compatibilitytools.d)
  --z DIR        link DIR into the prefix's Z: drive as Z:\<basename>
  --config NAME  victory config to use, relative to the repo root
                 (default: victory.toml if present; see docs/proton.md)

Examples:
  proton/run.sh config
  proton/run.sh --z /mnt/games inspect "Z:\\game\\scripts\\x64\\final.js.c.c.gmpc"
USAGE
}

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${VICTORY_PROTON_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/victory/proton}"
exe="${VICTORY_EXE:-$repo/target/x86_64-pc-windows-gnu/release/victory.exe}"
proton="${PROTON:-}"
z_dir=""
config=""

while [[ $# -gt 0 && $1 != -- ]]; do
    case "$1" in
        --prefix) prefix=$2; shift 2 ;;
        --exe)    exe=$2; shift 2 ;;
        --proton) proton=$2; shift 2 ;;
        --z)      z_dir=$2; shift 2 ;;
        --config) config=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)      break ;;
    esac
done
[[ $# -gt 0 && $1 == -- ]] && shift
[[ $# -gt 0 ]] || set -- config

die() { echo "proton/run.sh: $*" >&2; exit 1; }

# Newest GE-Proton, then any Proton-*, from Steam's compatibility tools.
if [[ -z $proton ]]; then
    tools=${STEAM_COMPAT_TOOLS:-$HOME/.local/share/Steam/compatibilitytools.d}
    if [[ -d $tools ]]; then
        newest=$(find "$tools" -maxdepth 1 -mindepth 1 -type d \
            \( -name 'GE-Proton*' -o -name 'Proton-*' \) -printf '%f\n' \
            | sort -V | tail -n1)
        [[ -n $newest ]] && proton=$tools/$newest
    fi
fi
[[ -n $proton ]] || die "no Proton found; install one under compatibilitytools.d or pass --proton"

[[ -x "$proton/proton" || -x "$proton" ]] || die "$proton is neither a Proton directory nor an executable"
[[ -f $exe ]] || die "no $exe — build it with: cargo win"

mkdir -p "$prefix"

# The prefix's Z: drive is a plain directory; linked folders appear under it,
# so game_dir can read as e.g. Z:\game while living wherever you keep it.
if [[ -n $z_dir ]]; then
    mkdir -p "$prefix/drive_z"
    ln -sfn -- "$z_dir" "$prefix/drive_z/$(basename -- "$z_dir")"
fi

# Steam uses these when launching Proton; the proton script wants them even
# when driven by hand.
export WINEPREFIX=$prefix
export STEAM_COMPAT_DATA_PATH=$prefix
export STEAM_COMPAT_CLIENT_INSTALL_PATH=${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.steam/Steam}

# Wine resolves the process' Unix cwd through its Z: mapping, so a config
# given relative to the repo root works on both sides unchanged.
cd "$repo"
if [[ -n $config ]]; then
    [[ -f $config ]] || die "no $repo/$config"
    export VICTORY_CONFIG=$config
fi

if [[ -x "$proton/proton" ]]; then
    exec "$proton/proton" run "$exe" "$@"
else
    exec "$proton" "$exe" "$@"
fi
