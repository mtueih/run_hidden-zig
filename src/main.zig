// SPDX-License-Identifier: ISC
// Copyright (c) 2026 mtueih

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const win32 = @import("win32.zig");


// 用一个极简的 trap 替换默认的 panic 处理程序（默认处理程序会连带引入栈回溯、
// stderr 加锁以及格式化相关的代码），从而保持二进制文件体积小巧。
pub const panic = std.debug.no_panic;


/// 判断一个宽字符是否是空白字符（针对 Windows 命令行解析逻辑，只包含空格和制表符）。
fn isWhitespaceW(ch: win32.WCHAR) bool {
	return ch == ' ' or ch == '\t';
}

/// 获取原始 UTF-16 命令行字符串的参数部分
/// （除第一个 token 以外的部分，从第二个 token 的起始位置开始）。
/// 先借助 Windows API 函数 GetCommandLineW() 获取原始 UTF-16 命令行字符串，
/// 再定位到第二个 token 起始处。
fn getCmdLine() [*:0]win32.WCHAR {
	// 获取原始 UTF-16 命令行字符串。
	var cursor: [*:0]win32.WCHAR = win32.GetCommandLineW();

	// 定位第二个 token 的起始位置。
	// 如果第一个字符是双引号，则查找到下一个双引号的后一个位置处；
	// 否则，查找到第一个空白字符的位置处。
	if (cursor[0] == '"') {
		// 跳过第一个双引号。
		cursor += 1;

		// 遇到 '\0' 或第二个双引号时停止。
		while (cursor[0] != 0 and cursor[0] != '"') : (cursor += 1) {}

		// 如果是遇到双引号停止的，就跳过这个双引号，让指针指向双引号的后一个位置。
		if (cursor[0] == '"') cursor += 1;
	} else {
		while (cursor[0] != 0 and !isWhitespaceW(cursor[0])) : (cursor += 1) {}
	}

	// 然后，查找到第一个非空白字符的位置处。
	while (isWhitespaceW(cursor[0])) : (cursor += 1) {}

	return cursor;
}

/// 输出一条消息到标准错误流。
fn putErr(msg: []const u8) void {
	// 获取标准错误设备句柄。
	const errHandle = win32.GetStdHandle(win32.STD_ERROR_HANDLE) orelse return;

	// 用于辅助完成调用的变量，实际用不到，但需要。
	var writtenLen: win32.DWORD = undefined;

	// 向标准错误流写入消息。
	_ = win32.WriteFile(
		errHandle, msg.ptr, @intCast(msg.len),
		&writtenLen,
		null
	);
}


// 这是 Windows PE 的启动符号。定义它可以阻止 std.start 安装其
// 用于解码参数的启动例程。
pub export fn wWinMainCRTStartup() callconv(.winapi) noreturn {
	// 获取原始 UTF-16 命令行字符串的参数部分（除第一个 token 以外的部分）。
	const cmdLine = getCmdLine();

	// 如果 cmdLine 以 0 开头，说明有效 token 数小于 2，此时报错并退出。
	if (cmdLine[0] == 0) {
		// 仅在 debug 构建模式下打印错误消息。
		if (builtin.mode == .debug) putErr("Insufficient parameters.\r\n");

		// 以 1 退出码退出。
		win32.ExitProcess(1);
	}

	// 声明并初始化一个 StartupInfoW 结构体，指定以隐藏窗口方式启动。
    var si: win32.StartupInfoW = .{
	    .dwFlags = win32.STARTF_USESHOWWINDOW,
	    .wShowWindow = win32.SW_HIDE,
    };
	// 声明一个 ProcessInformation 结构体。
    var pi: win32.ProcessInformation = undefined;

	// 调用 CreateProcessW() 函数创建进程。
    if (win32.CreateProcessW(
        null, cmdLine,
        null, null, 0,
        win32.CREATE_NO_WINDOW,
        null, null,
        &si, &pi,
    ) == 0) {
	    // 获取错误码。
        const errCode = win32.GetLastError();

	    // 仅在 debug 构建模式下打印错误消息。
	    if (builtin.mode == .debug) putErr("CreateProcessW failed.\r\n");

	    // 以错误码或 1（当错误码为 0 时）退出进程。
        win32.ExitProcess(if (errCode == 0) 1 else errCode);
    }

	// 声明并初始化退出码为 0。
    var exitCode: win32.DWORD = 0;

	// 编译期构建选项，是否等待目标进程退出。如果是，则等待。
    if (build_options.wait) {
	    // 等待目标进程退出。
        _ = win32.WaitForSingleObject(pi.hProcess, win32.INFINITE);

		// 获取目标进程退出码。
        _ = win32.GetExitCodeProcess(pi.hProcess, &exitCode);
    }

	// 关闭进程句柄。
    _ = win32.CloseHandle(pi.hProcess);
	// 关闭线程句柄。
    _ = win32.CloseHandle(pi.hThread);

	// 以目标进程退出码或 0 退出。
    win32.ExitProcess(exitCode);
}
