#!/bin/bash
#
# 鸿蒙设备上的 TeX Live 一键配置和测试脚本
# 用法: 
#   curl -O http://<IP>:8000/texlive-ohos.tar.gz
#   curl -O http://<IP>:8000/setup-and-test.sh
#   chmod +x setup-and-test.sh
#   ./setup-and-test.sh
#

set -e

# ============================================================
# 配置
# ============================================================
# 安装目录（当前目录）
INSTALL_DIR="$(pwd)"
ARCHIVE="texlive-ohos.tar.gz"
SERVER_URL="${1:-}"  # 可选：传入服务器地址自动下载

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_err() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_info() { echo -e "[INFO] $*"; }

# ============================================================
# 第一步：获取资源
# ============================================================
echo "============================================================"
echo "  TeX Live for HarmonyOS - 安装与测试"
echo "============================================================"
echo ""

# 如果提供了服务器地址，自动下载
if [ -n "${SERVER_URL}" ]; then
    log_info "从 ${SERVER_URL} 下载资源..."
    curl -O "${SERVER_URL}/texlive-ohos.tar.gz" || {
        log_err "下载失败"
        exit 1
    }
fi

# 检查压缩包是否存在
if [ ! -f "${ARCHIVE}" ]; then
    log_err "未找到 ${ARCHIVE}"
    echo "请先下载: curl -O http://<IP>:8000/texlive-ohos.tar.gz"
    exit 1
fi

# ============================================================
# 第二步：解压
# ============================================================
log_info "解压 ${ARCHIVE}..."

# 清理旧文件（保留压缩包和本脚本）
rm -rf bin/ texmf/ texmf-var/ test-plain.tex test-latex.tex *.pdf *.log *.fmt *.aux

tar xzf "${ARCHIVE}"
log_ok "解压完成"

# 创建缓存目录
mkdir -p texmf-var

# ============================================================
# 第三步：签名并设置权限
# ============================================================
log_info "设置执行权限..."
chmod +x bin/pdftex

# 签名
if command -v binary-sign-tool >/dev/null 2>&1; then
    log_info "签名 pdftex..."
    binary-sign-tool sign -inFile bin/pdftex -outFile bin/pdftex -selfSign 1
    log_ok "签名完成"
else
    log_warn "binary-sign-tool 不可用，跳过签名"
    log_warn "如果执行失败，请手动签名: binary-sign-tool sign -inFile bin/pdftex -outFile bin/pdftex -selfSign 1"
fi

# ============================================================
# 第四步：设置环境变量
# ============================================================
log_info "配置环境变量..."

export TEXMFCNF="${INSTALL_DIR}/texmf/web2c"
export PATH="${INSTALL_DIR}/bin:${PATH}"

# 验证 pdftex 可运行
log_info "验证 pdftex 可执行..."
if ./bin/pdftex --version >/dev/null 2>&1; then
    VERSION=$(./bin/pdftex --version 2>&1 | head -1)
    log_ok "pdftex 可运行: ${VERSION}"
else
    # 可能 --version 不支持，试试直接运行看输出
    RESULT=$(echo '\relax' | ./bin/pdftex 2>&1 | head -1 || true)
    if echo "${RESULT}" | grep -q "pdfTeX"; then
        log_ok "pdftex 可运行: ${RESULT}"
    else
        log_err "pdftex 无法运行"
        echo "输出: ${RESULT}"
        exit 1
    fi
fi

# ============================================================
# 第五步：生成格式文件
# ============================================================
echo ""
echo "------------------------------------------------------------"
log_info "生成 plain TeX 格式文件 (plain.fmt)..."
echo "------------------------------------------------------------"

cd "${INSTALL_DIR}"

if [ -f "texmf/web2c/plain.fmt" ]; then
    log_info "plain.fmt 已存在，跳过生成"
else
    # 创建一个 ini 文件，包含 plain.tex 和 \dump 指令
    cat > plain-init.tex << 'EOF'
\pdfoutput=1
\input plain
\dump
EOF

    # -ini 模式 + 指定 jobname 生成 plain.fmt
    ./bin/pdftex -ini -jobname=plain -interaction=nonstopmode plain-init.tex 2>&1 | tail -10

    if [ -f "plain.fmt" ]; then
        mv plain.fmt texmf/web2c/
        log_ok "plain.fmt 生成成功"
    else
        log_err "plain.fmt 生成失败"
        echo "请检查 plain.log 获取详细信息"
        [ -f "plain.log" ] && tail -20 plain.log
        exit 1
    fi
fi

# 创建 pdftex.fmt 副本（pdftex 默认查找 pdftex.fmt）
if [ ! -f "texmf/web2c/pdftex.fmt" ]; then
    cp texmf/web2c/plain.fmt texmf/web2c/pdftex.fmt
    log_ok "已创建 pdftex.fmt"
fi

# 清理生成的临时文件
rm -f plain.log plain.pdf plain-init.tex 2>/dev/null

# ============================================================
# 第六步：测试 plain TeX 编译
# ============================================================
echo ""
echo "------------------------------------------------------------"
log_info "测试 1: plain TeX 编译"
echo "------------------------------------------------------------"

cd "${INSTALL_DIR}"

if [ ! -f "test-plain.tex" ]; then
    cat > test-plain.tex << 'EOF'
Hello, HarmonyOS!

This is plain \TeX\ running on OpenHarmony.

Simple math: $E = mc^2$

Display math:
$$\int_0^\infty e^{-x^2} dx = {\sqrt\pi \over 2}$$

\bye
EOF
fi

# 编译
rm -f test-plain.pdf test-plain.dvi test-plain.log 2>/dev/null
./bin/pdftex -interaction=nonstopmode test-plain.tex 2>&1 | tail -3

if [ -f "test-plain.pdf" ]; then
    PDF_SIZE=$(ls -l test-plain.pdf | awk '{print $5}')
    log_ok "plain TeX 编译成功! test-plain.pdf (${PDF_SIZE} bytes)"
elif [ -f "test-plain.dvi" ]; then
    log_warn "编译成功但输出为 DVI 而非 PDF，重新生成格式文件..."

    # 重新生成带 PDF 模式的格式
    rm -f texmf/web2c/plain.fmt texmf/web2c/pdftex.fmt

    cat > plain-init.tex << 'EOF'
\pdfoutput=1
\input plain
\dump
EOF
    ./bin/pdftex -ini -jobname=plain -interaction=nonstopmode plain-init.tex 2>&1 | tail -5
    if [ -f "plain.fmt" ]; then
        mv plain.fmt texmf/web2c/
        cp texmf/web2c/plain.fmt texmf/web2c/pdftex.fmt
        log_ok "已重新生成 PDF 模式格式文件"
    fi
    rm -f plain-init.tex plain.log test-plain.dvi 2>/dev/null

    # 重新编译测试
    ./bin/pdftex -interaction=nonstopmode test-plain.tex 2>&1 | tail -3
    if [ -f "test-plain.pdf" ]; then
        PDF_SIZE=$(ls -l test-plain.pdf | awk '{print $5}')
        log_ok "plain TeX 编译成功! test-plain.pdf (${PDF_SIZE} bytes)"
    else
        log_err "仍然无法生成 PDF"
        [ -f "test-plain.log" ] && tail -20 test-plain.log
        exit 1
    fi
else
    log_err "plain TeX 编译失败"
    echo "日志:"
    [ -f "test-plain.log" ] && tail -20 test-plain.log
    exit 1
fi

# ============================================================
# 第七步：测试 LaTeX 编译（可选）
# ============================================================
echo ""
echo "------------------------------------------------------------"
log_info "测试 2: LaTeX 编译"
echo "------------------------------------------------------------"

cd "${INSTALL_DIR}"
SKIP_LATEX=""

# 先生成 LaTeX 格式
if [ ! -f "texmf/web2c/pdflatex.fmt" ]; then
    log_info "生成 LaTeX 格式文件 (pdflatex.fmt)..."
    log_info "（这可能需要较长时间）"

    if [ -f "texmf/tex/latex/base/latex.ltx" ]; then
        # 创建 LaTeX 格式生成用的 ini 文件
        cat > pdflatex-init.tex << 'EOF'
\input latex.ltx
EOF

        ./bin/pdftex -ini -jobname=pdflatex -interaction=nonstopmode -progname=pdflatex pdflatex-init.tex 2>&1 | tail -10 || true

        if [ -f "pdflatex.fmt" ]; then
            mv pdflatex.fmt texmf/web2c/
            log_ok "pdflatex.fmt 生成成功"
        else
            log_warn "pdflatex.fmt 生成失败，跳过 LaTeX 测试"
            log_warn "这通常是因为缺少某些宏包文件，plain TeX 已经可用"
            [ -f "pdflatex.log" ] && tail -20 pdflatex.log
            SKIP_LATEX=1
        fi

        rm -f pdflatex-init.tex pdflatex.log 2>/dev/null
    else
        log_warn "latex.ltx 不存在，跳过 LaTeX 测试"
        SKIP_LATEX=1
    fi
fi

if [ -z "${SKIP_LATEX}" ] && [ -f "texmf/web2c/pdflatex.fmt" ] && [ -f "test-latex.tex" ]; then
    rm -f test-latex.pdf test-latex.log test-latex.aux 2>/dev/null

    # 用 pdflatex 格式编译
    ./bin/pdftex -interaction=nonstopmode -fmt=pdflatex test-latex.tex 2>&1 | tail -3

    if [ -f "test-latex.pdf" ]; then
        PDF_SIZE=$(ls -l test-latex.pdf | awk '{print $5}')
        log_ok "LaTeX 编译成功! test-latex.pdf (${PDF_SIZE} bytes)"
    else
        log_warn "LaTeX 编译失败（plain TeX 仍然可用）"
        [ -f "test-latex.log" ] && tail -10 test-latex.log
    fi
else
    [ -n "${SKIP_LATEX}" ] && log_info "跳过 LaTeX 测试"
fi

# ============================================================
# 总结
# ============================================================
echo ""
echo "============================================================"
echo "  测试完成"
echo "============================================================"
echo ""

# 统计结果
TESTS_PASSED=0
TESTS_TOTAL=0

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "test-plain.pdf" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  [PASS] plain TeX  → test-plain.pdf"
else
    echo "  [FAIL] plain TeX"
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "test-latex.pdf" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  [PASS] LaTeX      → test-latex.pdf"
else
    echo "  [SKIP] LaTeX (缺少依赖或格式生成失败)"
fi

echo ""
echo "  结果: ${TESTS_PASSED}/${TESTS_TOTAL} 通过"
echo ""
echo "------------------------------------------------------------"
echo "  使用方法:"
echo ""
echo "  # plain TeX:"
echo "  export TEXMFCNF=${INSTALL_DIR}/texmf/web2c"
echo "  ./bin/pdftex yourfile.tex"
echo ""
echo "  # LaTeX (如果格式生成成功):"
echo "  ./bin/pdftex -fmt=pdflatex yourfile.tex"
echo ""
echo "  # 或创建 pdflatex 符号链接:"
echo "  ln -sf pdftex bin/pdflatex"
echo "  ./bin/pdflatex yourfile.tex"
echo "============================================================"