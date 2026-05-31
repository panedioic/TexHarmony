#!/bin/bash
#
# pack-texmf.sh
# 打包 TeX Live 最小资源 + pdftex 二进制（鸿蒙 ARM64）
# 用法: ./pack-texmf.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist-ohos"
TEXMF_DIR="${DIST_DIR}/texmf"
PACK_OUTPUT="${DIST_DIR}/texlive-ohos.tar.gz"

# TeX Live 系统 texmf 路径
SYSTEM_TEXMF="/usr/share/texlive/texmf-dist"
# updmap 生成的映射文件路径（Debian/Ubuntu）
SYSTEM_TEXMF_VAR="/var/lib/texmf"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

echo "============================================================"
echo "  打包 TeX Live 最小资源 (鸿蒙 ARM64)"
echo "============================================================"

# ============================================================
# 第1步：前置检查
# ============================================================
echo ""
log "第1步: 前置检查"

if [ ! -f "${DIST_DIR}/bin/pdftex" ]; then
    echo "错误: pdftex 二进制不存在: ${DIST_DIR}/bin/pdftex"
    echo "请先运行 build-ohos.sh 编译"
    exit 1
fi

if [ ! -d "${SYSTEM_TEXMF}" ]; then
    echo "错误: 系统 texmf 不存在: ${SYSTEM_TEXMF}"
    echo "请先安装: sudo apt install texlive-base texlive-plain-generic texlive-fonts-recommended"
    exit 1
fi

# 检查关键文件是否存在
MISSING=""
[ ! -f "${SYSTEM_TEXMF}/tex/plain/base/plain.tex" ] && MISSING="${MISSING} plain.tex"
[ ! -d "${SYSTEM_TEXMF}/fonts/tfm/public/cm" ] && MISSING="${MISSING} cm-tfm"

if [ -n "${MISSING}" ]; then
    echo "错误: 缺少系统文件:${MISSING}"
    echo "请安装: sudo apt install texlive-base texlive-plain-generic texlive-fonts-recommended"
    exit 1
fi

log "前置检查通过"

# ============================================================
# 第2步：清理旧文件
# ============================================================
echo ""
log "第2步: 清理旧文件"

rm -rf "${TEXMF_DIR}"
rm -f "${PACK_OUTPUT}"
# 保留 bin/ 目录（pdftex 二进制）
rm -f "${DIST_DIR}/test-plain.tex" "${DIST_DIR}/test-latex.tex"

log "清理完成"

# ============================================================
# 第3步：创建目录结构
# ============================================================
echo ""
log "第3步: 创建目录结构"

mkdir -p "${TEXMF_DIR}/web2c"
mkdir -p "${TEXMF_DIR}/tex/plain/base"
mkdir -p "${TEXMF_DIR}/tex/generic/config"
mkdir -p "${TEXMF_DIR}/tex/generic/hyphen"
mkdir -p "${TEXMF_DIR}/tex/generic/knuth-lib"
mkdir -p "${TEXMF_DIR}/tex/generic/unicode-data"
mkdir -p "${TEXMF_DIR}/tex/latex/base"
mkdir -p "${TEXMF_DIR}/tex/latex/l3kernel"
mkdir -p "${TEXMF_DIR}/tex/latex/l3backend"
mkdir -p "${TEXMF_DIR}/tex/latex/amsmath"
mkdir -p "${TEXMF_DIR}/tex/latex/amsfonts"
mkdir -p "${TEXMF_DIR}/tex/latex/tools"
mkdir -p "${TEXMF_DIR}/fonts/tfm/public/cm"
mkdir -p "${TEXMF_DIR}/fonts/tfm/public/knuth-lib"
mkdir -p "${TEXMF_DIR}/fonts/tfm/public/amsfonts/cm"
mkdir -p "${TEXMF_DIR}/fonts/tfm/public/amsfonts/symbols"
mkdir -p "${TEXMF_DIR}/fonts/type1/public/amsfonts/cm"
mkdir -p "${TEXMF_DIR}/fonts/map/pdftex/updmap"
mkdir -p "${TEXMF_DIR}/fonts/enc/dvips"

log "目录结构创建完成"

# ============================================================
# 第4步：写入 texmf.cnf
# ============================================================
echo ""
log "第4步: 生成 texmf.cnf"

cat > "${TEXMF_DIR}/web2c/texmf.cnf" << 'TEXMFCNF'
% texmf.cnf for pdftex on HarmonyOS

TEXMFROOT = /storage/Users/currentUser/CodeArtsProjects/testtex
TEXMFDIST = $TEXMFROOT/texmf
TEXMFLOCAL = $TEXMFROOT/texmf
TEXMFVAR = $TEXMFROOT/texmf-var

TEXMFCNF = $TEXMFDIST/web2c

% 搜索路径
TEXINPUTS = .;$TEXMFDIST/tex/{plain,generic,latex}//
TEXINPUTS.pdftex = .;$TEXMFDIST/tex/{plain,generic,latex}//
TFMFONTS = .;$TEXMFDIST/fonts/tfm//
T1FONTS = .;$TEXMFDIST/fonts/type1//
ENCFONTS = .;$TEXMFDIST/fonts/enc//
TEXFONTMAPS = .;$TEXMFDIST/fonts/map/pdftex/updmap
TEXFORMATS = .;$TEXMFDIST/web2c
TEXPOOL = .;$TEXMFDIST/web2c

% 内存设置
main_memory = 5000000
extra_mem_top = 500000
extra_mem_bot = 500000
pool_size = 6250000
string_vacancies = 90000
max_strings = 500000
hash_extra = 600000
save_size = 80000
stack_size = 10000
TEXMFCNF

log "texmf.cnf 生成完成"

# ============================================================
# 第5步：复制 plain TeX 核心文件
# ============================================================
echo ""
log "第5步: 复制 plain TeX 核心文件"

# plain.tex
cp "${SYSTEM_TEXMF}/tex/plain/base/plain.tex" "${TEXMF_DIR}/tex/plain/base/"

# pdftex 配置
[ -f "${SYSTEM_TEXMF}/tex/generic/config/pdftexconfig.tex" ] && \
    cp "${SYSTEM_TEXMF}/tex/generic/config/pdftexconfig.tex" "${TEXMF_DIR}/tex/generic/config/"

# 断字文件（plain.tex 格式生成必需）
if [ -f "${SYSTEM_TEXMF}/tex/generic/hyphen/hyphen.tex" ]; then
    cp "${SYSTEM_TEXMF}/tex/generic/hyphen/hyphen.tex" "${TEXMF_DIR}/tex/generic/hyphen/"
fi
# 有些发行版放在 knuth-lib 下
if [ -f "${SYSTEM_TEXMF}/tex/generic/knuth-lib/hyphen.tex" ]; then
    cp "${SYSTEM_TEXMF}/tex/generic/knuth-lib/hyphen.tex" "${TEXMF_DIR}/tex/generic/knuth-lib/"
fi

# knuth-lib 全部（null.tex, plain.mf 等基础文件）
if [ -d "${SYSTEM_TEXMF}/tex/generic/knuth-lib" ]; then
    cp "${SYSTEM_TEXMF}/tex/generic/knuth-lib/"*.tex "${TEXMF_DIR}/tex/generic/knuth-lib/" 2>/dev/null || true
fi

# unicode-data（现代 LaTeX 需要）
if [ -d "${SYSTEM_TEXMF}/tex/generic/unicode-data" ]; then
    cp "${SYSTEM_TEXMF}/tex/generic/unicode-data/"*.tex "${TEXMF_DIR}/tex/generic/unicode-data/" 2>/dev/null || true
fi

log "plain TeX 核心文件复制完成"

# ============================================================
# 第6步：复制字体度量文件（TFM）
# ============================================================
echo ""
log "第6步: 复制字体度量文件"

# Computer Modern（必需）
cp "${SYSTEM_TEXMF}/fonts/tfm/public/cm/"*.tfm "${TEXMF_DIR}/fonts/tfm/public/cm/"

# knuth-lib 字体（manfnt, logo 等，plain.tex 引用）
if [ -d "${SYSTEM_TEXMF}/fonts/tfm/public/knuth-lib" ]; then
    cp "${SYSTEM_TEXMF}/fonts/tfm/public/knuth-lib/"*.tfm "${TEXMF_DIR}/fonts/tfm/public/knuth-lib/"
fi
# manfnt 可能在其他位置
find "${SYSTEM_TEXMF}/fonts/tfm" -name "manfnt*.tfm" -exec cp {} "${TEXMF_DIR}/fonts/tfm/public/knuth-lib/" \; 2>/dev/null || true
find "${SYSTEM_TEXMF}/fonts/tfm" -name "logo*.tfm" -exec cp {} "${TEXMF_DIR}/fonts/tfm/public/knuth-lib/" \; 2>/dev/null || true

# AMS 字体
if [ -d "${SYSTEM_TEXMF}/fonts/tfm/public/amsfonts/cm" ]; then
    cp "${SYSTEM_TEXMF}/fonts/tfm/public/amsfonts/cm/"*.tfm "${TEXMF_DIR}/fonts/tfm/public/amsfonts/cm/" 2>/dev/null || true
fi
if [ -d "${SYSTEM_TEXMF}/fonts/tfm/public/amsfonts/symbols" ]; then
    cp "${SYSTEM_TEXMF}/fonts/tfm/public/amsfonts/symbols/"*.tfm "${TEXMF_DIR}/fonts/tfm/public/amsfonts/symbols/" 2>/dev/null || true
fi

TFM_COUNT=$(find "${TEXMF_DIR}/fonts/tfm" -name "*.tfm" | wc -l)
log "字体度量文件复制完成 (${TFM_COUNT} 个 .tfm 文件)"

# ============================================================
# 第7步：复制 Type1 字体文件（PDF 嵌入必需）
# ============================================================
echo ""
log "第7步: 复制 Type1 字体文件"

# CM 字体的 .pfb 文件（PDF 中嵌入字体用）
if [ -d "${SYSTEM_TEXMF}/fonts/type1/public/amsfonts/cm" ]; then
    cp "${SYSTEM_TEXMF}/fonts/type1/public/amsfonts/cm/"*.pfb "${TEXMF_DIR}/fonts/type1/public/amsfonts/cm/"
    PFB_COUNT=$(ls "${TEXMF_DIR}/fonts/type1/public/amsfonts/cm/"*.pfb 2>/dev/null | wc -l)
    log "已复制 ${PFB_COUNT} 个 .pfb 文件 (amsfonts/cm)"
else
    log "警告: amsfonts/cm Type1 字体不存在"
    log "请安装: sudo apt install texlive-fonts-recommended"
fi

# enc 文件（字体编码）
if [ -d "${SYSTEM_TEXMF}/fonts/enc/dvips" ]; then
    cp -r "${SYSTEM_TEXMF}/fonts/enc/dvips/"* "${TEXMF_DIR}/fonts/enc/dvips/" 2>/dev/null || true
fi

log "Type1 字体文件复制完成"

# ============================================================
# 第8步：复制字体映射文件（pdftex.map）
# ============================================================
echo ""
log "第8步: 复制字体映射文件"

PDFTEX_MAP_FOUND=0

# 优先从 updmap 生成的位置查找
SEARCH_PATHS=(
    "${SYSTEM_TEXMF_VAR}/fonts/map/pdftex/updmap/pdftex.map"
    "/var/lib/texmf/fonts/map/pdftex/updmap/pdftex.map"
    "/usr/share/texmf/fonts/map/pdftex/updmap/pdftex.map"
    "${HOME}/.texlive/texmf-var/fonts/map/pdftex/updmap/pdftex.map"
)

for mapfile in "${SEARCH_PATHS[@]}"; do
    if [ -f "${mapfile}" ]; then
        cp "${mapfile}" "${TEXMF_DIR}/fonts/map/pdftex/updmap/pdftex.map"
        MAP_SIZE=$(ls -lh "${TEXMF_DIR}/fonts/map/pdftex/updmap/pdftex.map" | awk '{print $5}')
        log "已复制 pdftex.map (${MAP_SIZE}) 来源: ${mapfile}"
        PDFTEX_MAP_FOUND=1
        break
    fi
done

# 如果找不到 updmap 生成的，用 find 搜索
if [ ${PDFTEX_MAP_FOUND} -eq 0 ]; then
    FOUND_MAP=$(find /usr/share/texlive /var/lib/texmf /etc/texmf ${HOME}/.texlive* -name "pdftex.map" 2>/dev/null | head -1)
    if [ -n "${FOUND_MAP}" ]; then
        cp "${FOUND_MAP}" "${TEXMF_DIR}/fonts/map/pdftex/updmap/pdftex.map"
        log "已复制 pdftex.map 来源: ${FOUND_MAP}"
        PDFTEX_MAP_FOUND=1
    fi
fi

# 如果还是找不到，尝试生成
if [ ${PDFTEX_MAP_FOUND} -eq 0 ]; then
    log "未找到 pdftex.map，尝试用 updmap 生成..."
    if command -v updmap >/dev/null 2>&1; then
        updmap --pdftexmap 2>/dev/null || updmap-sys --pdftexmap 2>/dev/null || true
        FOUND_MAP=$(find /var/lib/texmf ${HOME}/.texlive* -name "pdftex.map" 2>/dev/null | head -1)
        if [ -n "${FOUND_MAP}" ]; then
            cp "${FOUND_MAP}" "${TEXMF_DIR}/fonts/map/pdftex/updmap/pdftex.map"
            log "已通过 updmap 生成并复制 pdftex.map"
            PDFTEX_MAP_FOUND=1
        fi
    fi
fi

# 最后的备选：用 cm.map 拼接一个最小映射
if [ ${PDFTEX_MAP_FOUND} -eq 0 ]; then
    log "警告: 无法找到 pdftex.map，尝试拼接最小映射..."
    CM_MAP=$(find "${SYSTEM_TEXMF}" -name "cm.map" -path "*/dvips/*" 2>/dev/null | head -1)
    if [ -n "${CM_MAP}" ]; then
        cp "${CM_MAP}" "${TEXMF_DIR}/fonts/map/pdftex/updmap/pdftex.map"
        # 追加 amsfonts 映射
        AMS_MAP=$(find "${SYSTEM_TEXMF}" -name "amsfonts.map" 2>/dev/null | head -1)
        [ -n "${AMS_MAP}" ] && cat "${AMS_MAP}" >> "${TEXMF_DIR}/fonts/map/pdftex/updmap/pdftex.map"
        log "已拼接最小映射文件"
        PDFTEX_MAP_FOUND=1
    fi
fi

if [ ${PDFTEX_MAP_FOUND} -eq 0 ]; then
    log "错误: 无法获取 pdftex.map"
    log "请运行: sudo apt install texlive-font-utils && sudo updmap-sys"
    exit 1
fi

log "字体映射文件复制完成"

# ============================================================
# 第9步：复制 LaTeX 核心文件
# ============================================================
echo ""
log "第9步: 复制 LaTeX 核心文件"

LATEX_BASE="${SYSTEM_TEXMF}/tex/latex/base"
if [ -d "${LATEX_BASE}" ]; then
    # 复制整个 base 目录（包含 latex.ltx 和所有核心 .sty/.cls/.def）
    cp "${LATEX_BASE}/"*.{ltx,cls,clo,sty,def,cfg,dfu,fd} "${TEXMF_DIR}/tex/latex/base/" 2>/dev/null || true
    LATEX_BASE_COUNT=$(ls "${TEXMF_DIR}/tex/latex/base/" | wc -l)
    log "latex/base: ${LATEX_BASE_COUNT} 个文件"
fi

# l3kernel（现代 LaTeX 必需）
L3KERNEL="${SYSTEM_TEXMF}/tex/latex/l3kernel"
if [ -d "${L3KERNEL}" ]; then
    cp "${L3KERNEL}/"*.{sty,ltx,def} "${TEXMF_DIR}/tex/latex/l3kernel/" 2>/dev/null || true
    log "l3kernel: $(ls "${TEXMF_DIR}/tex/latex/l3kernel/" | wc -l) 个文件"
fi

# l3backend
L3BACKEND="${SYSTEM_TEXMF}/tex/latex/l3backend"
if [ -d "${L3BACKEND}" ]; then
    cp "${L3BACKEND}/"*.{sty,def} "${TEXMF_DIR}/tex/latex/l3backend/" 2>/dev/null || true
    log "l3backend: $(ls "${TEXMF_DIR}/tex/latex/l3backend/" | wc -l) 个文件"
fi

# amsmath
AMSMATH="${SYSTEM_TEXMF}/tex/latex/amsmath"
if [ -d "${AMSMATH}" ]; then
    cp "${AMSMATH}/"*.sty "${TEXMF_DIR}/tex/latex/amsmath/" 2>/dev/null || true
    log "amsmath: $(ls "${TEXMF_DIR}/tex/latex/amsmath/" | wc -l) 个文件"
fi

# amsfonts
AMSFONTS_TEX="${SYSTEM_TEXMF}/tex/latex/amsfonts"
if [ -d "${AMSFONTS_TEX}" ]; then
    cp "${AMSFONTS_TEX}/"*.{sty,fd} "${TEXMF_DIR}/tex/latex/amsfonts/" 2>/dev/null || true
    log "amsfonts: $(ls "${TEXMF_DIR}/tex/latex/amsfonts/" | wc -l) 个文件"
fi

# tools（multicol, array, tabularx 等）
TOOLS="${SYSTEM_TEXMF}/tex/latex/tools"
if [ -d "${TOOLS}" ]; then
    cp "${TOOLS}/"*.{sty,def} "${TEXMF_DIR}/tex/latex/tools/" 2>/dev/null || true
    log "tools: $(ls "${TEXMF_DIR}/tex/latex/tools/" | wc -l) 个文件"
fi

log "LaTeX 核心文件复制完成"

# ============================================================
# 第10步：创建测试文件
# ============================================================
echo ""
log "第10步: 创建测试文件"

cat > "${DIST_DIR}/test-plain.tex" << 'EOF'
Hello, HarmonyOS!

This is plain \TeX\ running on OpenHarmony.

Simple math: $E = mc^2$

Display math:
$$\int_0^\infty e^{-x^2} dx = {\sqrt\pi \over 2}$$

\bye
EOF

cat > "${DIST_DIR}/test-latex.tex" << 'EOF'
\documentclass{article}
\usepackage{amsmath}
\begin{document}

\section{Hello HarmonyOS}

This is \LaTeX\ running on OpenHarmony.

\subsection{Math Test}

Inline: $E = mc^2$

Display:
\begin{equation}
  \int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
\end{equation}

\subsection{Alignment}

\begin{align}
  a &= b + c \\
  d &= e + f + g
\end{align}

\end{document}
EOF

log "测试文件创建完成"

# ============================================================
# 第11步：打包
# ============================================================
echo ""
log "第11步: 打包"

cd "${DIST_DIR}"
tar czf texlive-ohos.tar.gz bin/ texmf/ test-plain.tex test-latex.tex

PACK_SIZE=$(ls -lh texlive-ohos.tar.gz | awk '{print $5}')
FILE_COUNT=$(find bin/ texmf/ -type f | wc -l)
TEXMF_SIZE=$(du -sh texmf/ | awk '{print $1}')

log "打包完成"

# ============================================================
# 总结
# ============================================================
echo ""
echo "============================================================"
echo "  打包完成"
echo "============================================================"
echo ""
echo "  产物:       ${PACK_OUTPUT}"
echo "  包大小:     ${PACK_SIZE}"
echo "  texmf 大小: ${TEXMF_SIZE}"
echo "  文件总数:   ${FILE_COUNT}"
echo ""
echo "  内容:"
echo "    bin/pdftex          - pdftex 引擎 (aarch64 鸿蒙)"
echo "    texmf/              - TeX 资源文件"
echo "    test-plain.tex      - plain TeX 测试文件"
echo "    test-latex.tex      - LaTeX 测试文件"
echo ""
echo "  使用:"
echo "    cd ~/dev/texlive-build/dist-ohos"
echo "    python3 -m http.server"
echo "============================================================"