Yaul build scripts
===

Build scripts for Yaul.

## List of configurations

### SH-2

| Platform        | Configuration file                         | Build type | Working? |
|-----------------|--------------------------------------------|------------|----------|
| Linux           | `sh2eb-elf/native-linux.config`            | Native     | Yes      |
| macOS (arm64)   | `sh2eb-elf/native-darwin-aarch64.config`   | Native     | WIP      |
| Linux           | `sh2eb-elf/host-i686-pc-linux-gnu.config`  | Canadian   | Yes      |
| Windows (MinGW) | `sh2eb-elf/host-x86_64-w64-mingw32.config` | Canadian   | Yes      |
| Windows (WSL2)  | `sh2eb-elf/host-x86_64-w64-mingw32.config` | Canadian   | Yes      |

### M68k

_Currently unavailable._

## Building

### Build requirements

<details>
  <summary>Debian based and WSL2 Ubuntu</summary>

```
apt install \
  texinfo \
  help2man \
  curl \
  lzip \
  meson \
  ninja-build \
  gawk \
  libtool-bin \
  ncurses-dev \
  flex \
  bison
```

</details>

<details>
  <summary>FreeBSD</summary>

```
pkg install \
  autotools \
  gsed \
  texinfo \
  help2man \
  gawk \
  lzma \
  wget \
  bison \
  coreutils \
  gmake \
  unix2dos \
  patch \
  gcc \
  lzip
```

</details>

<details>
  <summary>macOS (Homebrew, Apple Silicon)</summary>

```
brew install \
  make \
  coreutils \
  gnu-sed \
  gnu-tar \
  grep \
  gawk \
  binutils \
  help2man \
  flex \
  bison \
  texinfo \
  wget \
  curl \
  xz \
  lzip \
  meson \
  ninja
```

Manual environment setup (the wrapper script below applies this automatically):

```
export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
export PATH="${HOMEBREW_PREFIX}/opt/make/libexec/gnubin:${HOMEBREW_PREFIX}/opt/coreutils/libexec/gnubin:${HOMEBREW_PREFIX}/opt/gnu-sed/libexec/gnubin:${HOMEBREW_PREFIX}/opt/gnu-tar/libexec/gnubin:${HOMEBREW_PREFIX}/opt/grep/libexec/gnubin:${HOMEBREW_PREFIX}/opt/gawk/libexec/gnubin:${PATH}"
export AWK="$(command -v gawk)"
export MAKE="$(command -v gmake)"
export OBJCOPY="${OBJCOPY:-$(command -v gobjcopy || command -v llvm-objcopy)}"
export OBJDUMP="${OBJDUMP:-$(command -v gobjdump || command -v llvm-objdump)}"
export READELF="${READELF:-$(command -v greadelf || command -v llvm-readelf)}"
```

</details>

### Case-sensitive file system requirement (macOS)

`crosstool-ng` aborts if either the work directory or install prefix is on a case-insensitive file system.  
The macOS wrapper defaults to `CASE_ROOT=/Volumes/ctng-case` and sets:

- `CT_WORK_DIR="$CASE_ROOT/.build"`
- `CT_PREFIX="$CASE_ROOT/x-tools"`

Create and mount a case-sensitive sparse image (recommended):

```
mkdir -p "$HOME/.cache/ctng"

hdiutil create -size 30g -type SPARSE \
  -fs 'Case-sensitive APFS' \
  -volname ctng-case \
  "$HOME/.cache/ctng/ctng-case.sparseimage"

hdiutil attach \
  "$HOME/.cache/ctng/ctng-case.sparseimage" \
  -mountpoint /Volumes/ctng-case
```

Quick case-sensitivity check:

```
mkdir -p /Volumes/ctng-case/.case-check
touch /Volumes/ctng-case/.case-check/foo
test ! -e /Volumes/ctng-case/.case-check/FOO && echo "case-sensitive: ok"
rm -rf /Volumes/ctng-case/.case-check
```

### Build `crosstool-ng`

<details>
  <summary>Linux</summary>

```
git submodule init
git submodule update

cd crosstool-ng
./bootstrap
./configure --enable-local
make
```

</details>

<details>
  <summary>Windows (WSL2)</summary>

```
git submodule init
git submodule update

cd crosstool-ng
./bootstrap
./configure --enable-local
make
sudo bash -c "echo 0 > /proc/sys/fs/binfmt_misc/status"
```

</details>

<details>
  <summary>FreeBSD</summary>

```
git submodule init
git submodule update

cd crosstool-ng
./bootstrap

MAKE=/usr/local/bin/gmake \
INSTALL=/usr/local/bin/ginstall \
SED=/usr/local/bin/gsed \
PATCH=/usr/local/bin/gpatch \
./configure --enable-local

gmake
```

</details>

<details>
  <summary>macOS (Apple Silicon)</summary>

```
git submodule init
git submodule update

cd crosstool-ng
./bootstrap

AWK="$(command -v gawk)" \
MAKE="$(command -v gmake)" \
OBJCOPY="${OBJCOPY:-$(command -v gobjcopy || command -v llvm-objcopy)}" \
OBJDUMP="${OBJDUMP:-$(command -v gobjdump || command -v llvm-objdump)}" \
READELF="${READELF:-$(command -v greadelf || command -v llvm-readelf)}" \
./configure --enable-local

gmake
```

</details>

### Build the `sh2eb-elf-` tool-chain

```
cd ..
cp configs/sh2eb-elf/<file>.config .config
crosstool-ng/ct-ng build
```

### Build the `sh2eb-elf-` tool-chain (macOS fast-path)

```
CASE_ROOT=/Volumes/ctng-case ./build-macos-sh2.sh
```

Optional overrides:

```
CASE_ROOT=/Volumes/ctng-case \
CT_HOST_EXTRA_CFLAGS="-Wno-error=incompatible-function-pointer-types -UTARGET_OS_MAC" \
OBJCOPY=/path/to/llvm-objcopy \
OBJDUMP=/path/to/llvm-objdump \
READELF=/path/to/llvm-readelf \
./build-macos-sh2.sh
```

### Smoke test (built toolchain)

```
TOOLROOT=/Volumes/ctng-case/x-tools/sh2eb-elf/bin \
./smoke-test-sh2eb.sh
```

### Package toolchain bundle

```
./package-sh2eb-toolchain.sh
```

Outputs are created in `dist/`:

- `sh2eb-elf-darwin-arm64-gcc<...>-binutils<...>.tar.xz`
- `...tar.xz.sha256`
- `...manifest.txt`
- `install-sh2eb-toolchain.sh` (copied next to the bundle)
- `smoke-test-sh2eb.sh` (copied next to the bundle)

### Install from bundle (user-local, recommended)

`/usr/bin` is not a valid install target on macOS (SIP-protected).  
Use `~/.local` by default:

```
ARCHIVE="$(ls -t ./dist/sh2eb-elf-darwin-arm64-gcc*-binutils*.tar.xz | head -n 1)"
./dist/install-sh2eb-toolchain.sh "${ARCHIVE}"
```

Default install locations:

- Versioned install: `~/.local/opt/sh2eb-elf-darwin-arm64-gcc<...>-binutils<...>`
- Stable symlink: `~/.local/opt/sh2eb-elf-current`
- Command links: `~/.local/bin/sh2eb-elf-*`

If needed:

```
export PATH="$HOME/.local/bin:$PATH"
```

Post-install verification:

```
TOOLROOT="$HOME/.local/opt/sh2eb-elf-current/bin" \
./smoke-test-sh2eb.sh
```

### Unmount and delete the case-sensitive build image

After install + smoke test passes from `~/.local/opt/sh2eb-elf-current/bin`:

```
hdiutil detach /Volumes/ctng-case
rm "$HOME/.cache/ctng/ctng-case.sparseimage"
```
