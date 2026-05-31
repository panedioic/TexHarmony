# TexHarmony

> TeX Live for HarmonyOS — 将 TeX Live 排版系统移植到 OpenHarmony / HarmonyOS NEXT 平台

本仓库是 TeX Live 移植到 HarmonyOS 的 meta 仓库，包含完整的交叉编译脚本、资源打包脚本、设备端测试脚本，以及 HAP 工程模板和 HNP 打包配方。

> 💡 **关于本项目**
> 本项目的诞生过程高度依赖了 AI 辅助（Vibe Coding），包括这份文档也是 AI 帮忙润色的。移植目前仍处于**非常早期**的阶段，可能存在各种坑，请带着探索和宽容的心态体验。欢迎 issue 和 PR。

> ⚠️ **平台限制**
> 由于该项目使用了 HNP（HarmonyOS Native Package）机制，目前**仅支持鸿蒙 PC**（搭载 HarmonyOS NEXT 的 PC 设备），**手机和平板暂时无法使用**。
> 此外，由于自签名流程在 HAP 层会失败，本仓库**不提供预编译的 HAP 包下载**，需要自行打包安装。

---

## 目录

- [功能现状](#功能现状)
- [仓库结构](#仓库结构)
- [构建前准备](#构建前准备)
- [构建流程](#构建流程)
  - [1. 准备工作目录](#1-准备工作目录)
  - [2. 获取 TeX Live 源码](#2-获取-tex-live-源码)
  - [3. 构建第三方依赖（lycium）](#3-构建第三方依赖lycium)
  - [4. 构建宿主机工具](#4-构建宿主机工具)
  - [5. 交叉编译鸿蒙二进制](#5-交叉编译鸿蒙二进制)
  - [6. 打包资源](#6-打包资源)
- [设备端测试](#设备端测试)
- [HNP 打包与 HAP 集成](#hnp-打包与-hap-集成)
- [使用方式](#使用方式)
- [常见问题](#常见问题)
- [致谢](#致谢)

---

## 功能现状

| 引擎 / 工具 | 状态 | 说明 |
|------------|------|------|
| `pdftex` / `pdflatex` | ✅ 可用 | 支持基础 LaTeX 文档、数学、表格、hyperref 等常见宏包 |
| `tex` / `latex` (DVI) | ✅ 可用 | 配合 `dvipdfmx` / `dvips` 可输出 PDF/PS |
| `xetex` / `xelatex` | ✅ 可用 | 支持 Unicode 与系统字体（含中文） |
| `bibtex` / `makeindex` | ✅ 可用 | 文献与索引生成 |
| `dvipdfmx` / `dvips` | ✅ 可用 | DVI 后端转换 |
| `luatex` / `luahbtex` | ❌ 暂不支持 | 跨编译尚未打通 |
| `metafont` (`mf`) | ❌ 暂不支持 | 同上 |

仓库内同时提供 **完整版** 与 **最小版**（仅 pdftex 子集）两套构建脚本，便于按需取舍。

---

## 仓库结构

```text
TexHarmony/
├── README.md                          # 本文档
├── app/                               # HAP 工程模板（鸿蒙应用）
├── hmp/                               # HNP 打包目录
│   └── arm64-v8a/                     # 放置打包后的 .hnp 文件
│
├── build-host.sh                      # 宿主机工具编译脚本（生成 tangle、ctangle 等）
├── build-ohos.sh                      # 鸿蒙交叉编译脚本（完整版）
├── build-ohos-minimum.sh              # 鸿蒙交叉编译脚本（最小版，仅 pdftex 子集）
│
├── pack-texmf.sh                      # 资源 + fmt 打包脚本（完整版）
├── pack-texmf-minimum.sh              # 资源 + fmt 打包脚本（最小版）
│
├── setup-and-test.sh                  # 设备端安装与测试脚本（完整版）
├── setup-and-test-minimum.sh          # 设备端安装与测试脚本（最小版）
│
└── hpkbuild/                          # 各依赖库的 lycium 构建配方（HPKBUILD）
    ├── icu/
    ├── freetype2/
    ├── harfbuzz/
    ├── graphite2/
    ├── teckit/
    ├── zlib/
    ├── bzip2/
    ├── libpng/
    ├── brotli/
    ├── fontconfig/
    └── expat/
```

---

## 构建前准备

### 推荐环境

- **操作系统**：WSL2 Ubuntu 22.04 / 24.04（笔者使用环境），或原生 Linux
- **磁盘空间**：建议预留 **30 GB+**（源码 + 多份构建产物 + 缓存）
- **内存**：8 GB 起步，16 GB 更稳妥

### 必备工具

```bash
sudo apt update
sudo apt install -y \
    build-essential autoconf automake libtool pkg-config \
    bison flex perl python3 \
    curl wget tar xz-utils \
    fonts-noto-cjk     # 用于打包 CJK 字体（可选）
```

### 鸿蒙 SDK

下载 OpenHarmony Native SDK，并解压到任意目录：

```bash
# 默认假设在 ~/ohos-sdk/linux
export OHOS_SDK=~/ohos-sdk/linux
```

> 脚本中通过 `OHOS_SDK` 环境变量定位 SDK，默认值为 `/home/suwan/ohos-sdk/linux`，请按实际情况修改或在执行脚本前 `export`。

---

## 构建流程

### 1. 准备工作目录

```bash
mkdir -p ~/dev/texlive
cd ~/dev/texlive
```

### 2. 获取 TeX Live 源码

从 TeX Live 官方仓库下载最新源码：

```bash
# 方式一：rsync（推荐）
rsync -a --delete rsync://tug.org/tldevsrc/Master/source/ texlive-source/

# 方式二：tar 包（更稳定但偏旧）
wget https://ftp.tug.org/historic/systems/texlive/2024/texlive-20240312-source.tar.xz
tar xf texlive-20240312-source.tar.xz
mv texlive-20240312-source texlive-source
```

最终目录应是这样：

```text
~/dev/texlive/
└── texlive-source/    # TeX Live 源码
```

将本仓库的 `build-*.sh`、`pack-*.sh` 等脚本拷贝到 `~/dev/texlive/` 下（与 `texlive-source/` 同级）。

### 3. 构建第三方依赖（lycium）

虽然 TeX Live 源码内置了所有依赖的源码，但部分依赖（ICU、HarfBuzz、FreeType 等）在交叉编译鸿蒙平台时**无法直接构建**，需要先单独编译为静态库。

这里推荐使用 [lycium](https://gitee.com/openharmony-sig/tpc_c_cplusplus) 工具链：

```bash
# 克隆 lycium
git clone https://gitee.com/openharmony-sig/tpc_c_cplusplus.git
cd tpc_c_cplusplus/lycium
```

针对每一个依赖，建立对应文件夹，并将本仓库 `hpkbuild/` 下对应的 `HPKBUILD` 文件拷贝进去：

```bash
# 以 icu 为例
mkdir -p icu && cd icu
cp /path/to/TexHarmony/hpkbuild/icu/HPKBUILD .

# 执行构建
../build.sh
```

依次构建以下依赖（顺序大致按依赖关系排列）：

```text
zlib → bzip2 → libpng → brotli → expat
     → freetype2 → graphite2 → harfbuzz → icu → teckit → fontconfig
```

构建产物会输出到 `lycium/usr/<pkg>/arm64-v8a/`，后续 `build-ohos.sh` 会从此处寻找。

> 💡 **为什么不用 lycium 自带的配方？**
> lycium 仓库中部分依赖的 HPKBUILD 存在以下问题：版本过旧、缺少必要的 patch、configure 参数不适配 TeX Live 的需求。本仓库的 HPKBUILD 经过实际验证，请优先使用。

依赖路径默认为 `/home/suwan/tpc_c_cplusplus/lycium/usr`，请通过 `LYCIUM_USR` 环境变量覆盖：

```bash
export LYCIUM_USR=~/tpc_c_cplusplus/lycium/usr
```

### 4. 构建宿主机工具

TeX Live 编译过程中需要 `tangle`、`ctangle`、`otangle`、`tie` 等元工具，这些工具必须以**与目标版本一致**的源码在主机上编译一份，用于交叉编译时调用。

```bash
cd ~/dev/texlive
./build-host.sh
```

成功后会生成 `build-host/` 目录，关键产物：

- `build-host/texk/web2c/tangle`
- `build-host/texk/web2c/ctangle`
- `build-host/texk/web2c/otangle`
- `build-host/texk/web2c/tie`
- `build-host/texk/web2c/pdftex`（用于生成 fmt）
- `build-host/texk/web2c/xetex`（用于生成 xelatex.fmt）

### 5. 交叉编译鸿蒙二进制

```bash
# 设置必要的环境变量（按实际路径修改）
export OHOS_SDK=~/ohos-sdk/linux
export LYCIUM_USR=~/tpc_c_cplusplus/lycium/usr

./build-ohos.sh
```

或者使用最小版（仅 pdftex 相关，体积更小、更快）：

```bash
./build-ohos-minimum.sh
```

成功后会生成 `dist-ohos/bin/`，包含所有 ARM64 鸿蒙可执行文件，例如：

```text
dist-ohos/bin/
├── pdftex
├── tex
├── xetex
├── bibtex
├── makeindex
├── dvipdfmx
├── dvips
├── kpsewhich
└── ... （共数十个工具）
```

### 6. 打包资源

二进制文件本身无法独立运行，还需要：

- **texmf 资源**（宏包、字体、配置文件）
- **预生成的 fmt 文件**（pdflatex.fmt、xelatex.fmt 等）
- **运行时动态库**（ICU、HarfBuzz 等的 `.so`）
- **ICU 数据文件**

`pack-texmf.sh` 会自动从 [TeX Live tlnet 镜像](https://mirror.ctan.org/systems/texlive/tlnet/archive) 下载所需宏包、整理目录、生成 fmt、收集动态库，并打包为 `dist-ohos/texlive-ohos.tar.gz`：

```bash
./pack-texmf.sh
```

如果国际镜像速度慢，可以切换到国内镜像：

```bash
TLNET_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/CTAN/systems/texlive/tlnet/archive \
    ./pack-texmf.sh
```

打包完成后会输出：

```text
dist-ohos/
├── bin/                      # 鸿蒙可执行文件
├── lib/                      # 动态库
├── share/icu/                # ICU 数据
├── texmf/                    # 宏包、字体、fmt
├── test-*.tex                # 测试用例
└── texlive-ohos.tar.gz       # 最终压缩包
```

---

## 设备端测试

> 前置条件：你的鸿蒙 PC 已经开启开发者模式，并安装了 [DevBox / DevEco Device Tool](https://developer.huawei.com/consumer/cn/deveco-device-tool/)。

### 步骤 1：在编译机上启动 HTTP 服务

在 `dist-ohos/` 目录下启动一个简单的 HTTP 服务：

```bash
cd dist-ohos
python3 -m http.server 8000
```

记下编译机的 IP 地址（如 `192.168.1.100`）。

### 步骤 2：在鸿蒙设备上下载并执行

将 `setup-and-test.sh` 通过 DevBox 拷贝到鸿蒙设备的某个可写目录（例如应用沙箱目录），然后：

```sh
sh setup-and-test.sh 192.168.1.100:8000
```

脚本会自动：

1. 从指定服务器下载 `texlive-ohos.tar.gz`
2. 解压到当前目录
3. 展开 `lib/` 中的符号链接
4. 调用 `binary-sign-tool` 对所有二进制和动态库自签名
5. 配置环境变量
6. 依次运行 13 项功能测试（plain TeX、LaTeX、XeLaTeX、CJK、bibtex、makeindex 等）

如果一切顺利，控制台会输出一系列 `[OK]`，并在末尾给出环境变量配置示例：

```text
通过: 13
失败: 0
跳过: 0
```

### 步骤 3：日常使用

在每个新的 shell 会话中，执行测试脚本最后输出的 `export` 命令即可使用：

```sh
export PATH="$INSTALL_DIR/bin:$PATH"
export TEXMFCNF="$INSTALL_DIR/texmf/web2c"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$LD_LIBRARY_PATH"
export TMPDIR="$INSTALL_DIR/.tmp"
export FONTCONFIG_PATH="$INSTALL_DIR/texmf/fonts/conf"
export FONTCONFIG_FILE="$INSTALL_DIR/texmf/fonts/conf/fonts.conf"
export FC_CACHEDIR="$INSTALL_DIR/texmf-var/fontconfig"

# 编译文档
pdftex hello.tex                          # plain TeX → PDF
pdftex -fmt=pdflatex -etex hello.tex      # LaTeX → PDF
xetex  -fmt=xelatex hello.tex             # XeLaTeX (中文 / Unicode) → PDF
```

---

## HNP 打包与 HAP 集成

为了让普通用户也能在鸿蒙 PC 上无脑使用 TeX Live，可以将编译产物打包为 **HNP（HarmonyOS Native Package）**，并通过 HAP 应用分发。

### 步骤 1：准备 HNP 工程目录

```bash
mkdir -p texlive-hnp
cd texlive-hnp

# 拷贝 dist-ohos 内容
cp -r ../dist-ohos/bin .
cp -r ../dist-ohos/lib .
cp -r ../dist-ohos/share .
cp -r ../dist-ohos/texmf .
```

### 步骤 2：编写 `hnp.json`

在 `texlive-hnp/` 目录下新建 `hnp.json`：

```json
{
  "type": "hnp-config",
  "name": "texlive",
  "version": "1.0.0",
  "install": {
    "links": [
      { "source": "bin/pdftex",    "target": "bin/pdftex" },
      { "source": "bin/tex",       "target": "bin/tex" },
      { "source": "bin/xetex",     "target": "bin/xetex" },
      { "source": "bin/bibtex",    "target": "bin/bibtex" },
      { "source": "bin/makeindex", "target": "bin/makeindex" },
      { "source": "bin/dvipdfmx",  "target": "bin/dvipdfmx" },
      { "source": "bin/dvips",     "target": "bin/dvips" },
      { "source": "bin/kpsewhich", "target": "bin/kpsewhich" }
    ]
  }
}
```

> `links` 中可以根据需要增减暴露的命令。

### 步骤 3：执行 HNP 打包

使用鸿蒙 SDK 中的 `hnpcli` 工具打包：

```bash
hnpcli pack -i ./texlive-hnp -o ./output -name texlive -v 1.0.0
```

会得到 `output/texlive.hnp`。

### 步骤 4：放入 HAP 工程

将生成的 `texlive.hnp` 文件移动到本仓库 `hmp/arm64-v8a/` 目录下：

```bash
cp output/texlive.hnp /path/to/TexHarmony/hmp/arm64-v8a/
```

### 步骤 5：构建并安装 HAP

打开 `app/` 工程目录，使用 DevEco Studio 连接你的鸿蒙 PC，点击 **Run** 即可一键打包安装。

安装成功后，在鸿蒙设备的命令行中验证：

```sh
pdftex -v
# 期望输出： pdfTeX 3.141592653-2.6-1.40.xx (TeX Live 2024) ...
```

---

## 使用方式

### 一个最小的 LaTeX 示例

`hello.tex`：

```latex
\documentclass{article}
\usepackage{amsmath}
\begin{document}
Hello, HarmonyOS!
$$ \int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2} $$
\end{document}
```

编译：

```sh
pdftex -fmt=pdflatex -etex hello.tex
```

### 中文 XeLaTeX 示例

`hello-cjk.tex`：

```latex
\documentclass[UTF8]{ctexart}
\begin{document}
你好，鸿蒙！这是在 HarmonyOS 上运行的 \XeLaTeX。
\end{document}
```

编译：

```sh
xetex -fmt=xelatex hello-cjk.tex
```

---

## 致谢

- [TeX Live](https://tug.org/texlive/) — 排版系统本体
- [OpenHarmony](https://www.openharmony.cn/) — 操作系统平台
- [lycium](https://gitee.com/openharmony-sig/tpc_c_cplusplus) — 第三方库交叉编译工具链
- 以及背后默默贡献的开源社区与帮我写代码的 AI

---

## License

本仓库中**新编写的脚本与文档**采用 MIT License。

TeX Live 本体、第三方依赖库、宏包等均遵循其各自的原始许可证（绝大部分为 LPPL / GPL / 自由许可）。