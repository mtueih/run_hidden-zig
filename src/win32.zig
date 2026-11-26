// SPDX-License-Identifier: ISC
// Copyright (c) 2026 mtueih

//! run_hidden 所需的最小 Win32 API 声明集合。
//!
//! 排列规则：声明分为常量、类型、函数三个板块，每个板块内部严格按照
//! 它们在 main.zig 中首次被使用的顺序排列；类型的顺序则以其在下方
//! 函数声明中首次被引用的顺序为准。行尾注释标注了首次使用的位置。


// ───────────────────────── 常量（按首次使用顺序） ─────────────────────────

/// 用于 GetStdHandle() 函数的 nStdHandle 参数，表示标准错误设备。
pub const STD_ERROR_HANDLE: DWORD = @bitCast(@as(i32, -12));

/// 用于结构体 StartupInfoW 的 dwFlags 字段，表示启用 wShowWindow 字段。
pub const STARTF_USESHOWWINDOW: DWORD = 0x00000001;

/// 用于结构体 StartupInfoW 的 wShowWindow 字段，表示隐藏窗口。
pub const SW_HIDE: u16 = 0;

/// 用于 CreateProcessW() 函数的 dwCreationFlags 参数，表示隐藏控制台窗口。
pub const CREATE_NO_WINDOW: DWORD = 0x08000000;

/// 用于 WaitForSingleObject() 函数的 dwMilliseconds 参数，表示无限等待。
pub const INFINITE: DWORD = 0xffffffff; // wWinMainCRTStartup：WaitForSingleObject 调用


// ─────────────── 类型（按函数声明中首次引用的顺序） ───────────────

/// 宽字符类型。
pub const WCHAR = u16;
/// 句柄类型。
pub const HANDLE = *anyopaque;
/// 无符号 32 位整数类型别名。
pub const DWORD = u32;
/// 布尔类型。
pub const BOOL = i32;

/// 进程启动信息结构体。用于 CreateProcessW()。
pub const StartupInfoW = extern struct {
    cb: DWORD = @sizeOf(@This()),
    lpReserved: ?[*:0]WCHAR = null,
    lpDesktop: ?[*:0]WCHAR = null,
    lpTitle: ?[*:0]WCHAR = null,
    dwX: DWORD = 0,
    dwY: DWORD = 0,
    dwXSize: DWORD = 0,
    dwYSize: DWORD = 0,
    dwXCountChars: DWORD = 0,
    dwYCountChars: DWORD = 0,
    dwFillAttribute: DWORD = 0,
    dwFlags: DWORD = 0,
    wShowWindow: u16 = 0,
    cbReserved2: u16 = 0,
    lpReserved2: ?[*]u8 = null,
    hStdInput: ?HANDLE = null,
    hStdOutput: ?HANDLE = null,
    hStdError: ?HANDLE = null,
};

/// 进程信息结构体。用于 CreateProcessW()。
pub const ProcessInformation = extern struct {
    hProcess: HANDLE,
    hThread: HANDLE,
    dwProcessId: DWORD,
    dwThreadId: DWORD,
};


// ───────────────────────── 函数（按首次使用顺序） ─────────────────────────

/// 获取原始 UTF-16 命令行字符串。
pub extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]WCHAR;

/// 获取标准 IO 设备的句柄。
pub extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(.winapi) ?HANDLE;

/// 写入数据到文件或指定 IO 设备。
pub extern "kernel32" fn WriteFile(
	hFile: HANDLE,
	lpBuffer: [*]const u8,
	nNumberOfBytesToWrite: DWORD,
	lpNumberOfBytesWritten: ?*DWORD,
	lpOverlapped: ?*anyopaque
) callconv(.winapi) BOOL;

/// 以指定退出码退出当前进程。
pub extern "kernel32" fn ExitProcess(uExitCode: u32) callconv(.winapi) noreturn;

/// 创建并启动一个进程。
pub extern "kernel32" fn CreateProcessW(
	lpApplicationName: ?[*:0]const WCHAR,
	lpCommandLine: ?[*:0]WCHAR,
	lpProcessAttributes: ?*anyopaque,
	lpThreadAttributes: ?*anyopaque,
	bInheritHandles: BOOL,
	dwCreationFlags: DWORD,
	lpEnvironment: ?*anyopaque,
	lpCurrentDirectory: ?[*:0]const WCHAR,
	lpStartupInfo: *StartupInfoW,
	lpProcessInformation: *ProcessInformation,
) callconv(.winapi) BOOL;

/// 获取最近一次错误的错误码。
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;

/// 等待指定进程退出。
pub extern "kernel32" fn WaitForSingleObject(
	hHandle: HANDLE,
	dwMilliseconds: DWORD
) callconv(.winapi) DWORD;

/// 获取一个进程的退出码。
pub extern "kernel32" fn GetExitCodeProcess(
	hProcess: HANDLE,
	lpExitCode: *DWORD
) callconv(.winapi) BOOL;

/// 关闭一个句柄。
pub extern "kernel32" fn CloseHandle(handle: HANDLE) callconv(.winapi) BOOL;
