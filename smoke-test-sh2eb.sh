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

assert_match() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    if ! grep -E -q "$pattern" "$file"; then
        die "validation failed: ${description}"
    fi
}

TOOLROOT="${TOOLROOT:-/Volumes/ctng-case/x-tools/sh2eb-elf/bin}"

if [ -n "${SMOKE_DIR:-}" ]; then
    mkdir -p "${SMOKE_DIR}"
else
    SMOKE_DIR="$(mktemp -d "/tmp/sh2eb-smoke.XXXXXX")"
fi

CC="${TOOLROOT}/sh2eb-elf-gcc"
AS="${TOOLROOT}/sh2eb-elf-as"
LD="${TOOLROOT}/sh2eb-elf-ld"
READELF="${TOOLROOT}/sh2eb-elf-readelf"
OBJDUMP="${TOOLROOT}/sh2eb-elf-objdump"

[ -x "${CC}" ] || die "missing compiler: ${CC}"
[ -x "${AS}" ] || die "missing assembler: ${AS}"
[ -x "${LD}" ] || die "missing linker: ${LD}"
[ -x "${READELF}" ] || die "missing readelf: ${READELF}"
[ -x "${OBJDUMP}" ] || die "missing objdump: ${OBJDUMP}"

for cmd in grep mktemp cat stat; do
    require_cmd "${cmd}"
done

info "Using TOOLROOT=${TOOLROOT}"
info "Using SMOKE_DIR=${SMOKE_DIR}"

cat > "${SMOKE_DIR}/add_m2.c" <<'EOF'
int add_m2(int a, int b) {
    return a + b;
}
EOF

cat > "${SMOKE_DIR}/start.s" <<'EOF'
    .section .text
    .global _start
_start:
    mov #0, r0
1:
    bra 1b
    nop
EOF

info "Compiling and assembling smoke test inputs"
"${CC}" -c -m2 -Os -ffreestanding -fno-builtin "${SMOKE_DIR}/add_m2.c" -o "${SMOKE_DIR}/add_m2.o"
"${AS}" --isa=sh2 "${SMOKE_DIR}/start.s" -o "${SMOKE_DIR}/start.o"

info "Linking smoke test executable"
"${LD}" -nostdlib -e _start -Ttext 0x06004000 -o "${SMOKE_DIR}/smoke_m2.elf" "${SMOKE_DIR}/start.o" "${SMOKE_DIR}/add_m2.o"

"${READELF}" -h "${SMOKE_DIR}/smoke_m2.elf" > "${SMOKE_DIR}/readelf_header.txt"
"${READELF}" -s "${SMOKE_DIR}/smoke_m2.elf" > "${SMOKE_DIR}/readelf_symbols_elf.txt"
"${READELF}" -s "${SMOKE_DIR}/add_m2.o" > "${SMOKE_DIR}/readelf_symbols_obj.txt"
"${OBJDUMP}" -d "${SMOKE_DIR}/add_m2.o" > "${SMOKE_DIR}/objdump_add_m2.txt"

assert_match "${SMOKE_DIR}/readelf_header.txt" "Machine:[[:space:]]+Renesas / SuperH SH" "ELF machine should be SuperH"
assert_match "${SMOKE_DIR}/readelf_header.txt" "Flags:[[:space:]]+0x[0-9a-f]+, sh2" "ELF flags should include sh2"
assert_match "${SMOKE_DIR}/readelf_symbols_elf.txt" "[[:space:]]_start$" "linked ELF should contain _start"
assert_match "${SMOKE_DIR}/readelf_symbols_obj.txt" "[[:space:]]_add_m2$" "compiled object should contain _add_m2"
assert_match "${SMOKE_DIR}/objdump_add_m2.txt" "<_add_m2>:" "objdump should decode _add_m2"

echo "Smoke test passed"
echo "  TOOLROOT: ${TOOLROOT}"
echo "  ELF: ${SMOKE_DIR}/smoke_m2.elf"
echo "  ELF size: $(stat -f %z "${SMOKE_DIR}/smoke_m2.elf") bytes"
