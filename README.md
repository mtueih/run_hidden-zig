# run_hidden（Zig 版）

![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)
![Zig](https://img.shields.io/badge/Zig-0.17.0%2B-orange.svg)
![Size](https://img.shields.io/badge/Size-3_KiB-success.svg)
[![CI](https://github.com/mtueih/run_hidden-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/mtueih/run_hidden-zig/actions/workflows/ci.yml)
[![CD](https://github.com/mtueih/run_hidden-zig/actions/workflows/cd.yml/badge.svg)](https://github.com/mtueih/run_hidden-zig/actions/workflows/cd.yml)
[![GitHub License](https://img.shields.io/github/license/mtueih/run_hidden-zig)](LICENSE)

Windows 下以隐藏窗口启动进程的轻量级命令行工具，是 [mtueih/run_hidden](https://github.com/mtueih/run_hidden) 的 Zig 重写版本。

在保持行为一致的前提下，本项目利用 Zig 的自定义入口能力把「解析命令行」这件事从运行时彻底移除：不解析 `argv`、不重建命令行字符串、不做编码转换、不分配任何内存，直接把 `GetCommandLineW()` 返回的原始 UTF-16 缓冲区指针交给 `CreateProcessW()`。ReleaseFast 下单文件约 **3 KiB**，比上游的 C 版本（11,264 字节）还小。

## 与原项目的关系

本项目不是逐行翻译，而是在上游设计目标的基础上重新取舍后的产物：

| 维度 | 上游 `run_hidden`（C） | 本项目（Zig） |
| --- | --- | --- |
| 交付形态 | CLI + C 库（CMake 包） | **仅 CLI** |
| 平台 | 按跨平台设计，实际只服务 Windows | **仅 Windows** |
| 入口 | 默认 CRT 启动代码 → `main` | 自定义 `wWinMainCRTStartup` |
| 命令行来源 | CRT 解析出的 `argv` | `GetCommandLineW()` 原始字符串 |
| 命令行处理 | 重新拼接、加引号 | 原样截取首个 token 之后的部分 |
| 编码转换 | `CP_ACP` → UTF-16（`MultiByteToWideChar`） | 无（本来就是 UTF-16） |
| 内存分配 | `malloc` 命令行缓冲区 | 无分配、无拷贝 |
| 运行库依赖 | C 运行库 | 无 CRT，仅 `kernel32` |
| 单文件体积* | 11,264 B | **3,072 B** |

\* 两侧均为官方/本地 Release 构建的单个 exe 体积；本项目为 `-Doptimize=ReleaseFast`，调试信息可另行剥离。

### 为什么去掉了库

1. **两者目标冲突。** 本项目的性能来自自定义启动代码（绕过 CRT 的命令行解析）以及「不拷贝、不转换、零分配」的实现方式。这些特性只有在可执行文件自己的入口处才能成立；一旦封装成库函数，调用方必然已经走完了默认启动代码，库内部只能退回到「拿字符串 → 转换/拷贝 → 调用 API」的老路，性能特性无从谈起。
2. **库的必要性很低。** 上游的库接口本质上是对 `CreateProcessW` 的薄封装，真正有价值的逻辑（引号处理、编码转换、等待退出码）在需要时可以直接参考源码复制几行。相比之下，CLI 才是这个项目的主要使用方式。
3. **平台专化后复用需求下降。** 上游起步时考虑了跨平台，但最终只有 Windows 需要这套能力。本项目直接声明只支持 Windows，于是抽象层、可移植性代码和跨平台封装都失去了意义。

### 为什么只支持 Windows

- 隐藏窗口启动、`CREATE_NO_WINDOW`、`STARTF_USESHOWWINDOW` 都是 Win32 概念，在其他平台上没有等价物；
- 只有 Windows 会为 GUI 子系统程序提供「不分配控制台」的启动语义；
- 去掉跨平台分支后，整个程序只剩两个文件、约 250 行代码，Win32 声明也按「用多少写多少」裁剪到最小集合。

构建脚本会在目标平台不是 Windows 时直接报错终止，不会产生「看似可用实则未测」的产物。

## 命令行工具

本项目包含两个可执行文件，用法完全一致：

- `run_hidden.exe`：成功启动目标程序后立即返回 `0`；
- `run_hidden_wait.exe`：等待目标程序结束，并返回其退出码。

### 使用方法

```text
run_hidden <program> [args...]
run_hidden_wait <program> [args...]
```

- `<program>`：要启动的可执行文件，支持绝对路径、相对路径与 `PATH` 查找；
- `[args...]`：原样传给目标程序的参数。

示例：

```bat
run_hidden "C:\Program Files\Notepad3\Notepad3.exe" "C:\Temp\my notes.txt"
run_hidden_wait "C:\Tools\worker.exe" --mode "quick run"
```

因为工具把首个 token 之后的原始命令行原样转发，参数中的引号、空格与反斜杠都会保持你输入时的样子，不会被重新拼接或转义；中文等非 ASCII 参数也不经过代码页转换，不存在乱码或字符丢失。

### 行为说明

- 至少需要提供 `<program>`；未提供任何参数时，工具以退出码 `1` 结束（Debug 构建会额外向 stderr 输出提示）。
- `CreateProcessW` 失败时，以系统错误码退出；错误码为 `0` 时退化为 `1`。Debug 构建会向 stderr 输出失败提示，Release 构建保持静默。
- 工具自身编译为 Windows GUI 子系统程序，启动时不会闪现控制台窗口。

> ⚠️ 因为工具本身不附带控制台，在 `cmd`/PowerShell 里直接调用时通常拿不到它的退出码。`run_hidden_wait` 的真实退出码需要通过支持等待的方式获取，例如：
>
> - Windows API：`CreateProcess()` + `WaitForSingleObject()` + `GetExitCodeProcess()`；
> - `cmd /c start /wait run_hidden_wait.exe ...`；
> - PowerShell：`Start-Process -Wait -PassThru` 后读取 `.ExitCode`。

## 实现要点

### 自定义启动入口，绕开 CRT

默认启动代码会先把原始命令行解析成 `argc`/`argv`，再由运行库或应用代码重新拼装命令行——这是一次多余的「拆开再装回去」。本项目直接导出 PE 入口符号 `wWinMainCRTStartup`，阻止 Zig 标准库安装默认启动例程，于是：

- 没有参数解析，没有 `argv` 数组；
- 没有 `argc` 上限，也没有解析时的堆分配；
- 与入口相关的启动开销被压到只剩一次 `GetCommandLineW()` 调用。

入口符号只是名字，真正决定「不分配控制台」的是 PE 头里的 Subsystem 字段，构建脚本已将其设为 GUI。

### 原始字符串直接传递，零拷贝零转换

`GetCommandLineW()` 返回的是进程原始 UTF-16 命令行缓冲区。程序只做一件事：跳过第一个 token（兼容带引号与不带引号两种形式），把指针移到第二个 token 的起始处，然后把这个指针直接作为 `lpCommandLine` 传给 `CreateProcessW()`。

因此整个程序没有：

- `MultiByteToWideChar` 之类的编码转换；
- `malloc`/`memcpy` 或任何中间缓冲区；
- 引号重写逻辑（Windows 命令行解析规则本就直接作用于原始字符串）。

> `CreateProcessW` 允许就地修改传入的命令行缓冲区，这也是它要求可写缓冲区的原因。这里传入的是本进程自己的命令行缓冲区，之后不再读取，因此不产生任何副作用。

### 极简 Win32 声明

`src/win32.zig` 手写了所需的常量、结构体与函数声明，而不是引入完整的 Windows 绑定。文件内按「首次使用顺序」排列，并附有注释说明每项被谁使用，便于随代码一起审阅和裁剪。最终只链接 `kernel32`，不依赖 C 运行库。

### 用 panic 策略换体积

`main.zig` 将 panic 处理程序替换为 `std.debug.no_panic`，避免把栈回溯、stderr 加锁和格式化代码拖进二进制。

## 测试

```bash
zig build test
```

`zig build test` 会构建一个参数记录器 `argv_echo` 和一个测试驱动 `cli_test`，然后由测试驱动完成集成测试。

之所以需要这么一套东西，是因为两个工具都以隐藏窗口方式运行，子进程没有可用的控制台，无法通过标准输出/标准错误断言结果。测试的流程是：

1. 把 `run_hidden.exe`、`run_hidden_wait.exe` 和 `argv_echo.exe` 复制到一个**同时包含空格和中文**的临时目录，顺带覆盖带引号的程序路径与 Unicode 路径；
2. 对每个用例，先用完全相同的原始命令行直接启动 `argv_echo` 作为参照，再通过 `run_hidden_wait` 转发同一条命令行；
3. `argv_echo` 把收到的 `argv` 序列化到文件，测试驱动比较「参照结果」与「转发结果」，并要求两者都等于用例中硬编码的期望值。

用例集中覆盖 Windows `CreateProcessW` 命令行解析的经典陷阱，例如：

- 带空格、制表符、空字符串的参数；
- 反斜杠与双引号的各种组合：`\"`、`\\"`、`\\\"`、结尾反斜杠 + 引号、未闭合的引号等；
- 参数中间的引号、相邻引号段、只有引号的参数；
- Windows 路径、正斜杠路径、Unicode（中文、emoji）参数；
- 参数前后多余的空格，以及未被引号包裹的工具路径。

除参数转发外，测试还验证：`run_hidden_wait` 透传子进程退出码、`run_hidden` 成功启动后返回 `0`，以及两者在缺少参数时返回 `1`。当被测行为被破坏时，测试会打印具体用例、期望参数与实际参数。

## 持续集成与发布

- **CI**（`.github/workflows/ci.yml`）：在 `Debug`、`ReleaseFast`、`ReleaseSmall` 三种优化模式下分别构建并运行测试；额外验证 `-Dstrip=true` 的发布配置，并报告最终二进制大小。
- **CD**（`.github/workflows/cd.yml`）：推送 `v*` 标签时触发。先构建并运行测试，再把二进制、`LICENSE`、`README.md` 打包为 `run_hidden-<tag>-win64.zip`，生成 SHA-256 校验文件，最后创建 GitHub Release。

发布说明由 `scripts/release-notes.ps1` 自动生成，而不是只留一行 “Full Changelog”。它会：

- 按 Conventional Commits 的类型（新功能、修复、性能、重构、构建、CI、测试、文档、杂项）分组列出提交，并标注破坏性变更；
- 附上构建信息（Zig 版本、优化模式、目标平台）；
- 列出产物名称、大小与 SHA-256；
- 给出与上一个标签的完整 compare 链接。

发布后仍然可以在 GitHub 的 Release 页面手动补充或修改说明。

## 从源码构建

### 环境要求

- **操作系统**：Windows（仅支持 Windows 目标）；
- **工具链**：[Zig](https://ziglang.org/) 0.17.0 或更高版本。

### 构建命令

```bash
zig build -Doptimize=ReleaseFast
```

产物位于 `zig-out/bin/`：

```text
run_hidden.exe
run_hidden_wait.exe
```

默认会同时生成 `.pdb`。发布时若不需要符号文件，加上 `-Dstrip=true`：

```bash
zig build -Doptimize=ReleaseFast -Dstrip=true
```

> ReleaseFast 就是本项目的推荐发布模式：工具本身逻辑极短（一次进程创建），可执行文件体积在有无调试信息下都是 3,072 字节，而优化等级只影响速度与代码质量。

其他可用选项：

| 选项 | 说明 |
| --- | --- |
| `-Doptimize=Debug` | 默认值。体积较大，失败时向 stderr 打印诊断信息，适合开发调试 |
| `-Doptimize=ReleaseFast` | 推荐发布模式 |
| `-Doptimize=ReleaseSmall` | 进一步偏向体积；不生成 `.pdb` |
| `-Dstrip=true` | 移除调试信息且不生成 `.pdb` |
| `-Dtarget=...` | 仅接受 Windows 目标（如 `x86_64-windows`、`aarch64-windows`），其他目标会在构建开始时直接报错 |

测试单独运行：

```bash
zig build test
```

## 项目结构

```text
.
├── .github/workflows/
│   ├── ci.yml              # CI：多优化模式构建 + 集成测试
│   └── cd.yml              # CD：按标签打包并发布 Release
├── build.zig               # 构建脚本：两个产物、GUI 子系统、wait 编译期开关、test 步骤
├── build.zig.zon           # 包元数据（最低 Zig 版本等）
├── scripts/
│   └── release-notes.ps1   # 根据 git 历史生成发布说明
├── src/
│   ├── main.zig            # 入口、命令行截取、CreateProcessW 调用
│   └── win32.zig           # 项目所需的最小 Win32 声明集合
├── test/
│   ├── argv_echo.zig       # 测试辅助程序：把 argv 写入文件
│   └── cli_test.zig        # 集成测试驱动：命令行转发与退出码
├── LICENSE
└── README.md
```

两个可执行文件共用同一份 `main.zig`，通过 `build_options.wait` 这个编译期布尔值区分「是否等待并返回子进程退出码」。这样两个产物之间没有重复代码，也不会在 `run_hidden.exe` 中残留等待逻辑。

## 许可协议

本项目采用 [MIT 许可证](https://opensource.org/license/mit) 授权——详情请参阅 [LICENSE](LICENSE) 文件。
