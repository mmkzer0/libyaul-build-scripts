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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-/Volumes/ctng-case/x-tools/sh2eb-elf}"
DIST_DIR="${DIST_DIR:-${SCRIPT_DIR}/dist}"
RUN_SMOKE="${RUN_SMOKE:-y}"

[ -d "${TOOLCHAIN_ROOT}" ] || die "toolchain root does not exist: ${TOOLCHAIN_ROOT}"
[ -x "${TOOLCHAIN_ROOT}/bin/sh2eb-elf-gcc" ] || die "missing ${TOOLCHAIN_ROOT}/bin/sh2eb-elf-gcc"
[ -x "${TOOLCHAIN_ROOT}/bin/sh2eb-elf-as" ] || die "missing ${TOOLCHAIN_ROOT}/bin/sh2eb-elf-as"

for cmd in tar shasum date basename dirname awk sed git cp mkdir rm chmod; do
    require_cmd "${cmd}"
done

if [ "${RUN_SMOKE}" = "y" ]; then
    [ -x "${SCRIPT_DIR}/smoke-test-sh2eb.sh" ] || die "missing executable smoke test: ${SCRIPT_DIR}/smoke-test-sh2eb.sh"
    info "Running smoke test before packaging"
    TOOLROOT="${TOOLCHAIN_ROOT}/bin" "${SCRIPT_DIR}/smoke-test-sh2eb.sh"
fi

GCC_VERSION="$("${TOOLCHAIN_ROOT}/bin/sh2eb-elf-gcc" -dumpfullversion -dumpversion | head -n 1)"
[ -n "${GCC_VERSION}" ] || die "failed to resolve GCC version"
BINUTILS_VERSION="$("${TOOLCHAIN_ROOT}/bin/sh2eb-elf-as" --version | head -n 1 | awk '{print $NF}')"
[ -n "${BINUTILS_VERSION}" ] || die "failed to resolve binutils version"

ARCHIVE_BASE="sh2eb-elf-darwin-arm64-gcc${GCC_VERSION}-binutils${BINUTILS_VERSION}"
ARCHIVE_NAME="${ARCHIVE_BASE}.tar.xz"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
MANIFEST_PATH="${DIST_DIR}/${ARCHIVE_BASE}.manifest.txt"

mkdir -p "${DIST_DIR}"
rm -f "${ARCHIVE_PATH}" "${CHECKSUM_PATH}" "${MANIFEST_PATH}"

info "Creating archive ${ARCHIVE_PATH}"
tar -C "$(dirname "${TOOLCHAIN_ROOT}")" -cJf "${ARCHIVE_PATH}" "$(basename "${TOOLCHAIN_ROOT}")"

info "Writing checksum ${CHECKSUM_PATH}"
(
    cd "${DIST_DIR}"
    shasum -a 256 "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256"
)

GIT_COMMIT="$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || true)"
[ -n "${GIT_COMMIT}" ] || GIT_COMMIT="unknown"

cat > "${MANIFEST_PATH}" <<EOF
archive=${ARCHIVE_NAME}
sha256_file=$(basename "${CHECKSUM_PATH}")
toolchain_root=${TOOLCHAIN_ROOT}
gcc_version=${GCC_VERSION}
binutils_version=${BINUTILS_VERSION}
git_commit=${GIT_COMMIT}
built_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

info "Copying helper scripts to ${DIST_DIR}"
cp "${SCRIPT_DIR}/install-sh2eb-toolchain.sh" "${DIST_DIR}/install-sh2eb-toolchain.sh"
cp "${SCRIPT_DIR}/smoke-test-sh2eb.sh" "${DIST_DIR}/smoke-test-sh2eb.sh"
chmod +x "${DIST_DIR}/install-sh2eb-toolchain.sh" "${DIST_DIR}/smoke-test-sh2eb.sh"

echo "Package complete"
echo "  archive: ${ARCHIVE_PATH}"
echo "  checksum: ${CHECKSUM_PATH}"
echo "  manifest: ${MANIFEST_PATH}"
