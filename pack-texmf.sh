#!/bin/bash
#
# pack-texmf.sh
# 打包 TeX Live 资源（鸿蒙 ARM64）
#
# 特点：
#   - 从 TeX Live tlnet 官方仓库下载宏包，不依赖系统 texlive
#   - 声明式宏包列表，加包改一行
#   - 自动生成 fmt 文件
#
# 用法: ./pack-texmf.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist-ohos"
TEXMF_DIR="${DIST_DIR}/texmf"
PACK_OUTPUT="${DIST_DIR}/texlive-ohos.tar.gz"
DOWNLOAD_CACHE="${SCRIPT_DIR}/.tlpkg-cache"
HOST_BUILD_DIR="${SCRIPT_DIR}/build-host"

# TeX Live tlnet 镜像（可换成国内镜像加速）
TLNET_MIRROR="${TLNET_MIRROR:-https://mirror.ctan.org/systems/texlive/tlnet/archive}"
# 备选国内镜像：
# TLNET_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/CTAN/systems/texlive/tlnet/archive"
# TLNET_MIRROR="https://mirrors.ustc.edu.cn/CTAN/systems/texlive/tlnet/archive"

# CJK 字体来源（系统路径，可选）
NOTO_CJK_PATHS=(
    "/usr/share/fonts/opentype/noto"
    "/usr/share/fonts/truetype/noto"
    "/usr/share/fonts/opentype/noto-cjk"
)

# lycium 依赖路径
LYCIUM_USR="${LYCIUM_USR:-/home/suwan/tpc_c_cplusplus/lycium/usr}"

JOBS="${JOBS:-$(nproc)}"

# ============================================================
# 宏包声明（改这里就行）
# ============================================================

# 格式：tlnet 包名（不带 .tar.xz）
# 分类仅为可读性，下载逻辑统一处理

# --- 核心：plain TeX + LaTeX 格式生成必需 ---
PACKAGES_CORE=(
    # plain TeX
    plain
    knuth-lib
    knuth-local
    hyphen-base
    hyph-utf8
    tex-ini-files
    unicode-data
    # pdftex 配置
    pdftex
    # LaTeX 内核
    latex
    latex-fonts
    latex-base-dev
    latexconfig
    l3kernel
    l3backend
    l3packages
    # babel（断字）
    babel
    babel-english
)

# --- 字体 ---
PACKAGES_FONTS=(
    cm
    amsfonts
    lm
    lm-math            # 新增：OpenType 数学字体
    cm-super           # T1 编码的 CM 字体（Type1）
    # 字体映射
    fontname
    # cm-super（Type1 版 CM，PDF 嵌入用）
    cm-super
    glyphlist # pdftex 嵌入字体必需
)

# --- LaTeX 常用宏包 Tier 1（几乎所有文档都用） ---
PACKAGES_TIER1=(
    # 数学
    amsmath
    mathtools
    # 页面
    geometry
    # 颜色与图形
    xcolor
    graphics
    graphics-cfg
    graphics-def
    # 超链接
    hyperref
    bookmark
    url
    # 表格
    booktabs
    multirow
    # 图表
    caption
    float
    # 列表
    enumitem
    # 字体选择
    fontspec
    euenc
    # 工具集
    tools
    etoolbox
    iftex
    # hyperref 依赖链
    pdftexcmds
    infwarerr
    kvsetkeys
    kvdefinekeys
    ltxcmds
    etexcmds
    kvoptions
    pdfescape
    hycolor
    letltxmacro
    auxhook
    intcalc
    bigintcalc
    bitset
    uniquecounter
    refcount
    rerunfilecheck
    gettitlestring
    atbegshi
    atveryend
    epstopdf-pkg
    hobsub
    # xetex 相关
    xkeyval
    filehook
    xltxtra
    xunicode
    # hyperref 的间接依赖（tlnet 拆包后的小工具）
    stringenc
    pdflscape
    zref
    needspace
    xstring
)

# --- LaTeX 常用宏包 Tier 2（大多数论文会用） ---
PACKAGES_TIER2=(
    listings
    fancyvrb
    microtype
    titlesec
    wrapfig
    setspace
    parskip
    cite
    natbib
    csquotes
    fancyhdr
    # 算法
    algorithms
    algorithmicx
    # 科学
    siunitx
    # 盒子
    tcolorbox
    environ
    pgf
    # 其他
    oberdiek
    subfig
    # IEEE 模板支持
    ieeetran
    newtx
    txfonts
    lipsum
    # Tier 2 补充
    fontaxes              # newtx 依赖
    helvetic              # PSNFSS 字体
    courier               # PSNFSS 字体
    psnfss                # PostScript 字体支持（hyperref 也可能用）
    ec                    # T1 编码字体 
    # PSNFSS 字体（PostScript 标准 35 字体的 LaTeX 支持）
    times
    palatino
    bookman
    charter
    ncntrsbk
    utopia
    avantgar
    zapfding
    zapfchan
    # URW base 35 字体本体
    # urw-base35 （下载失败）
)

# --- 中文支持 ---
PACKAGES_CJK=(
    ctex
    xecjk
    zhnumber
    zhmetrics
    cjk
    cjkpunct
    # adobemapping（CMap）
    adobemapping
    fandol
)

# --- dvips / dvipdfmx ---
PACKAGES_DRIVERS=(
    dvips
    dvipdfmx
)

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

# 下载并解压一个 tlnet 包
# 用法: fetch_package <pkgname>
fetch_package() {
    local pkg="$1"
    local tarball="${pkg}.tar.xz"
    local cached="${DOWNLOAD_CACHE}/${tarball}"
    local url="${TLNET_MIRROR}/${tarball}"

    # 已缓存则跳过下载
    if [ -f "${cached}" ]; then
        tar xf "${cached}" -C "${TEXMF_DIR}" --strip-components=0 2>/dev/null || true
        return 0
    fi

    # 下载
    if curl -fsSL -o "${cached}.tmp" "${url}" 2>/dev/null; then
        mv "${cached}.tmp" "${cached}"
        tar xf "${cached}" -C "${TEXMF_DIR}" --strip-components=0 2>/dev/null || true
        return 0
    else
        rm -f "${cached}.tmp"
        return 1
    fi
}

# 并行下载（控制并发数）
fetch_packages_parallel() {
    local -n pkg_array=$1
    local label="$2"
    local total=${#pkg_array[@]}
    local ok=0
    local fail=0
    local fail_list=""

    log "  下载 ${label} (${total} 个包)..."

    # 用 xargs 并行下载，最多 8 并发
    for pkg in "${pkg_array[@]}"; do
        if fetch_package "${pkg}"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
            fail_list="${fail_list} ${pkg}"
        fi
    done

    if [ ${fail} -gt 0 ]; then
        log "    ✓ ${ok} 成功, ✗ ${fail} 失败: ${fail_list}"
    else
        log "    ✓ 全部 ${ok} 个包下载成功"
    fi
}

# ============================================================
# 主流程
# ============================================================
TOTAL_START=$(date +%s)

echo "============================================================"
echo "  TeX Live 资源打包 (鸿蒙 ARM64)"
echo "  源: ${TLNET_MIRROR}"
echo "============================================================"

# ============================================================
# 第 1 步：前置检查
# ============================================================
echo ""
log "第 1 步: 前置检查"

if [ ! -f "${DIST_DIR}/bin/pdftex" ]; then
    log "错误: pdftex 二进制不存在: ${DIST_DIR}/bin/pdftex"
    log "请先运行 build-ohos.sh"
    exit 1
fi

# 检查 host 工具（生成 fmt 用）
HOST_PDFTEX="${HOST_BUILD_DIR}/texk/web2c/pdftex"
HOST_XETEX="${HOST_BUILD_DIR}/texk/web2c/xetex"
HOST_TEX="${HOST_BUILD_DIR}/texk/web2c/tex"
if [ ! -x "${HOST_PDFTEX}" ]; then
    log "警告: host pdftex 不存在，将跳过 fmt 生成"
    log "  请先运行: ./build-host.sh"
fi

# 检查工具
for cmd in curl tar xz; do
    if ! command -v ${cmd} >/dev/null 2>&1; then
        log "错误: 缺少命令 ${cmd}"
        exit 1
    fi
done

log "前置检查通过"

# ============================================================
# 第 2 步：清理
# ============================================================
echo ""
log "第 2 步: 清理旧文件"

rm -rf "${TEXMF_DIR}"
rm -rf "${DIST_DIR}/lib"
rm -rf "${DIST_DIR}/share"
rm -f "${PACK_OUTPUT}"
rm -f "${DIST_DIR}/test-"*.tex

mkdir -p "${TEXMF_DIR}"
mkdir -p "${DOWNLOAD_CACHE}"

log "清理完成"

# ============================================================
# 第 3 步：下载宏包
# ============================================================
echo ""
log "第 3 步: 从 tlnet 下载宏包"

fetch_packages_parallel PACKAGES_CORE "核心包"
fetch_packages_parallel PACKAGES_FONTS "字体包"
fetch_packages_parallel PACKAGES_TIER1 "Tier 1 宏包"
fetch_packages_parallel PACKAGES_TIER2 "Tier 2 宏包"
fetch_packages_parallel PACKAGES_CJK "中文支持"
fetch_packages_parallel PACKAGES_DRIVERS "驱动"

# 统计
PKG_TOTAL=$(find "${TEXMF_DIR}" -type f | wc -l)
PKG_SIZE=$(du -sh "${TEXMF_DIR}" | awk '{print $1}')
log "宏包下载完成: ${PKG_TOTAL} 个文件, ${PKG_SIZE}"

# ============================================================
# 第 4 步：整理目录结构
# ============================================================
echo ""
log "第 4 步: 整理目录结构"

# tlnet 解压后的结构是 texmf-dist/xxx，需要把内容提升一级
# 如果解压出来有 texmf-dist 子目录，合并到 TEXMF_DIR
if [ -d "${TEXMF_DIR}/texmf-dist" ]; then
    cp -a "${TEXMF_DIR}/texmf-dist/"* "${TEXMF_DIR}/" 2>/dev/null || true
    rm -rf "${TEXMF_DIR}/texmf-dist"
    log "已合并 texmf-dist/ 到 texmf/"
fi

# 删除不需要的文档和源码（节省空间）
rm -rf "${TEXMF_DIR}/doc" 2>/dev/null || true
rm -rf "${TEXMF_DIR}/source" 2>/dev/null || true

# 删除 tlpkg 元数据
rm -rf "${TEXMF_DIR}/tlpkg" 2>/dev/null || true

CLEAN_SIZE=$(du -sh "${TEXMF_DIR}" | awk '{print $1}')
log "清理后: ${CLEAN_SIZE}"

# ============================================================
# 第 5 步：生成 texmf.cnf
# ============================================================
echo ""
log "第 5 步: 生成 texmf.cnf"

mkdir -p "${TEXMF_DIR}/web2c"

cat > "${TEXMF_DIR}/web2c/texmf.cnf" << 'TEXMFCNF'
% texmf.cnf for TeX Live on HarmonyOS
% 自动生成，请勿手动编辑

TEXMFROOT = /storage/Users/currentUser/CodeArtsProjects/testtex
TEXMFDIST = $TEXMFROOT/texmf
TEXMFLOCAL = $TEXMFROOT/texmf
TEXMFVAR = $TEXMFROOT/texmf-var

TEXMFCNF = $TEXMFDIST/web2c

% TeX 输入路径
TEXINPUTS = .;$TEXMFDIST/tex/{plain,generic,latex,xelatex}//
TEXINPUTS.pdftex = .;$TEXMFDIST/tex/{plain,generic,latex}//
TEXINPUTS.pdflatex = .;$TEXMFDIST/tex/{plain,generic,latex}//
TEXINPUTS.tex = .;$TEXMFDIST/tex/{plain,generic}//
TEXINPUTS.xetex = .;$TEXMFDIST/tex/{plain,generic,latex,xelatex}//
TEXINPUTS.xelatex = .;$TEXMFDIST/tex/{plain,generic,latex,xelatex}//

% 字体路径
TFMFONTS = .;$TEXMFDIST/fonts/tfm//
T1FONTS = .;$TEXMFDIST/fonts/type1//
ENCFONTS = .;$TEXMFDIST/fonts/enc//
OPENTYPEFONTS = .;$TEXMFDIST/fonts/opentype//
TRUETYPEFONTS = .;$TEXMFDIST/fonts/truetype//
TEXFONTMAPS = .;$TEXMFDIST/fonts/map/{pdftex,dvips,glyphlist}/{updmap,}//

% pdftex glyph name 查找路径
GLYPHFONTS = .;$TEXMFDIST/fonts/map/glyphlist

% 格式与池
TEXFORMATS = .;$TEXMFDIST/web2c/{$engine,}
TEXPOOL = .;$TEXMFDIST/web2c

% dvips 路径
TEXPSHEADERS = .;$TEXMFDIST/dvips//;$TEXMFDIST/fonts/{enc,type1}//
PSHEADERS = .;$TEXMFDIST/dvips//
TEXCONFIG = .;$TEXMFDIST/dvips/{config,base}//

% dvipdfmx
CMAPFONTS = .;$TEXMFDIST/fonts/cmap//

TEXMFDBS = $TEXMFDIST

% ============================================================
% 内存与容量设置
% ============================================================
main_memory = 8000000
extra_mem_top = 0
extra_mem_bot = 0
pool_size = 12500000
string_vacancies = 90000
max_strings = 2097151
strings_free = 100
hash_extra = 600000
nest_size = 1000
param_size = 10000
save_size = 250000
stack_size = 10000
dvi_buf_size = 16384
error_line = 79
half_error_line = 50
max_in_open = 25
max_print_line = 79
trie_op_size = 35111
trie_size = 1000000
font_mem_size = 8000000
font_max = 9000
buf_size = 200000
expand_depth = 10000
obj_tab_size = 1000000
dest_names_size = 131072
pdf_mem_size = 65536
pk_dpi = 600
TEXMFCNF

log "texmf.cnf 生成完成"

# ============================================================
# 第 6 步：生成字体映射
# ============================================================
echo ""
log "第 6 步: 生成字体映射"

MAP_DIR="${TEXMF_DIR}/fonts/map"
PDFTEX_MAP="${MAP_DIR}/pdftex/updmap/pdftex.map"
mkdir -p "$(dirname ${PDFTEX_MAP})"

TMP_MAP="${MAP_DIR}/.merged.map.tmp"
> "${TMP_MAP}"

find "${MAP_DIR}" -name "*.map" -not -path "*/updmap/*" 2>/dev/null | sort | while read mapfile; do
    cat "${mapfile}" >> "${TMP_MAP}"
    echo "" >> "${TMP_MAP}"
done

# 按字体名（第一列）合并，保留 NF 最大的条目（最完整的 map 信息）
awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*%/ { next }
    {
        if (!($1 in nf) || NF > nf[$1]) {
            line[$1] = $0
            nf[$1] = NF
        }
    }
    END {
        for (k in line) print line[k]
    }
' "${TMP_MAP}" > "${PDFTEX_MAP}"

rm -f "${TMP_MAP}"

# dvips 用同一份
DVIPS_MAP="${MAP_DIR}/dvips/updmap/psfonts.map"
mkdir -p "$(dirname ${DVIPS_MAP})"
cp "${PDFTEX_MAP}" "${DVIPS_MAP}"

MAP_LINES=$(wc -l < "${PDFTEX_MAP}")
log "字体映射: ${MAP_LINES} 行（择优合并）"

# 验证 lm 关键条目没被踩坏
LM_BAD=$(grep -cE "^ec-lm.* lm-ec [a-z]+[0-9]+$" "${PDFTEX_MAP}" 2>/dev/null || true)
LM_GOOD=$(grep -cE "^ec-lm.* \"enclmec ReEncodeFont\"" "${PDFTEX_MAP}" 2>/dev/null || true)
# 兜底：如果是空字符串当 0 处理
LM_BAD="${LM_BAD:-0}"
LM_GOOD="${LM_GOOD:-0}"
log "  lm 完整条目: ${LM_GOOD}, 残缺条目: ${LM_BAD}"
if [ "${LM_BAD}" -gt 0 ] 2>/dev/null; then
    log "  警告：仍有 lm 残缺条目"
fi

# ============================================================
# 第 7 步：打包动态链接库
# ============================================================
echo ""
log "第 7 步: 打包动态链接库"

mkdir -p "${DIST_DIR}/lib"

for prefix in icu freetype2 harfbuzz graphite2 teckit zlib bzip2 libpng brotli fontconfig expat; do
    LIBDIR="${LYCIUM_USR}/${prefix}/arm64-v8a/lib"
    if [ ! -d "${LIBDIR}" ]; then
        log "  跳过 ${prefix} (目录不存在)"
        continue
    fi
    # 用 shell glob 代替 find
    for f in "${LIBDIR}"/*.so "${LIBDIR}"/*.so.*; do
        [ -e "$f" ] || continue
        cp -P "$f" "${DIST_DIR}/lib/"
    done
done

# libc++_shared.so（鸿蒙 NDK）
OHOS_SDK="${OHOS_SDK:-/home/suwan/ohos-sdk/linux}"
LIBCXX="${OHOS_SDK}/native/llvm/lib/aarch64-linux-ohos/libc++_shared.so"
if [ -f "${LIBCXX}" ]; then
    cp "${LIBCXX}" "${DIST_DIR}/lib/"
fi

LIB_COUNT=$(ls "${DIST_DIR}/lib/" 2>/dev/null | wc -l)
LIB_SIZE=$(du -sh "${DIST_DIR}/lib/" 2>/dev/null | awk '{print $1}')
log "动态库: ${LIB_COUNT} 个文件, ${LIB_SIZE}"

# ============================================================
# 第 8 步：ICU 数据
# ============================================================
echo ""
log "第 8 步: ICU 数据"

ICU_DATA_FILE=$(find "${LYCIUM_USR}/icu/arm64-v8a/share" -name "icudt*.dat" 2>/dev/null | head -1)
if [ -n "${ICU_DATA_FILE}" ]; then
    mkdir -p "${DIST_DIR}/share/icu"
    cp "${ICU_DATA_FILE}" "${DIST_DIR}/share/icu/"
    log "ICU 数据: $(basename ${ICU_DATA_FILE}) ($(ls -lh ${ICU_DATA_FILE} | awk '{print $5}'))"
else
    log "警告: 未找到 ICU 数据文件"
fi

# ============================================================
# 第 9 步：CJK 字体（可选，从系统复制）
# ============================================================
echo ""
log "第 9 步: CJK 字体"

mkdir -p "${TEXMF_DIR}/fonts/opentype/public/noto-cjk"
mkdir -p "${TEXMF_DIR}/fonts/truetype/public/noto-cjk"

for noto_dir in "${NOTO_CJK_PATHS[@]}"; do
    [ -d "${noto_dir}" ] || continue
    
    # 只复制简体中文（SC）系列
    for pattern in \
        "NotoSerifCJKsc-*.otf" \
        "NotoSansCJKsc-*.otf" \
        "NotoSerifCJKSC-*.otf" \
        "NotoSansCJKSC-*.otf"; do
        for f in "${noto_dir}"/${pattern}; do
            [ -e "$f" ] || continue
            cp "$f" "${TEXMF_DIR}/fonts/opentype/public/noto-cjk/"
        done
    done
    
    for pattern in \
        "NotoSerifCJK-*.ttc" \
        "NotoSansCJK-*.ttc"; do
        for f in "${noto_dir}"/${pattern}; do
            [ -e "$f" ] || continue
            cp "$f" "${TEXMF_DIR}/fonts/truetype/public/noto-cjk/"
        done
    done
done

CJK_FONT_COUNT=$(ls "${TEXMF_DIR}/fonts/opentype/public/noto-cjk" "${TEXMF_DIR}/fonts/truetype/public/noto-cjk" 2>/dev/null | wc -l)
if [ ${CJK_FONT_COUNT} -gt 0 ]; then
    CJK_SIZE=$(du -sh "${TEXMF_DIR}/fonts/opentype/public/noto-cjk" "${TEXMF_DIR}/fonts/truetype/public/noto-cjk" 2>/dev/null | tail -1 | awk '{print $1}')
    log "CJK 字体: ${CJK_FONT_COUNT} 个 (${CJK_SIZE})"
else
    log "警告: 未找到 Noto CJK 字体"
    log "  安装: sudo apt install fonts-noto-cjk"
fi

# ============================================================
# 第 10 步：fontconfig 配置
# ============================================================
echo ""
log "第 10 步: fontconfig 配置"

mkdir -p "${TEXMF_DIR}/fonts/conf"
cat > "${TEXMF_DIR}/fonts/conf/fonts.conf" << 'FONTCONF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <!-- texmf 内的字体 -->
    <dir prefix="default">../opentype</dir>
    <dir prefix="default">../truetype</dir>
    <!-- 鸿蒙系统字体 -->
    <dir>/system/fonts</dir>
    <dir>/data/themes/a/app/flag</dir>
    <cachedir>/data/storage/el2/base/.fontconfig</cachedir>
</fontconfig>
FONTCONF

log "fonts.conf 已生成"

# ============================================================
# 第 11 步：生成 fmt 文件
# ============================================================
echo ""
log "第 11 步: 生成 fmt 文件"

mkdir -p "${TEXMF_DIR}/web2c/pdftex"
mkdir -p "${TEXMF_DIR}/web2c/xetex"

FMT_WORK_DIR="${SCRIPT_DIR}/.fmt-work"
rm -rf "${FMT_WORK_DIR}"
mkdir -p "${FMT_WORK_DIR}/tex/generic/config"

# 最小化 language.dat / language.def（只支持英文断字）
# 必须放在 FMT_WORK_DIR 里且让 TEXINPUTS 优先搜它，否则会加载 hyph-utf8 完整列表
cat > "${FMT_WORK_DIR}/tex/generic/config/language.dat" << 'LDAT'
=english
=USenglish
hyphen.tex
LDAT

cat > "${FMT_WORK_DIR}/tex/generic/config/language.def" << 'LDEF'
% Minimal language.def - only English
\addlanguage{USenglish}{hyphen}{}{2}{3}
\uselanguage{USenglish}
LDEF

# 设置环境
export TEXMFCNF="${TEXMF_DIR}/web2c"
export TEXMF="${TEXMF_DIR}"
export TEXMFDIST="${TEXMF_DIR}"
export TEXMFLOCAL="${TEXMF_DIR}"
export TEXMFVAR="${FMT_WORK_DIR}"
export TEXMFCONFIG="${FMT_WORK_DIR}"
export TEXMFSYSCONFIG="${FMT_WORK_DIR}"
export TEXMFSYSVAR="${FMT_WORK_DIR}"
unset TEXMFHOME
# 关键：FMT_WORK_DIR 在 TEXMF_DIR 之前，让最小 language.dat 覆盖完整版
export TEXINPUTS=".:${FMT_WORK_DIR}//:${TEXMF_DIR}//"

# 通用 fmt 生成函数：engine ini-arg jobname output-dir
gen_fmt() {
    local engine="$1"
    local ini_arg="$2"
    local jobname="$3"
    local outdir="$4"
    local extra_args="$5"

    cd "${FMT_WORK_DIR}"
    rm -f "${jobname}".* 2>/dev/null

    log "  生成 ${jobname}.fmt..."

    # 关键三件套：
    #   < /dev/null        防止 fatal error 时等待输入
    #   -interaction=batchmode  比 nonstopmode 更安静
    #   超时保护           避免无限循环
    timeout 60 "${engine}" \
        -ini ${extra_args} \
        -jobname="${jobname}" \
        -progname="${jobname}" \
        -interaction=batchmode \
        "${ini_arg}" < /dev/null > /dev/null 2>&1 || true

    if [ -f "${jobname}.fmt" ]; then
        mkdir -p "${outdir}"
        mv "${jobname}.fmt" "${outdir}/"
        local FMT_SIZE=$(ls -lh "${outdir}/${jobname}.fmt" | awk '{print $5}')
        log "  ✓ ${jobname}.fmt (${FMT_SIZE})"
        cd "${SCRIPT_DIR}"
        return 0
    else
        log "  ✗ ${jobname}.fmt 未生成"
        if [ -f "${jobname}.log" ]; then
            log "    log 末尾："
            tail -30 "${jobname}.log" | sed 's/^/      /'
        fi
        cd "${SCRIPT_DIR}"
        return 1
    fi
}

# --- pdflatex.fmt ---
if [ -x "${HOST_PDFTEX}" ]; then
    gen_fmt "${HOST_PDFTEX}" "*pdflatex.ini" "pdflatex" "${TEXMF_DIR}/web2c/pdftex" "-etex"
fi

# --- latex.fmt (DVI 模式) ---
if [ -x "${HOST_PDFTEX}" ]; then
    gen_fmt "${HOST_PDFTEX}" "*latex.ini" "latex" "${TEXMF_DIR}/web2c/pdftex" "-etex"
fi

# --- plain.fmt (PDF 模式) ---
if [ -x "${HOST_PDFTEX}" ]; then
    cd "${FMT_WORK_DIR}"
    cat > plain-init.tex << 'EOF'
\pdfoutput=1
\input plain
\dump
EOF
    log "  生成 plain.fmt..."
    timeout 60 "${HOST_PDFTEX}" -ini \
        -jobname=plain \
        -interaction=batchmode \
        plain-init.tex < /dev/null > /dev/null 2>&1 || true

    if [ -f plain.fmt ]; then
        mv plain.fmt "${TEXMF_DIR}/web2c/"
        cp "${TEXMF_DIR}/web2c/plain.fmt" "${TEXMF_DIR}/web2c/pdftex.fmt"
        log "  ✓ plain.fmt + pdftex.fmt"
    else
        log "  ✗ plain.fmt 未生成"
        [ -f plain.log ] && tail -20 plain.log | sed 's/^/      /'
    fi
    rm -f plain-init.tex
    cd "${SCRIPT_DIR}"
fi

# --- tex.fmt (DVI 模式，必须用 host tex 而非 pdftex) ---
if [ -x "${HOST_TEX}" ]; then
    cd "${FMT_WORK_DIR}"
    cat > tex-init.tex << 'EOF'
\input plain
\dump
EOF
    log "  生成 tex.fmt..."
    timeout 60 "${HOST_TEX}" -ini \
        -jobname=tex \
        -interaction=batchmode \
        tex-init.tex < /dev/null > /dev/null 2>&1 || true

    if [ -f tex.fmt ]; then
        mv tex.fmt "${TEXMF_DIR}/web2c/"
        log "  ✓ tex.fmt"
    else
        log "  ✗ tex.fmt 未生成"
        [ -f tex.log ] && tail -20 tex.log | sed 's/^/      /'
    fi
    rm -f tex-init.tex
    cd "${SCRIPT_DIR}"
else
    log "  跳过 tex.fmt（host tex 不存在: ${HOST_TEX}）"
fi

# --- xelatex.fmt ---
if [ -x "${HOST_XETEX}" ]; then
    gen_fmt "${HOST_XETEX}" "*xelatex.ini" "xelatex" "${TEXMF_DIR}/web2c/xetex" "-etex"
else
    log "  跳过 xelatex.fmt（host xetex 不存在）"
fi

# 清理
rm -rf "${FMT_WORK_DIR}"

# 还原环境
unset TEXMFCNF TEXMF TEXMFDIST TEXMFLOCAL TEXMFVAR TEXMFCONFIG
unset TEXMFSYSCONFIG TEXMFSYSVAR TEXINPUTS

# ============================================================
# 第 12 步：生成测试文件
# ============================================================
echo ""
log "第 12 步: 生成测试文件"

# --- plain TeX ---
cat > "${DIST_DIR}/test-plain.tex" << 'EOF'
Hello, HarmonyOS!

This is plain \TeX\ running on OpenHarmony.

Simple math: $E = mc^2$

Display math:
$$\int_0^\infty e^{-x^2}\,dx = {\sqrt\pi \over 2}$$

\bye
EOF

# --- 基础 LaTeX ---
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

# --- 真实场景 LaTeX（含 hyperref/booktabs/listings 等） ---
cat > "${DIST_DIR}/test-latex-full.tex" << 'EOF'
\documentclass[a4paper,11pt]{article}
\usepackage[margin=2cm]{geometry}
\usepackage{lmodern}
\usepackage[T1]{fontenc}
\usepackage{amsmath,mathtools}
\usepackage{booktabs}
\usepackage{xcolor}
\usepackage{microtype}
\usepackage{listings}
\usepackage[colorlinks=true,linkcolor=blue,urlcolor=teal]{hyperref}

\title{Real-world LaTeX Test on HarmonyOS}
\author{TeX Live for HarmonyOS}
\date{\today}

\begin{document}
\maketitle
\tableofcontents

\section{Hyperlinks}
Visit \url{https://example.com} or click \href{https://kiro.dev}{Kiro}.

\section{Mathematics}
\begin{align}
  \nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \\
  \nabla \cdot \mathbf{B} &= 0 \\
  \nabla \times \mathbf{E} &= -\frac{\partial \mathbf{B}}{\partial t}
\end{align}

\section{Tables}
\begin{tabular}{@{}lrr@{}}
\toprule
Item & Quantity & Price \\
\midrule
Apple  & 3 & \$1.50 \\
Banana & 6 & \$0.75 \\
Cherry & 1 & \$4.00 \\
\bottomrule
\end{tabular}

\section{Code Listings}
\begin{lstlisting}[language=C,basicstyle=\ttfamily\small]
int main(int argc, char *argv[]) {
    printf("Hello, HarmonyOS!\n");
    return 0;
}
\end{lstlisting}

\section{Colors}
This text is in \textcolor{red}{red}, \textcolor{blue}{blue}, and \textcolor{green!50!black}{dark green}.

\end{document}
EOF

# --- xelatex 英文 ---
cat > "${DIST_DIR}/test-xelatex.tex" << 'EOF'
\documentclass{article}
\usepackage{fontspec}
\begin{document}
\section{XeLaTeX on HarmonyOS}

Hello, this is \XeLaTeX\ running on OpenHarmony.

Math: $\displaystyle \int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$

\end{document}
EOF

# --- xelatex 中文 ---
cat > "${DIST_DIR}/test-xelatex-cjk.tex" << 'EOF'
\documentclass[UTF8,fontset=none]{ctexart}

% 显式指定字体（打包的 Noto CJK SC）
\setCJKmainfont{Noto Serif CJK SC}
\setCJKsansfont{Noto Sans CJK SC}
\setCJKmonofont{Noto Sans Mono CJK SC}

\title{鸿蒙系统上的 \XeLaTeX 测试}
\author{TeX Live for HarmonyOS}

\begin{document}
\maketitle

\section{中文排版}
你好，世界！这是在鸿蒙系统上运行的 \XeLaTeX。

\subsection{数学公式}
行内公式：$E = mc^2$

行间公式：
\[
    \int_0^\infty e^{-x^2}\,\mathrm{d}x = \frac{\sqrt{\pi}}{2}
\]

\subsection{中英混排}
LaTeX 是 Leslie Lamport 基于 Donald Knuth 的 \TeX\ 开发的排版系统。

\end{document}
EOF

log "测试文件已生成: test-plain.tex, test-latex.tex, test-latex-full.tex, test-xelatex.tex, test-xelatex-cjk.tex"

# ============================================================
# 第 13 步：打包
# ============================================================
echo ""
log "第 13 步: 打包"

cd "${DIST_DIR}"

# 收集要打包的内容
PACK_ITEMS="bin/ lib/ texmf/"
[ -d "share" ] && PACK_ITEMS="${PACK_ITEMS} share/"

# 加入测试文件
for f in test-plain.tex test-latex.tex test-latex-full.tex test-xelatex.tex test-xelatex-cjk.tex; do
    [ -f "${f}" ] && PACK_ITEMS="${PACK_ITEMS} ${f}"
done

tar czf texlive-ohos.tar.gz ${PACK_ITEMS}

PACK_SIZE=$(ls -lh texlive-ohos.tar.gz | awk '{print $5}')
TEXMF_SIZE=$(du -sh texmf/ | awk '{print $1}')
LIB_SIZE=$(du -sh lib/ 2>/dev/null | awk '{print $1}')
BIN_SIZE=$(du -sh bin/ | awk '{print $1}')
FILE_COUNT=$(find bin/ lib/ texmf/ -type f 2>/dev/null | wc -l)

log "打包完成"

# ============================================================
# 总结
# ============================================================
TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

echo ""
echo "============================================================"
echo "  打包完成 (总耗时 $(format_duration $TOTAL_DURATION))"
echo "============================================================"
echo ""
echo "  产物:        ${PACK_OUTPUT}"
echo "  压缩包:      ${PACK_SIZE}"
echo "  bin/:        ${BIN_SIZE}"
echo "  lib/:        ${LIB_SIZE}"
echo "  texmf/:      ${TEXMF_SIZE}"
echo "  文件总数:    ${FILE_COUNT}"
echo ""
echo "  测试文件:"
echo "    test-plain.tex        - plain TeX"
echo "    test-latex.tex        - 基础 LaTeX"
echo "    test-latex-full.tex   - 真实场景 (hyperref/booktabs/listings)"
echo "    test-xelatex.tex      - XeLaTeX 英文"
echo "    test-xelatex-cjk.tex  - XeLaTeX 中文"
echo ""
echo "  下一步:"
echo "    cd ${DIST_DIR}"
echo "    python3 -m http.server"
echo "============================================================"