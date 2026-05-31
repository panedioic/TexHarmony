#!/bin/bash
#
# build-host.sh
# 在主机上构建 host 版本的 TeX Live 工具
# 用于：
#   1. 生成 web2c/tangle/ctangle 等给交叉编译使用
#   2. 生成与设备端相同版本的 .fmt 文件
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/texlive-source"
HOST_BUILD_DIR="${SCRIPT_DIR}/build-host"
HOST_INSTALL_DIR="${SCRIPT_DIR}/host-install"

JOBS="${JOBS:-$(nproc)}"
TOTAL_START=$(date +%s)

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

log "========================================"
log "  TeX Live Host 构建"
log "========================================"

# ============================================================
# 第1步：清理并准备
# ============================================================
if [ -d "${HOST_BUILD_DIR}" ]; then
    log "清理旧的 host 构建目录..."
    rm -rf "${HOST_BUILD_DIR}"
fi
mkdir -p "${HOST_BUILD_DIR}"
mkdir -p "${HOST_INSTALL_DIR}"

# ============================================================
# 第2步：configure（启用 pdftex + xetex）
# ============================================================
log "运行 configure..."
cd "${HOST_BUILD_DIR}"

"${SOURCE_DIR}/configure" \
    --prefix="${HOST_INSTALL_DIR}" \
    \
    --disable-shared \
    \
    --enable-web2c \
    --enable-pdftex \
    --enable-xetex \
    --enable-bibtex \
    --enable-makeindex \
    --enable-dvipdfmx \
    --enable-mp \
    --enable-tex \
    --enable-luatex \
    --enable-luajittex \
    --enable-luahbtex \
    --enable-mf \
    --enable-mf-nowin \
    --enable-aleph \
    --enable-eptex \
    --enable-euptex \
    --enable-ptex \
    --enable-uptex \
    --enable-hitex \
    --enable-xdvipsk \
    \
    --without-system-icu \
    --without-system-zlib \
    --without-system-freetype2 \
    --without-system-harfbuzz \
    --without-system-graphite2 \
    --without-system-teckit \
    --without-system-libpng \
    --without-system-cairo \
    --without-system-gd \
    --without-system-pixman \
    --without-system-zziplib \
    --without-system-mpfr \
    --without-system-gmp \
    --without-system-potrace \
    --without-system-paper \
    \
    2>&1 | tee configure-host.log

# ============================================================
# 第3步：编译
# ============================================================
log "编译 (make -j${JOBS})..."
make -j"${JOBS}" 2>&1 | tee make-host.log

# ============================================================
# 第4步：验证关键工具
# ============================================================
log "验证关键工具..."

CRITICAL_TOOLS=(
    "texk/web2c/tangle"
    "texk/web2c/ctangle"
    "texk/web2c/otangle"
    "texk/web2c/tie"
    "texk/web2c/pdftex"
    "texk/web2c/xetex"
    "texk/kpathsea/kpsewhich"
)

ALL_OK=1
for tool in "${CRITICAL_TOOLS[@]}"; do
    if [ -x "${HOST_BUILD_DIR}/${tool}" ]; then
        SIZE=$(ls -lh "${HOST_BUILD_DIR}/${tool}" | awk '{print $5}')
        log "  ✓ ${tool} (${SIZE})"
    else
        log "  ✗ ${tool} 缺失"
        ALL_OK=0
    fi
done

if [ ${ALL_OK} -eq 0 ]; then
    log "错误: 部分关键工具缺失，请检查 make-host.log"
    exit 1
fi

# 显示版本（让你确认 build-host 和 build-ohos 版本一致）
log ""
log "Host 版本信息:"
"${HOST_BUILD_DIR}/texk/web2c/pdftex" --version | head -1
"${HOST_BUILD_DIR}/texk/web2c/xetex" --version | head -1

# ============================================================
# 总结
# ============================================================
TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))
log "========================================"
log "  Host 构建完成 (总耗时 $(format_duration $TOTAL_DURATION))"
log "========================================"