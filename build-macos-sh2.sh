#!/usr/bin/env bash
set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

info() {
    echo "==> $*"
}

escape_sed_repl() {
    printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

resolve_tool() {
    local var_name="$1"
    shift
    local value="${!var_name:-}"
    local candidate=""

    if [ -n "${value}" ]; then
        if [[ "${value}" == */* ]]; then
            [ -x "${value}" ] || die "${var_name} path is not executable: ${value}"
            printf '%s\n' "${value}"
            return 0
        fi

        candidate="$(command -v "${value}" || true)"
        [ -n "${candidate}" ] || die "${var_name} command not found in PATH: ${value}"
        printf '%s\n' "${candidate}"
        return 0
    fi

    for candidate in "$@"; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            command -v "${candidate}"
            return 0
        fi
    done

    die "could not resolve ${var_name}; tried: $*"
}

assert_case_sensitive_dir() {
    local dir="$1"
    local probe

    [ -d "${dir}" ] || die "CASE_ROOT does not exist: ${dir}. Create and mount a case-sensitive APFS volume first."

    probe="${dir}/.ctng-case-check.$$"
    mkdir -p "${probe}"
    touch "${probe}/foo"
    if [ -e "${probe}/FOO" ]; then
        rm -rf "${probe}"
        die "CASE_ROOT is not case-sensitive: ${dir}"
    fi
    rm -rf "${probe}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_ROOT="${CASE_ROOT:-/Volumes/ctng-case}"
CONFIG_FILE="configs/sh2eb-elf/native-darwin-aarch64.config"
CT_WORK_DIR="${CASE_ROOT}/.build"
CT_PREFIX="${CASE_ROOT}/x-tools"
CT_HOST_EXTRA_CFLAGS="${CT_HOST_EXTRA_CFLAGS:--Wno-error=incompatible-function-pointer-types -UTARGET_OS_MAC}"

[ -f "${SCRIPT_DIR}/${CONFIG_FILE}" ] || die "missing config file: ${CONFIG_FILE}"
[ -d "${SCRIPT_DIR}/crosstool-ng" ] || die "missing crosstool-ng submodule directory"

BREW_PREFIX="${HOMEBREW_PREFIX:-}"
if [ -z "${BREW_PREFIX}" ]; then
    BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
fi
[ -n "${BREW_PREFIX}" ] || BREW_PREFIX="/opt/homebrew"

for gnubin in \
    "${BREW_PREFIX}/opt/make/libexec/gnubin" \
    "${BREW_PREFIX}/opt/coreutils/libexec/gnubin" \
    "${BREW_PREFIX}/opt/gnu-sed/libexec/gnubin" \
    "${BREW_PREFIX}/opt/gnu-tar/libexec/gnubin" \
    "${BREW_PREFIX}/opt/grep/libexec/gnubin" \
    "${BREW_PREFIX}/opt/gawk/libexec/gnubin"
do
    [ -d "${gnubin}" ] && PATH="${gnubin}:${PATH}"
done
export PATH

for cmd in \
    git \
    gawk \
    gmake \
    gsed \
    gtar \
    help2man \
    makeinfo \
    flex \
    bison \
    wget \
    curl \
    xz \
    lzip \
    meson \
    ninja \
    patch \
    bash \
    unzip \
    file \
    which \
    readlink \
    cut \
    gzip \
    bzip2 \
    tar \
    gcc \
    g++
do
    require_cmd "${cmd}"
done

export AWK="$(resolve_tool AWK gawk)"
export MAKE="$(resolve_tool MAKE gmake)"
export OBJCOPY="$(resolve_tool OBJCOPY gobjcopy llvm-objcopy)"
export OBJDUMP="$(resolve_tool OBJDUMP gobjdump llvm-objdump)"
export READELF="$(resolve_tool READELF greadelf llvm-readelf)"

info "Using CASE_ROOT=${CASE_ROOT}"
info "Using CT_HOST_EXTRA_CFLAGS=${CT_HOST_EXTRA_CFLAGS}"
assert_case_sensitive_dir "${CASE_ROOT}"
mkdir -p "${CT_WORK_DIR}" "${CT_PREFIX}"

cd "${SCRIPT_DIR}"

info "Initializing/updating crosstool-ng submodule"
git submodule init
git submodule update

info "Bootstrapping and building crosstool-ng"
(
    cd crosstool-ng
    ./bootstrap
    ./configure --enable-local
    "${MAKE}"
)

info "Selecting config ${CONFIG_FILE}"
cp "${CONFIG_FILE}" .config

WORK_DIR_ESCAPED="$(escape_sed_repl "${CT_WORK_DIR}")"
PREFIX_DIR_ESCAPED="$(escape_sed_repl "${CT_PREFIX}/sh2eb-elf")"
HOST_CFLAGS_ESCAPED="$(escape_sed_repl "${CT_HOST_EXTRA_CFLAGS}")"
gsed -i \
    -e "s|^CT_WORK_DIR=.*$|CT_WORK_DIR=\"${WORK_DIR_ESCAPED}\"|" \
    -e "s|^CT_PREFIX_DIR=.*$|CT_PREFIX_DIR=\"${PREFIX_DIR_ESCAPED}\"|" \
    -e "s|^CT_EXTRA_CFLAGS_FOR_HOST=.*$|CT_EXTRA_CFLAGS_FOR_HOST=\"${HOST_CFLAGS_ESCAPED}\"|" \
    .config

info "Building sh2eb-elf toolchain"
crosstool-ng/ct-ng build

info "Done. Toolchain binaries should be under: ${CT_PREFIX}/sh2eb-elf/bin"
