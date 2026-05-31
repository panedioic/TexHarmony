#!/bin/bash
#
# build-ohos.sh
#

set -e

# ============================================================
# 配置区
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/texlive-source"
BUILD_DIR="${SCRIPT_DIR}/build-ohos"
HOST_BUILD_DIR="${SCRIPT_DIR}/build-host"

export OHOS_SDK="${OHOS_SDK:-/home/suwan/ohos-sdk/linux}"
export SYSROOT="${OHOS_SDK}/native/sysroot"
TOOLCHAIN_BIN="${OHOS_SDK}/native/llvm/bin"

LYCIUM_USR="${LYCIUM_USR:-/home/suwan/tpc_c_cplusplus/lycium/usr}"
ICU_PREFIX="${LYCIUM_USR}/icu/arm64-v8a"
FREETYPE_PREFIX="${LYCIUM_USR}/freetype2/arm64-v8a"
HARFBUZZ_PREFIX="${LYCIUM_USR}/harfbuzz/arm64-v8a"
GRAPHITE2_PREFIX="${LYCIUM_USR}/graphite2/arm64-v8a"
TECKIT_PREFIX="${LYCIUM_USR}/teckit/arm64-v8a"
ZLIB_PREFIX="${LYCIUM_USR}/zlib/arm64-v8a"
BZIP2_PREFIX="${LYCIUM_USR}/bzip2/arm64-v8a"
LIBPNG_PREFIX="${LYCIUM_USR}/libpng/arm64-v8a"
BROTLI_PREFIX="${LYCIUM_USR}/brotli/arm64-v8a"
FONTCONFIG_PREFIX="${LYCIUM_USR}/fontconfig/arm64-v8a"
EXPAT_PREFIX="${LYCIUM_USR}/expat/arm64-v8a"

# 合并所有依赖到编译参数
DEP_INCLUDES="-I${ICU_PREFIX}/include \
              -I${FREETYPE_PREFIX}/include/freetype2 \
              -I${HARFBUZZ_PREFIX}/include/harfbuzz \
              -I${GRAPHITE2_PREFIX}/include \
              -I${TECKIT_PREFIX}/include \
              -I${ZLIB_PREFIX}/include \
              -I${BZIP2_PREFIX}/include \
              -I${LIBPNG_PREFIX}/include \
              -I${BROTLI_PREFIX}/include \
              -I${FONTCONFIG_PREFIX}/include \
              -I${EXPAT_PREFIX}/include"
DEP_LIBDIRS="-L${ICU_PREFIX}/lib \
             -L${FREETYPE_PREFIX}/lib \
             -L${HARFBUZZ_PREFIX}/lib \
             -L${GRAPHITE2_PREFIX}/lib \
             -L${TECKIT_PREFIX}/lib \
             -L${ZLIB_PREFIX}/lib \
             -L${BZIP2_PREFIX}/lib \
             -L${LIBPNG_PREFIX}/lib \
             -L${BROTLI_PREFIX}/lib \
             -L${FONTCONFIG_PREFIX}/lib \
             -L${EXPAT_PREFIX}/lib"

export CC="${TOOLCHAIN_BIN}/clang --target=aarch64-linux-ohos --sysroot=${SYSROOT}"
export CXX="${TOOLCHAIN_BIN}/clang++ --target=aarch64-linux-ohos --sysroot=${SYSROOT}"
export AR="${TOOLCHAIN_BIN}/llvm-ar"
export RANLIB="${TOOLCHAIN_BIN}/llvm-ranlib"
export STRIP="${TOOLCHAIN_BIN}/llvm-strip"
export NM="${TOOLCHAIN_BIN}/llvm-nm"
export LD="${TOOLCHAIN_BIN}/ld.lld"

export CFLAGS="-O2 -fPIC ${DEP_INCLUDES}"
export CXXFLAGS="-O2 -fPIC ${DEP_INCLUDES}"
export LDFLAGS="${DEP_LIBDIRS}"
export PKG_CONFIG_PATH="${ICU_PREFIX}/lib/pkgconfig:${FREETYPE_PREFIX}/lib/pkgconfig:${HARFBUZZ_PREFIX}/lib/pkgconfig:${GRAPHITE2_PREFIX}/lib/pkgconfig:${TECKIT_PREFIX}/lib/pkgconfig:${ZLIB_PREFIX}/lib/pkgconfig"

JOBS="${JOBS:-$(nproc)}"

# ============================================================
# 工具函数
# ============================================================
log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

format_duration() {
    local total=$1
    local h=$((total / 3600))
    local m=$(((total % 3600) / 60))
    local s=$((total % 60))
    if [ $h -gt 0 ]; then
        printf "%dh %dm %ds" $h $m $s
    elif [ $m -gt 0 ]; then
        printf "%dm %ds" $m $s
    else
        printf "%ds" $s
    fi
}

step_start() {
    STEP_NAME="$1"
    STEP_START_TIME=$(date +%s)
    echo ""
    echo "============================================================"
    log "开始: ${STEP_NAME}"
    echo "============================================================"
}

step_end() {
    local end_time=$(date +%s)
    local duration=$((end_time - STEP_START_TIME))
    log "完成: ${STEP_NAME} (耗时 $(format_duration $duration))"
}

# ============================================================
# 主流程
# ============================================================
TOTAL_START=$(date +%s)

echo "============================================================"
echo "  TeX Live 鸿蒙交叉编译 (阶段1: 基础工具集)"
echo "============================================================"
echo "  源码目录:     ${SOURCE_DIR}"
echo "  构建目录:     ${BUILD_DIR}"
echo "  宿主目录:     ${HOST_BUILD_DIR}"
echo "  OHOS SDK:     ${OHOS_SDK}"
echo "  并行任务:     ${JOBS}"
echo "============================================================"

# ============================================================
# 第1步：前置检查
# ============================================================
step_start "前置检查"

if [ ! -d "${SOURCE_DIR}" ]; then
    log "错误: 源码目录不存在: ${SOURCE_DIR}"
    exit 1
fi

if [ ! -d "${OHOS_SDK}" ]; then
    log "错误: OHOS SDK 不存在: ${OHOS_SDK}"
    exit 1
fi

if [ ! -x "${TOOLCHAIN_BIN}/clang" ]; then
    log "错误: clang 不存在: ${TOOLCHAIN_BIN}/clang"
    exit 1
fi

HOST_TANGLE="${HOST_BUILD_DIR}/texk/web2c/tangle"
if [ ! -x "${HOST_TANGLE}" ]; then
    log "错误: 宿主工具 tangle 不存在: ${HOST_TANGLE}"
    log "请先完成宿主工具编译 (build-host 步骤)"
    exit 1
fi
log "宿主工具检查通过"

step_end

# ============================================================
# 第2步：清理并重建构建目录
# ============================================================
step_start "清理构建目录"

if [ -d "${BUILD_DIR}" ]; then
    log "构建目录已存在，删除中..."
    rm -rf "${BUILD_DIR}"
fi
mkdir -p "${BUILD_DIR}"
log "已创建构建目录: ${BUILD_DIR}"

step_end

# ============================================================
# 第3步：修补 config.sub 支持 ohos
# ============================================================
step_start "修补 config.sub 支持 aarch64-linux-ohos"

CRITICAL_PATHS=(
    "${SOURCE_DIR}/build-aux/config.sub"
    "${SOURCE_DIR}/libs"
    "${SOURCE_DIR}/texk"
)

CONFIG_SUB_FILES=""
for path in "${CRITICAL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CONFIG_SUB_FILES="${CONFIG_SUB_FILES} ${path}"
    elif [ -d "$path" ]; then
        CONFIG_SUB_FILES="${CONFIG_SUB_FILES} $(find "$path" -name "config.sub" -type f)"
    fi
done

PATCHED=0
SKIPPED=0
ALREADY_OK=0

for sub in $CONFIG_SUB_FILES; do
    if "${sub}" aarch64-linux-ohos >/dev/null 2>&1; then
        ALREADY_OK=$((ALREADY_OK + 1))
        continue
    fi

    if [ ! -f "${sub}.bak" ]; then
        cp "${sub}" "${sub}.bak"
    fi

    sed -i 's/linux-musl\*-/linux-musl*- | linux-ohos*-/g' "${sub}" 2>/dev/null
    sed -i 's/linux-musl\*/linux-musl* | linux-ohos*/g' "${sub}" 2>/dev/null

    if "${sub}" aarch64-linux-ohos >/dev/null 2>&1; then
        PATCHED=$((PATCHED + 1))
    else
        cp "${sub}.bak" "${sub}"
        SKIPPED=$((SKIPPED + 1))
    fi
done

log "结果: ${ALREADY_OK} 已支持, ${PATCHED} 已修补, ${SKIPPED} 跳过"

if ! "${SOURCE_DIR}/build-aux/config.sub" aarch64-linux-ohos >/dev/null 2>&1; then
    log "错误: 顶层 config.sub 仍不支持 ohos"
    exit 1
fi
log "顶层 config.sub 验证通过"

step_end

# ============================================================
# 第4步：运行 configure
# ============================================================
step_start "运行 configure"

cd "${BUILD_DIR}"

# 禁止 configure 调用宿主 pkg-config 来探测交叉编译库
# （中间更换过编译环境，导致部分依赖路径出错。这里直接显式指定。
# export PKG_CONFIG=/bin/false

"${SOURCE_DIR}/configure" \
    --host=aarch64-linux-ohos \
    --build=x86_64-linux-gnu \
    \
    --disable-native-texlive-build \
    --disable-shared \
    --without-x \
    \
    --enable-web2c \
    --enable-pdftex \
    --enable-bibtex \
    --enable-makeindex \
    --enable-dvipdfmx \
    --enable-mp \
    --enable-xetex \
    \
    --disable-luatex \
    --disable-luajittex \
    --disable-luahbtex \
    --disable-mf \
    --disable-mf-nowin \
    --disable-aleph \
    --disable-eptex \
    --disable-euptex \
    --disable-ptex \
    --disable-uptex \
    --disable-hitex \
    --disable-xdvipsk \
    \
    --with-system-icu \
    --with-system-zlib \
    --without-system-libpng \
    --with-system-freetype2 \
    --with-system-harfbuzz \
    --without-system-cairo \
    --without-system-gd \
    --without-system-pixman \
    --with-system-graphite2 \
    --without-system-zziplib \
    --without-system-mpfr \
    --without-system-gmp \
    --without-system-potrace \
    --with-system-teckit \
    --without-system-paper \
    \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    NM="$NM" \
    CFLAGS="$CFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    \
    ZLIB_CFLAGS="-I${ZLIB_PREFIX}/include" \
    ZLIB_LIBS="${ZLIB_PREFIX}/lib/libz.a" \
    \
    ICU_CFLAGS="-I${ICU_PREFIX}/include" \
    ICU_CPPFLAGS="-I${ICU_PREFIX}/include" \
    ICU_LIBS="${ICU_PREFIX}/lib/libicui18n.a ${ICU_PREFIX}/lib/libicuuc.a ${ICU_PREFIX}/lib/libicudata.a -lc++ -lm" \
    \
    FREETYPE2_CFLAGS="-I${FREETYPE_PREFIX}/include/freetype2" \
    FREETYPE2_LIBS="${FREETYPE_PREFIX}/lib/libfreetype.a \
                    ${ZLIB_PREFIX}/lib/libz.a \
                    ${BZIP2_PREFIX}/lib/libbz2.a \
                    ${LIBPNG_PREFIX}/lib/libpng16.a \
                    ${BROTLI_PREFIX}/lib/libbrotlidec.a \
                    ${BROTLI_PREFIX}/lib/libbrotlicommon.a \
                    -lm" \
    \
    GRAPHITE2_CFLAGS="-I${GRAPHITE2_PREFIX}/include" \
    GRAPHITE2_LIBS="${GRAPHITE2_PREFIX}/lib/libgraphite2.a -lc++ -lm" \
    \
    HARFBUZZ_CFLAGS="-I${HARFBUZZ_PREFIX}/include/harfbuzz" \
    HARFBUZZ_LIBS="${HARFBUZZ_PREFIX}/lib/libharfbuzz.a \
                   ${FREETYPE_PREFIX}/lib/libfreetype.a \
                   ${GRAPHITE2_PREFIX}/lib/libgraphite2.a \
                   ${ICU_PREFIX}/lib/libicuuc.a \
                   ${ICU_PREFIX}/lib/libicudata.a \
                   ${ZLIB_PREFIX}/lib/libz.a \
                   ${BZIP2_PREFIX}/lib/libbz2.a \
                   ${LIBPNG_PREFIX}/lib/libpng16.a \
                   ${BROTLI_PREFIX}/lib/libbrotlidec.a \
                   ${BROTLI_PREFIX}/lib/libbrotlicommon.a \
                   -lc++ -lm" \
    \
    TECKIT_CFLAGS="-I${TECKIT_PREFIX}/include" \
    TECKIT_LIBS="${TECKIT_PREFIX}/lib/libTECkit.a \
                 ${ZLIB_PREFIX}/lib/libz.a \
                 -lc++ -lm" \
    \
    FONTCONFIG_CFLAGS="-I${FONTCONFIG_PREFIX}/include" \
    FONTCONFIG_LIBS="${FONTCONFIG_PREFIX}/lib/libfontconfig.a \
                     ${EXPAT_PREFIX}/lib/libexpat.a \
                     ${FREETYPE_PREFIX}/lib/libfreetype.a \
                     ${ZLIB_PREFIX}/lib/libz.a \
                     ${BZIP2_PREFIX}/lib/libbz2.a \
                     ${LIBPNG_PREFIX}/lib/libpng16.a \
                     ${BROTLI_PREFIX}/lib/libbrotlidec.a \
                     ${BROTLI_PREFIX}/lib/libbrotlicommon.a \
                     -lm" \
    \
    EXPAT_CFLAGS="-I${EXPAT_PREFIX}/include" \
    EXPAT_LIBS="${EXPAT_PREFIX}/lib/libexpat.a" \
    \
    2>&1 | tee configure-ohos.log

step_end

# ============================================================
# 第4.5步：打补丁（修复鸿蒙兼容性问题）
# ============================================================
step_start "打补丁"

# --- 修复 dvipdfmx: 鸿蒙没有 getpass() 函数 ---
DVIPDFMX_SRC="${SOURCE_DIR}/texk/dvipdfm-x/dvipdfmx.c"
if [ -f "${DVIPDFMX_SRC}" ] && grep -q "getpass" "${DVIPDFMX_SRC}"; then
    # 创建兼容头文件
    COMPAT_HEADER="${SOURCE_DIR}/texk/dvipdfm-x/ohos_compat.h"
    cat > "${COMPAT_HEADER}" << 'HEADER'
#ifndef OHOS_COMPAT_H
#define OHOS_COMPAT_H

#include <stdio.h>
#include <string.h>

#if !defined(HAVE_GETPASS) && !defined(__GLIBC__)
static inline char *getpass(const char *prompt) {
    static char buf[256];
    fprintf(stderr, "%s", prompt);
    fflush(stderr);
    if (fgets(buf, sizeof(buf), stdin)) {
        size_t len = strlen(buf);
        if (len > 0 && buf[len-1] == '\n') buf[len-1] = '\0';
        return buf;
    }
    buf[0] = '\0';
    return buf;
}
#endif

#endif
HEADER

    # 在 dvipdfmx.c 的 include 区域加入兼容头文件
    if ! grep -q "ohos_compat.h" "${DVIPDFMX_SRC}"; then
        # 在 #ifdef HAVE_CONFIG_H 块之后插入
        sed -i '/#include.*"dvipdfmx\.h"\|#include.*"system\.h"/{
            a #include "ohos_compat.h"
            }' "${DVIPDFMX_SRC}"
        # 如果上面没匹配到，尝试在文件前部插入
        if ! grep -q "ohos_compat.h" "${DVIPDFMX_SRC}"; then
            sed -i '1i #include "ohos_compat.h"' "${DVIPDFMX_SRC}"
        fi
    fi

    log "已修补: dvipdfmx.c (getpass 兼容层)"
    log "验证: $(grep -c 'ohos_compat' "${DVIPDFMX_SRC}") 处引用"
fi

# --- 修复 xdvipsk: 禁用 Windows 特有链接（备选方案） ---
# xdvipsk 在 configure 中已通过 --disable-xdvipsk 禁用
# 如果仍然被编译，在这里用 stub Makefile 阻止
XDVIPSK_DIR="${BUILD_DIR}/texk/xdvipsk"
if [ -d "${XDVIPSK_DIR}" ]; then
    log "注意: xdvipsk 目录存在，将在 configure 后检查是否需要禁用"
fi

step_end

# ============================================================
# 第5步：编译
# ============================================================
step_start "编译 (make -j${JOBS})"

cd "${BUILD_DIR}"

make -j"${JOBS}" \
    TANGLE="${HOST_BUILD_DIR}/texk/web2c/tangle" \
    CTANGLE="${HOST_BUILD_DIR}/texk/web2c/ctangle" \
    OTANGLE="${HOST_BUILD_DIR}/texk/web2c/otangle" \
    TIE="${HOST_BUILD_DIR}/texk/web2c/tie" \
    2>&1 | tee make-ohos.log

step_end

# ============================================================
# 第6步：验证产物
# ============================================================
step_start "验证并收集产物"

DIST_DIR="${SCRIPT_DIR}/dist-ohos"
mkdir -p "${DIST_DIR}/bin"

# 清理旧的 dist
rm -f "${DIST_DIR}/bin/"* 2>/dev/null

log "扫描所有 ARM64 可执行文件..."

COUNT=0
TOTAL_SIZE=0

# 在 texk 和 utils 下查找所有可执行文件
find "${BUILD_DIR}/texk" "${BUILD_DIR}/utils" -type f -executable 2>/dev/null | while read f; do
    if file "$f" 2>/dev/null | grep -q "ARM aarch64"; then
        name=$(basename "$f")
        # 跳过 .libs 内部的副本
        case "$f" in
            */\.libs/*) continue ;;
        esac
        cp "$f" "${DIST_DIR}/bin/${name}"
        ${STRIP} "${DIST_DIR}/bin/${name}" 2>/dev/null || true
    fi
done

# 创建 dvipdfmx -> xdvipdfmx 副本（同一程序通过 argv[0] 切换行为）
if [ -f "${DIST_DIR}/bin/xdvipdfmx" ] && [ ! -f "${DIST_DIR}/bin/dvipdfmx" ]; then
    cp "${DIST_DIR}/bin/xdvipdfmx" "${DIST_DIR}/bin/dvipdfmx"
fi

BIN_COUNT=$(ls "${DIST_DIR}/bin/" | wc -l)
TOTAL_SIZE=$(du -sh "${DIST_DIR}/bin/" | awk '{print $1}')

log "收集完成: ${BIN_COUNT} 个文件, 总大小 ${TOTAL_SIZE}"

# 检查关键程序
echo ""
log "关键程序检查:"
for bin in pdftex tex bibtex makeindex dvipdfmx dvips mpost kpsewhich; do
    if [ -f "${DIST_DIR}/bin/${bin}" ]; then
        SIZE=$(ls -lh "${DIST_DIR}/bin/${bin}" | awk '{print $5}')
        log "  ✓ ${bin} (${SIZE})"
    else
        log "  ✗ ${bin} 缺失"
    fi
done

# 架构验证
FIRST_BIN=$(ls "${DIST_DIR}/bin/" | head -1)
if [ -n "${FIRST_BIN}" ]; then
    log "架构验证 (${FIRST_BIN}):"
    file "${DIST_DIR}/bin/${FIRST_BIN}" | sed 's/^/    /'
fi

step_end

# ============================================================
# 总结
# ============================================================
TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

echo ""
echo "============================================================"
log "全部完成 (总耗时 $(format_duration $TOTAL_DURATION))"
echo "============================================================"
echo ""
echo "产物目录: ${DIST_DIR}/bin/"
ls -lh "${DIST_DIR}/bin/"
echo ""
echo "下一步: 运行 pack-texmf.sh 打包资源"
echo "============================================================"