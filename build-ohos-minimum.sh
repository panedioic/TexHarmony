#!/bin/bash
#
# TeX Live 交叉编译脚本（鸿蒙 ARM64）
# 用法: ./build-ohos.sh
#

set -e

# ============================================================
# 配置区
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/texlive-source"
BUILD_DIR="${SCRIPT_DIR}/build-ohos"
HOST_BUILD_DIR="${SCRIPT_DIR}/build-host"

# 鸿蒙 SDK 配置
export OHOS_SDK="${OHOS_SDK:-/home/suwan/ohos-sdk/linux}"
export SYSROOT="${OHOS_SDK}/native/sysroot"
TOOLCHAIN_BIN="${OHOS_SDK}/native/llvm/bin"

# lycium 预编译库
LYCIUM_USR="${LYCIUM_USR:-/home/suwan/tpc_c_cplusplus/lycium/usr}"
ICU_PREFIX="${LYCIUM_USR}/icu/arm64-v8a"

# 交叉编译工具链
export CC="${TOOLCHAIN_BIN}/clang --target=aarch64-linux-ohos --sysroot=${SYSROOT}"
export CXX="${TOOLCHAIN_BIN}/clang++ --target=aarch64-linux-ohos --sysroot=${SYSROOT}"
export AR="${TOOLCHAIN_BIN}/llvm-ar"
export RANLIB="${TOOLCHAIN_BIN}/llvm-ranlib"
export STRIP="${TOOLCHAIN_BIN}/llvm-strip"
export NM="${TOOLCHAIN_BIN}/llvm-nm"
export LD="${TOOLCHAIN_BIN}/ld.lld"
export CFLAGS="-O2 -fPIC -I${ICU_PREFIX}/include"
export CXXFLAGS="-O2 -fPIC -I${ICU_PREFIX}/include"
export LDFLAGS="-L${ICU_PREFIX}/lib"
export PKG_CONFIG_PATH="${ICU_PREFIX}/lib/pkgconfig"

# 并行编译数
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
echo "  TeX Live 鸿蒙交叉编译"
echo "============================================================"
echo "  源码目录:     ${SOURCE_DIR}"
echo "  构建目录:     ${BUILD_DIR}"
echo "  宿主目录:     ${HOST_BUILD_DIR}"
echo "  OHOS SDK:     ${OHOS_SDK}"
echo "  ICU 路径:     ${ICU_PREFIX}"
echo "  并行任务:     ${JOBS}"
echo "============================================================"

# ------------------------------------------------------------
# 前置检查
# ------------------------------------------------------------
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

# 检查宿主工具
HOST_TANGLE="${HOST_BUILD_DIR}/texk/web2c/tangle"
if [ ! -x "${HOST_TANGLE}" ]; then
    log "错误: 宿主工具 tangle 不存在: ${HOST_TANGLE}"
    log "请先完成宿主工具编译 (build-host 步骤)"
    exit 1
fi
log "宿主工具检查通过"

# 检查 ICU
if [ ! -f "${ICU_PREFIX}/include/unicode/uversion.h" ]; then
    log "错误: ICU 头文件不存在: ${ICU_PREFIX}/include/unicode/uversion.h"
    exit 1
fi
if [ ! -f "${ICU_PREFIX}/lib/libicuuc.so" ] && [ ! -f "${ICU_PREFIX}/lib/libicuuc.a" ]; then
    log "错误: ICU 库文件不存在"
    exit 1
fi
log "ICU 检查通过: $(ls ${ICU_PREFIX}/lib/libicuuc.* | head -1)"

step_end

# ------------------------------------------------------------
# 清理并重建构建目录
# ------------------------------------------------------------
step_start "清理构建目录"

if [ -d "${BUILD_DIR}" ]; then
    log "构建目录已存在，删除中..."
    rm -rf "${BUILD_DIR}"
fi
mkdir -p "${BUILD_DIR}"
log "已创建构建目录: ${BUILD_DIR}"

step_end

# ------------------------------------------------------------
# 修补 config.sub 支持 ohos
# ------------------------------------------------------------
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
        log "跳过 (非关键): ${sub}"
    fi
done

log "结果: ${ALREADY_OK} 已支持, ${PATCHED} 已修补, ${SKIPPED} 跳过"

if ! "${SOURCE_DIR}/build-aux/config.sub" aarch64-linux-ohos >/dev/null 2>&1; then
    log "错误: 顶层 config.sub 仍不支持 ohos"
    exit 1
fi
log "顶层 config.sub 验证通过"

step_end

# ------------------------------------------------------------
# 运行 configure
# ------------------------------------------------------------
step_start "运行 configure (交叉编译配置)"

cd "${BUILD_DIR}"

"${SOURCE_DIR}/configure" \
    --host=aarch64-linux-ohos \
    --build=x86_64-linux-gnu \
    --disable-all-pkgs \
    --enable-web2c \
    --enable-pdftex \
    --disable-xetex \
    --disable-luatex \
    --disable-luajittex \
    --disable-luahbtex \
    --disable-mf \
    --disable-mf-nowin \
    --disable-mp \
    --disable-pmp \
    --disable-upmp \
    --disable-aleph \
    --disable-eptex \
    --disable-euptex \
    --disable-ptex \
    --disable-uptex \
    --disable-hitex \
    --disable-shared \
    --disable-native-texlive-build \
    --without-x \
    --with-system-icu \
    --without-system-zlib \
    --without-system-libpng \
    --without-system-freetype2 \
    --without-system-harfbuzz \
    --without-system-cairo \
    --without-system-gd \
    --without-system-pixman \
    --without-system-graphite2 \
    --without-system-zziplib \
    --without-system-mpfr \
    --without-system-gmp \
    --without-system-potrace \
    --without-system-teckit \
    --without-system-paper \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    NM="$NM" \
    CFLAGS="$CFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH" \
    ICU_CFLAGS="-I${ICU_PREFIX}/include" \
    ICU_CPPFLAGS="-I${ICU_PREFIX}/include" \
    ICU_LIBS="-L${ICU_PREFIX}/lib -licuuc -licui18n -licudata" \
    2>&1 | tee configure-ohos.log

step_end

# ------------------------------------------------------------
# 编译
# ------------------------------------------------------------
step_start "编译 (make -j${JOBS})"

cd "${BUILD_DIR}"

make -j"${JOBS}" \
    TANGLE="${HOST_BUILD_DIR}/texk/web2c/tangle" \
    CTANGLE="${HOST_BUILD_DIR}/texk/web2c/ctangle" \
    OTANGLE="${HOST_BUILD_DIR}/texk/web2c/otangle" \
    TIE="${HOST_BUILD_DIR}/texk/web2c/tie" \
    2>&1 | tee make-ohos.log

step_end

# ------------------------------------------------------------
# 验证产物
# ------------------------------------------------------------
step_start "验证产物"

PDFTEX_BIN=$(find "${BUILD_DIR}" -name "pdftex" -type f -executable 2>/dev/null | head -1)

if [ -z "${PDFTEX_BIN}" ]; then
    log "错误: 未找到 pdftex 可执行文件"
    log "查看 make 日志末尾:"
    tail -30 "${BUILD_DIR}/make-ohos.log"
    exit 1
fi

log "找到 pdftex: ${PDFTEX_BIN}"
log "文件大小: $(ls -lh "${PDFTEX_BIN}" | awk '{print $5}')"
log "文件类型:"
file "${PDFTEX_BIN}" | sed 's/^/    /'

log "动态依赖:"
"${TOOLCHAIN_BIN}/llvm-readelf" -d "${PDFTEX_BIN}" 2>/dev/null \
    | grep -E "NEEDED|RPATH|RUNPATH" \
    | sed 's/^/    /' || log "    (静态链接或读取失败)"

# 拷贝到固定位置
DIST_DIR="${SCRIPT_DIR}/dist-ohos"
mkdir -p "${DIST_DIR}/bin"
cp "${PDFTEX_BIN}" "${DIST_DIR}/bin/pdftex"
${STRIP} "${DIST_DIR}/bin/pdftex"
log "已拷贝并 strip: ${DIST_DIR}/bin/pdftex ($(ls -lh "${DIST_DIR}/bin/pdftex" | awk '{print $5}'))"

step_end

# ------------------------------------------------------------
# 总结
# ------------------------------------------------------------
TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

echo ""
echo "============================================================"
log "全部完成 (总耗时 $(format_duration $TOTAL_DURATION))"
echo "============================================================"
echo ""
echo "产物位置: ${DIST_DIR}/bin/pdftex"
echo ""
echo "下一步:"
echo "  1. 推送到设备: hdc file send ${DIST_DIR}/bin/pdftex /data/local/tmp/texlive/bin/"
echo "  2. 准备 texmf 资源"
echo "  3. 在设备上测试运行"
echo ""

# Note: 你可以通过以下方法将 pdftex 发送至鸿蒙设备
# Windows
# netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8000 connectaddress=172.31.178.114 connectport=8000
# New-NetFirewallRule -DisplayName "WSL Server" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8000
# WSL
# python3 -m http.server