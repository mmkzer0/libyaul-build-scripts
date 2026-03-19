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

extract_body() {
    local asm_file="$1"
    local symbol="$2"
    local out_file="$3"

    awk -v sym="${symbol}" '
        $0 ~ ("^" sym "$") { in_body = 1; next }
        in_body && $0 ~ /^	.size[[:space:]]+/ { exit }
        in_body { print }
    ' "${asm_file}" > "${out_file}"

    [ -s "${out_file}" ] || die "failed to extract function body for ${symbol}"
}

assert_not_pr122948_bad_lowering() {
    local body_file="$1"
    local name="$2"
    local has_sett="n"
    local has_subc_r4_r1="n"
    local has_cmp_hi="n"
    local has_add_1_r4="n"

    grep -Eq '^[[:space:]]*sett([[:space:]]|$)' "${body_file}" && has_sett="y" || true
    grep -Eq '^[[:space:]]*subc[[:space:]]+r4,r1([[:space:]]|$)' "${body_file}" && has_subc_r4_r1="y" || true
    grep -Eq '^[[:space:]]*cmp/hi[[:space:]]+' "${body_file}" && has_cmp_hi="y" || true
    grep -Eq '^[[:space:]]*add[[:space:]]+#1,r4([[:space:]]|$)' "${body_file}" && has_add_1_r4="y" || true

    if [ "${has_sett}" = "y" ] && [ "${has_subc_r4_r1}" = "y" ] && [ "${has_cmp_hi}" = "n" ] && [ "${has_add_1_r4}" = "n" ]; then
        echo "Detected likely PR122948 bad lowering in ${name}:"
        sed -n '1,120p' "${body_file}" >&2
        die "PR122948 regression detected in ${name}"
    fi
}

TOOLROOT="${TOOLROOT:-/Volumes/ctng-case/x-tools/sh2eb-elf/bin}"
CC="${TOOLROOT}/sh2eb-elf-gcc"

[ -x "${CC}" ] || die "missing compiler: ${CC}"

for cmd in awk grep mktemp sed; do
    require_cmd "${cmd}"
done

if [ -n "${SMOKE_DIR:-}" ]; then
    mkdir -p "${SMOKE_DIR}"
else
    SMOKE_DIR="$(mktemp -d "/tmp/sh2eb-regressions.XXXXXX")"
fi

ASM_FILE="${SMOKE_DIR}/pr122948.s"
C_FILE="${SMOKE_DIR}/pr122948.c"

info "Using TOOLROOT=${TOOLROOT}"
info "Using SMOKE_DIR=${SMOKE_DIR}"

cat > "${C_FILE}" <<'EOF'
__attribute__ ((noipa,noinline,noclone)) unsigned int
pr122948_cmp(unsigned int a, unsigned int b) {
  return (b - a - 1) > b;
}

__attribute__ ((noipa,noinline,noclone)) unsigned int
pr122948_if(unsigned int a, unsigned int b) {
  if (b - a - 1 <= b)
    a = 0;
  return a;
}
EOF

info "Compiling PR122948 regression inputs"
"${CC}" -m2 -O2 -S "${C_FILE}" -o "${ASM_FILE}"

extract_body "${ASM_FILE}" "_pr122948_cmp:" "${SMOKE_DIR}/pr122948_cmp.body.s"
extract_body "${ASM_FILE}" "_pr122948_if:" "${SMOKE_DIR}/pr122948_if.body.s"

assert_not_pr122948_bad_lowering "${SMOKE_DIR}/pr122948_cmp.body.s" "pr122948_cmp"
assert_not_pr122948_bad_lowering "${SMOKE_DIR}/pr122948_if.body.s" "pr122948_if"

echo "Regression smoke passed"
echo "  TOOLROOT: ${TOOLROOT}"
echo "  ASM: ${ASM_FILE}"
