#!/usr/bin/env bash
set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

info() {
    echo "==> $*"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

usage() {
    cat <<'EOF'
Usage:
  ./install-sh2eb-toolchain.sh /path/to/sh2eb-elf-*.tar.xz

Optional environment variables:
  INSTALL_PREFIX  (default: $HOME/.local/opt)
  BIN_DIR         (default: $HOME/.local/bin)
  STABLE_LINK     (default: sh2eb-elf-current)
  FORCE           (default: n)
  RUN_SMOKE       (default: y)
EOF
}

[ "${1:-}" = "-h" ] && usage && exit 0
[ "${1:-}" = "--help" ] && usage && exit 0
[ $# -ge 1 ] || die "missing archive path (use --help for usage)"

ARCHIVE_PATH="$1"
[ -f "${ARCHIVE_PATH}" ] || die "archive not found: ${ARCHIVE_PATH}"
case "${ARCHIVE_PATH}" in
    *.tar.xz) ;;
    *) die "archive must end in .tar.xz: ${ARCHIVE_PATH}" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="$(cd "$(dirname "${ARCHIVE_PATH}")" && pwd)"
ARCHIVE_NAME="$(basename "${ARCHIVE_PATH}")"
ARCHIVE_BASE="${ARCHIVE_NAME%.tar.xz}"
CHECKSUM_FILE="${ARCHIVE_NAME}.sha256"

INSTALL_PREFIX="${INSTALL_PREFIX:-${HOME}/.local/opt}"
BIN_DIR="${BIN_DIR:-${HOME}/.local/bin}"
STABLE_LINK="${STABLE_LINK:-sh2eb-elf-current}"
FORCE="${FORCE:-n}"
RUN_SMOKE="${RUN_SMOKE:-y}"

INSTALL_DIR="${INSTALL_PREFIX}/${ARCHIVE_BASE}"
STABLE_PATH="${INSTALL_PREFIX}/${STABLE_LINK}"

for cmd in tar shasum mktemp rm mkdir ln basename dirname stat grep cut find head mv; do
    require_cmd "${cmd}"
done

if [ -f "${ARCHIVE_DIR}/${CHECKSUM_FILE}" ]; then
    info "Verifying checksum"
    (
        cd "${ARCHIVE_DIR}"
        shasum -a 256 -c "${CHECKSUM_FILE}"
    )
else
    info "No checksum file found (${CHECKSUM_FILE}); skipping checksum verification"
fi

if [ -e "${INSTALL_DIR}" ]; then
    if [ "${FORCE}" = "y" ]; then
        info "Removing existing install dir ${INSTALL_DIR}"
        rm -rf "${INSTALL_DIR}"
    else
        die "install dir already exists: ${INSTALL_DIR} (set FORCE=y to replace)"
    fi
fi

TMP_DIR="$(mktemp -d "/tmp/sh2eb-install.XXXXXX")"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

info "Extracting ${ARCHIVE_NAME}"
tar -xJf "${ARCHIVE_PATH}" -C "${TMP_DIR}"

TOP_DIR="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "${TOP_DIR}" ] || die "archive did not contain a toolchain directory"
[ -x "${TOP_DIR}/bin/sh2eb-elf-gcc" ] || die "archive contents are missing bin/sh2eb-elf-gcc"

mkdir -p "${INSTALL_PREFIX}" "${BIN_DIR}"
mv "${TOP_DIR}" "${INSTALL_DIR}"

info "Updating stable symlink ${STABLE_PATH}"
ln -sfn "${INSTALL_DIR}" "${STABLE_PATH}"

info "Linking sh2eb-elf-* binaries into ${BIN_DIR}"
for tool in "${STABLE_PATH}/bin"/sh2eb-elf-*; do
    [ -f "${tool}" ] || continue
    ln -sfn "${tool}" "${BIN_DIR}/$(basename "${tool}")"
done

if [ "${RUN_SMOKE}" = "y" ]; then
    SMOKE_SCRIPT="${SCRIPT_DIR}/smoke-test-sh2eb.sh"
    if [ -x "${SMOKE_SCRIPT}" ]; then
        info "Running smoke test against installed toolchain"
        TOOLROOT="${STABLE_PATH}/bin" "${SMOKE_SCRIPT}"
    else
        info "No smoke-test-sh2eb.sh next to installer; running quick version check only"
        "${STABLE_PATH}/bin/sh2eb-elf-gcc" --version | head -n 1
        "${STABLE_PATH}/bin/sh2eb-elf-as" --version | head -n 1
        "${STABLE_PATH}/bin/sh2eb-elf-ld" --version | head -n 1
    fi
fi

echo "Install complete"
echo "  install dir: ${INSTALL_DIR}"
echo "  stable link: ${STABLE_PATH}"
echo "  tool bin: ${BIN_DIR}"
echo "  gcc: $("${STABLE_PATH}/bin/sh2eb-elf-gcc" --version | head -n 1)"

case ":${PATH}:" in
    *":${BIN_DIR}:"*)
        ;;
    *)
        echo "Add this to your shell profile:"
        echo "  export PATH=\"${BIN_DIR}:\$PATH\""
        ;;
esac
