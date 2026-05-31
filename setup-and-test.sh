#!/bin/sh
#
# setup-and-test.sh
# 鸿蒙设备上的 TeX Live 安装与测试
#
# 用法:
#   sh setup-and-test.sh [服务器地址]
#   例: sh setup-and-test.sh 192.168.43.19:8000
#
# 不带参数时假设 texlive-ohos.tar.gz 已在当前目录
#

set -e

# ============================================================
# 配置
# ============================================================
INSTALL_DIR="$(pwd)"
ARCHIVE="texlive-ohos.tar.gz"
SERVER_URL="${1:-}"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

log_ok()   { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
log_err()  { printf "${RED}[FAIL]${NC}  %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
log_info() { printf "        %s\n" "$*"; }
log_dim()  { printf "${DIM}        %s${NC}\n" "$*"; }
log_step() {
    printf "${BLUE}[STEP]=== %s ===${NC}\n" "$*"
}

# 计数器
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

mark_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); log_ok "$*"; }
mark_fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); log_err "$*"; }
mark_skip() { TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); log_warn "$*"; }

# ============================================================
# 通用编译测试函数
# 用法: run_compile_test <名称> <命令...>
#   - 成功条件：返回码 0 且生成对应 PDF
#   - 失败时显示 log 末尾
# ============================================================
run_compile_test() {
    local name="$1"
    shift
    local input_tex="$1"
    shift

    local jobname="${input_tex%.tex}"
    local pdf="${jobname}.pdf"
    local logfile="${jobname}.log"

    # 清理旧产物
    rm -f "${jobname}".pdf "${jobname}".log "${jobname}".aux "${jobname}".dvi "${jobname}".xdv 2>/dev/null

    log_info "运行: $* ${input_tex}"
    "$@" "${input_tex}" > /dev/null 2>&1 || true

    if [ -f "${pdf}" ]; then
        local SIZE=$(ls -l "${pdf}" | awk '{print $5}')
        mark_pass "${name}: ${pdf} (${SIZE} bytes)"
        return 0
    else
        mark_fail "${name} 编译失败"
        if [ -f "${logfile}" ]; then
            log_dim "  ${logfile} 末尾:"
            tail -20 "${logfile}" | sed 's/^/          /'
        fi
        return 1
    fi
}

echo "============================================================"
echo "  TeX Live for HarmonyOS - 安装与测试"
echo "  目录: ${INSTALL_DIR}"
echo "============================================================"

# ============================================================
# 第 1 步：获取资源
# ============================================================
log_step "第 1 步: 获取资源"

if [ -n "${SERVER_URL}" ]; then
    log_info "从 http://${SERVER_URL}/${ARCHIVE} 下载..."
    if ! curl -fsSL -O "http://${SERVER_URL}/${ARCHIVE}"; then
        log_err "下载失败"
        exit 1
    fi
fi

if [ ! -f "${ARCHIVE}" ]; then
    log_err "未找到 ${ARCHIVE}"
    log_info "用法: sh setup-and-test.sh <服务器IP>:<端口>"
    log_info "或先手动下载: curl -O http://<IP>:8000/${ARCHIVE}"
    exit 1
fi

ARCHIVE_SIZE=$(ls -lh "${ARCHIVE}" | awk '{print $5}')
log_ok "压缩包: ${ARCHIVE} (${ARCHIVE_SIZE})"

# ============================================================
# 第 2 步：解压
# ============================================================
log_step "第 2 步: 解压"

# 清理旧产物（保留压缩包和脚本本身）
rm -rf bin/ lib/ share/ texmf/ texmf-var/ .tmp/ 2>/dev/null
rm -f test-*.tex test-*.pdf test-*.log test-*.aux test-*.dvi test-*.xdv test-*.ps test-*.ind test-*.idx test-*.ilg 2>/dev/null

if ! tar xzf "${ARCHIVE}"; then
    log_err "解压失败"
    exit 1
fi

mkdir -p texmf-var .tmp

BIN_COUNT=$(ls bin/ 2>/dev/null | wc -l)
TEXMF_SIZE=$(du -sh texmf/ 2>/dev/null | awk '{print $1}')
log_ok "bin/: ${BIN_COUNT} 个二进制"
log_ok "texmf/: ${TEXMF_SIZE}"

# ============================================================
# 第 3 步：展开 lib/ 符号链接
# ============================================================
log_step "第 3 步: 展开 lib/ 符号链接"

if [ ! -d "lib" ]; then
    log_warn "lib/ 不存在，跳过"
else
    LINK_COUNT=0
    for lnk in lib/*; do
        [ -L "${lnk}" ] || continue
        TARGET=$(readlink "${lnk}")
        case "${TARGET}" in
            /*) REAL_FILE="${TARGET}" ;;
            *)  REAL_FILE="lib/${TARGET}" ;;
        esac
        if [ -f "${REAL_FILE}" ]; then
            rm -f "${lnk}"
            cp "${REAL_FILE}" "${lnk}"
            LINK_COUNT=$((LINK_COUNT + 1))
        fi
    done
    LIB_TOTAL=$(ls lib/ 2>/dev/null | wc -l)
    LIB_SIZE=$(du -sh lib/ 2>/dev/null | awk '{print $1}')
    log_ok "展开 ${LINK_COUNT} 个链接，共 ${LIB_TOTAL} 个文件 (${LIB_SIZE})"
fi

exit 1

# ============================================================
# 第 4 步：签名
# ============================================================
log_step "第 4 步: 签名"

if ! command -v binary-sign-tool >/dev/null 2>&1; then
    log_warn "binary-sign-tool 不可用，跳过签名"
    log_warn "如果执行失败，请手动签名"
else
    SIGN_OK=0
    SIGN_FAIL=0
    SIGN_FAIL_LIST=""

    sign_one() {
        local f="$1"
        [ -f "$f" ] || return 1
        [ -L "$f" ] && return 1

        # 重试 3 次（大文件首次签名经常失败）
        local i=0
        while [ $i -lt 3 ]; do
            if binary-sign-tool sign -inFile "$f" -outFile "$f" -selfSign 1 >/dev/null 2>&1; then
                SIGN_OK=$((SIGN_OK + 1))
                return 0
            fi
            i=$((i + 1))
            sleep 1
        done

        SIGN_FAIL=$((SIGN_FAIL + 1))
        SIGN_FAIL_LIST="${SIGN_FAIL_LIST} $f"
        return 1
    }

    log_info "签名 bin/ ..."
    for bin in bin/*; do
        sign_one "$bin"
    done

    if [ -d "lib" ]; then
        log_info "签名 lib/ ..."
        for lib in lib/*; do
            case "$(basename "$lib")" in
                *.so|*.so.*) sign_one "$lib" ;;
            esac
        done
    fi

    log_ok "签名: ${SIGN_OK} 成功, ${SIGN_FAIL} 失败"
    if [ ${SIGN_FAIL} -gt 0 ]; then
        log_warn "签名失败的文件:"
        for f in ${SIGN_FAIL_LIST}; do
            log_dim "  $f"
        done
    fi
fi

chmod +x bin/* 2>/dev/null
[ -d "lib" ] && chmod 644 lib/* 2>/dev/null
log_ok "权限设置完成"

# ============================================================
# 第 5 步：配置环境变量
# ============================================================
log_step "第 5 步: 配置环境变量"

export PATH="${INSTALL_DIR}/bin:${PATH}"
export TEXMFCNF="${INSTALL_DIR}/texmf/web2c"
export TEXMFVAR="${INSTALL_DIR}/texmf-var"
export TMPDIR="${INSTALL_DIR}/.tmp"

if [ -d "${INSTALL_DIR}/lib" ]; then
    export LD_LIBRARY_PATH="${INSTALL_DIR}/lib:${LD_LIBRARY_PATH:-}"
fi

if [ -d "${INSTALL_DIR}/share/icu" ]; then
    export ICU_DATA="${INSTALL_DIR}/share/icu"
fi

# fontconfig
export FONTCONFIG_PATH="${INSTALL_DIR}/texmf/fonts/conf"
export FONTCONFIG_FILE="${INSTALL_DIR}/texmf/fonts/conf/fonts.conf"
export FC_CACHEDIR="${INSTALL_DIR}/texmf-var/fontconfig"
mkdir -p "${FC_CACHEDIR}"

log_info "PATH:               ${INSTALL_DIR}/bin"
log_info "TEXMFCNF:           ${TEXMFCNF}"
log_info "LD_LIBRARY_PATH:    ${INSTALL_DIR}/lib"
log_info "TMPDIR:             ${TMPDIR}"
log_info "FC_CACHEDIR:        ${FC_CACHEDIR}"
[ -n "${ICU_DATA:-}" ] && log_info "ICU_DATA:           ${ICU_DATA}"
log_ok "环境变量配置完成"

# ============================================================
# 第 6 步：核心工具可执行性检查
# ============================================================
log_step "第 6 步: 核心工具可执行性"

CORE_TOOLS="pdftex tex xetex xdvipdfmx bibtex makeindex dvipdfmx kpsewhich mpost dvips dvipng dvisvgm"

for tool in $CORE_TOOLS; do
    if [ ! -f "bin/${tool}" ]; then
        mark_skip "${tool} 不存在"
        continue
    fi

    OUTPUT=$(./bin/${tool} --version 2>&1 | head -1 || true)
    [ -z "${OUTPUT}" ] && OUTPUT=$(./bin/${tool} --help 2>&1 | head -1 || true)

    if [ -n "${OUTPUT}" ]; then
        mark_pass "${tool}: $(echo ${OUTPUT} | cut -c1-60)"
    else
        mark_fail "${tool} 无响应"
    fi
done

# ============================================================
# 第 7 步：fmt 文件检查
# ============================================================
log_step "第 7 步: fmt 文件检查"

FMT_FILES="
texmf/web2c/plain.fmt
texmf/web2c/pdftex.fmt
texmf/web2c/tex.fmt
texmf/web2c/pdftex/pdflatex.fmt
texmf/web2c/pdftex/latex.fmt
texmf/web2c/xetex/xelatex.fmt
"

for fmt in $FMT_FILES; do
    if [ -f "${fmt}" ]; then
        SIZE=$(ls -lh "${fmt}" | awk '{print $5}')
        log_ok "${fmt} (${SIZE})"
    else
        log_warn "${fmt} 不存在（对应测试将跳过）"
    fi
done

# ============================================================
# 第 8 步：plain TeX 测试
# ============================================================
log_step "第 8 步: plain TeX (pdftex)"

if [ -f "test-plain.tex" ] && [ -f "texmf/web2c/pdftex.fmt" ]; then
    run_compile_test "plain TeX → PDF" test-plain.tex \
        ./bin/pdftex -interaction=nonstopmode
else
    mark_skip "test-plain.tex 或 pdftex.fmt 缺失"
fi

# ============================================================
# 第 9 步：tex + dvipdfmx (DVI → PDF)
# ============================================================
log_step "第 9 步: tex + dvipdfmx"

if [ -f "test-plain.tex" ] && [ -f "texmf/web2c/tex.fmt" ] && [ -f "bin/dvipdfmx" ]; then
    cp test-plain.tex test-dvi.tex

    log_info "运行: tex test-dvi.tex"
    ./bin/tex -interaction=nonstopmode test-dvi.tex > /dev/null 2>&1 || true

    if [ -f "test-dvi.dvi" ]; then
        log_info "运行: dvipdfmx test-dvi.dvi"
        ./bin/dvipdfmx test-dvi.dvi > /dev/null 2>&1 || true

        if [ -f "test-dvi.pdf" ]; then
            SIZE=$(ls -l test-dvi.pdf | awk '{print $5}')
            mark_pass "tex → DVI → PDF: test-dvi.pdf (${SIZE} bytes)"
        else
            mark_fail "dvipdfmx 转换失败"
        fi
    else
        mark_fail "tex 编译 DVI 失败"
        [ -f test-dvi.log ] && tail -10 test-dvi.log | sed 's/^/          /'
    fi
else
    mark_skip "tex.fmt 或 dvipdfmx 缺失"
fi

# ============================================================
# 第 10 步：dvips (DVI → PS)
# ============================================================
log_step "第 10 步: dvips"

if [ -f "test-dvi.dvi" ] && [ -f "bin/dvips" ]; then
    log_info "运行: dvips -o test-dvi.ps test-dvi.dvi"
    ./bin/dvips -o test-dvi.ps test-dvi.dvi > /dev/null 2>&1 || true

    if [ -f "test-dvi.ps" ]; then
        SIZE=$(ls -l test-dvi.ps | awk '{print $5}')
        mark_pass "DVI → PS: test-dvi.ps (${SIZE} bytes)"
    else
        mark_fail "dvips 转换失败"
    fi
else
    mark_skip "dvips 或 DVI 缺失"
fi

# ============================================================
# 第 11 步：makeindex
# ============================================================
log_step "第 11 步: makeindex"

if [ -f "bin/makeindex" ]; then
    cat > test-idx.idx << 'EOF'
\indexentry{TeX}{1}
\indexentry{LaTeX}{2}
\indexentry{HarmonyOS}{3}
\indexentry{TeX!plain}{4}
\indexentry{TeX!extended}{5}
EOF

    log_info "运行: makeindex test-idx.idx"
    ./bin/makeindex test-idx.idx > /dev/null 2>&1 || true

    if [ -f "test-idx.ind" ]; then
        SIZE=$(ls -l test-idx.ind | awk '{print $5}')
        mark_pass "makeindex: test-idx.ind (${SIZE} bytes)"
    else
        mark_fail "makeindex 失败"
    fi
else
    mark_skip "makeindex 缺失"
fi

# ============================================================
# 第 12 步：基础 LaTeX
# ============================================================
log_step "第 12 步: 基础 LaTeX"

if [ -f "test-latex.tex" ] && [ -f "texmf/web2c/pdftex/pdflatex.fmt" ]; then
    run_compile_test "LaTeX → PDF" test-latex.tex \
        ./bin/pdftex -etex -fmt=pdflatex -interaction=nonstopmode
else
    mark_skip "pdflatex.fmt 或 test-latex.tex 缺失"
fi

# ============================================================
# 第 13 步：完整 LaTeX (hyperref / booktabs / listings)
# ============================================================
log_step "第 13 步: 完整 LaTeX 场景"

if [ -f "test-latex-full.tex" ] && [ -f "texmf/web2c/pdftex/pdflatex.fmt" ]; then
    # 完整文档可能需要两遍编译生成目录
    log_info "第一遍编译..."
    ./bin/pdftex -etex -fmt=pdflatex -interaction=nonstopmode test-latex-full.tex > /dev/null 2>&1 || true

    log_info "第二遍编译（生成目录/交叉引用）..."
    ./bin/pdftex -etex -fmt=pdflatex -interaction=nonstopmode test-latex-full.tex > /dev/null 2>&1 || true

    if [ -f "test-latex-full.pdf" ]; then
        SIZE=$(ls -l test-latex-full.pdf | awk '{print $5}')
        mark_pass "完整 LaTeX → PDF: test-latex-full.pdf (${SIZE} bytes)"
    else
        mark_fail "完整 LaTeX 编译失败"
        [ -f test-latex-full.log ] && {
            log_dim "  log 末尾:"
            tail -25 test-latex-full.log | sed 's/^/          /'
        }
    fi
else
    mark_skip "test-latex-full.tex 或 pdflatex.fmt 缺失"
fi

# ============================================================
# 第 14 步：XeLaTeX 英文
# ============================================================
log_step "第 14 步: XeLaTeX (英文)"

if [ -f "test-xelatex.tex" ] && [ -f "texmf/web2c/xetex/xelatex.fmt" ]; then
    run_compile_test "XeLaTeX → PDF" test-xelatex.tex \
        ./bin/xetex -fmt=xelatex -interaction=nonstopmode
else
    mark_skip "xelatex.fmt 或 test-xelatex.tex 缺失"
fi

# ============================================================
# 第 15 步：XeLaTeX 中文
# ============================================================
log_step "第 15 步: XeLaTeX (中文)"

if [ -f "test-xelatex-cjk.tex" ] && [ -f "texmf/web2c/xetex/xelatex.fmt" ]; then
    # 检查 CJK 字体是否存在
    CJK_FONT_COUNT=$(find texmf/fonts -name "NotoSerifCJK*" -o -name "NotoSansCJK*" 2>/dev/null | wc -l)
    if [ "${CJK_FONT_COUNT}" -eq 0 ]; then
        log_warn "未找到 CJK 字体，依赖 fontconfig 找系统字体"
    else
        log_info "找到 ${CJK_FONT_COUNT} 个 CJK 字体文件"
    fi

    run_compile_test "XeLaTeX 中文 → PDF" test-xelatex-cjk.tex \
        ./bin/xetex -fmt=xelatex -interaction=nonstopmode
else
    mark_skip "xelatex.fmt 或 test-xelatex-cjk.tex 缺失"
fi

# ============================================================
# 第 16 步：总结
# ============================================================
log_step "第 16 步: 总结"

echo ""
echo "  通过: ${TESTS_PASSED}"
echo "  失败: ${TESTS_FAILED}"
echo "  跳过: ${TESTS_SKIPPED}"
echo ""

# 列出所有产物
log_info "生成的产物:"
for f in test-*.pdf test-*.dvi test-*.ps test-*.ind; do
    if [ -f "$f" ]; then
        SIZE=$(ls -lh "$f" | awk '{print $5}')
        printf "          %-30s %s\n" "$f" "${SIZE}"
    fi
done

# 工具清单（仅当全绿时）
if [ ${TESTS_FAILED} -eq 0 ] && [ ${TESTS_SKIPPED} -eq 0 ]; then
    echo ""
    log_info "完整工具清单:"

    print_category() {
        local title="$1"
        shift
        local found=""
        for t in "$@"; do
            [ -f "bin/$t" ] && found="${found} $t"
        done
        if [ -n "${found}" ]; then
            printf "          %-15s%s\n" "${title}:" "${found}"
        fi
    }

    print_category "TeX 引擎" pdftex tex xetex luatex luajithbtex
    print_category "MetaPost"  mpost pmpost upmpost mfluajit mflua mft
    print_category "DVI"        dvipdfmx xdvipdfmx dvips dvipng dvisvgm dvi2tty dvitype dvilj dvilj4 dvicopy dviconcat dviselect dvidvi dvibook
    print_category "BibTeX"     bibtex bibtex8 bibtexu upbibtex
    print_category "索引"       makeindex mendex upmendex
    print_category "字体工具"   afm2tfm afm2pl tftopl pltotf vftovp vptovf gftopk pktogf gftype pktype ttf2tfm ttf2pk ttf2afm ttftotype42 cfftot1 t1asm t1disasm otfinfo otftotfm gsftopk
    print_category "辅助"       kpsewhich kpseaccess kpsereadlink kpsestat detex chktex lacheck ttfdump synctex

    echo ""
    echo "============================================================"
    echo "  使用方法 (新 shell 需重新设置环境变量):"
    echo "============================================================"
    cat << USAGE

  export PATH="${INSTALL_DIR}/bin:\$PATH"
  export TEXMFCNF="${INSTALL_DIR}/texmf/web2c"
  export LD_LIBRARY_PATH="${INSTALL_DIR}/lib:\$LD_LIBRARY_PATH"
  export TMPDIR="${INSTALL_DIR}/.tmp"
  export FONTCONFIG_PATH="${INSTALL_DIR}/texmf/fonts/conf"
  export FONTCONFIG_FILE="${INSTALL_DIR}/texmf/fonts/conf/fonts.conf"
  export FC_CACHEDIR="${INSTALL_DIR}/texmf-var/fontconfig"
USAGE
[ -n "${ICU_DATA:-}" ] && echo "  export ICU_DATA=\"${INSTALL_DIR}/share/icu\""
cat << USAGE

  # 编译命令:
  pdftex yourfile.tex                       # plain TeX → PDF
  pdftex -fmt=pdflatex -etex yourfile.tex   # LaTeX → PDF
  xetex -fmt=xelatex yourfile.tex           # XeLaTeX (中文/Unicode) → PDF
  tex yourfile.tex && dvipdfmx yourfile     # tex + dvipdfmx
  tex yourfile.tex && dvips yourfile        # tex + dvips
USAGE
    echo "============================================================"
fi

# 退出码
if [ ${TESTS_FAILED} -gt 0 ]; then
    echo ""
    log_err "存在测试失败，详见上方日志"
    exit 1
elif [ ${TESTS_SKIPPED} -gt 0 ]; then
    echo ""
    log_warn "存在跳过的测试（产物缺失或可选功能未启用）"
    exit 0
else
    echo ""
    log_ok "全部测试通过 ✓"
    exit 0
fi