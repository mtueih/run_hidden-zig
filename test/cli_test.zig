// SPDX-License-Identifier: MIT
// Copyright (c) 2026 mtueih

//! CLI 集成测试：验证 `run_hidden` / `run_hidden_wait` 是否原样转发了命令行。
//!
//! 测试思路：
//!
//! 1. 把两个工具与参数记录器 `argv_echo` 复制到一个同时包含空格和中文的
//!    临时目录（顺带覆盖带引号的程序路径与 Unicode 路径）；
//! 2. 对每个用例，先用同一条命令行直接启动 `argv_echo` 作为参照，再通过
//!    `run_hidden_wait` 转发同一条命令行，最后比较两者写出的参数列表，
//!    并要求两者都与用例中硬编码的期望值一致；
//! 3. 另外验证退出码：`run_hidden_wait` 透传子进程退出码，`run_hidden`
//!    返回 0，两者在缺少参数时都返回 1。
//!
//! 所有子进程都以隐藏窗口方式启动，因此结果只能通过文件回传。

const std = @import("std");
const win32 = @import("win32");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;

const Case = struct {
    name: []const u8,
    /// 追加在 `<argv_echo> <out-file>` 之后的原始命令行片段。
    raw: []const u8,
    /// `argv_echo` 应当看到的参数（不含自身路径和输出文件路径）。
    expected: []const []const u8,
};

const cases = [_]Case{
    .{
        .name = "普通参数",
        .raw = "alpha beta gamma",
        .expected = &.{ "alpha", "beta", "gamma" },
    },
    .{
        .name = "带空格的参数",
        .raw = "\"hello world\" \"a b c\"",
        .expected = &.{ "hello world", "a b c" },
    },
    .{
        .name = "空参数",
        .raw = "\"\" \"\" x",
        .expected = &.{ "", "", "x" },
    },
    .{
        .name = "普通反斜杠",
        .raw = "C:\\foo\\bar\\\\ \\\\server\\share",
        .expected = &.{ "C:\\foo\\bar\\\\", "\\\\server\\share" },
    },
    .{
        .name = "带空格的 Windows 路径",
        .raw = "\"C:\\Program Files\\App\\app.exe\" \"C:\\Users\\me\\My Documents\\a.txt\"",
        .expected = &.{ "C:\\Program Files\\App\\app.exe", "C:\\Users\\me\\My Documents\\a.txt" },
    },
    .{
        // 偶数个反斜杠 + 引号：反斜杠减半，引号作为分隔符结束参数。
        .name = "引号前的双反斜杠（路径以反斜杠结尾）",
        .raw = "\"C:\\Program Files\\\\\"",
        .expected = &.{"C:\\Program Files\\"},
    },
    .{
        // 奇数个反斜杠 + 引号：引号被转义为字面量，参数一直延续到行尾。
        .name = "引号前的单反斜杠（未闭合的引号）",
        .raw = "\"C:\\Program Files\\\"",
        .expected = &.{"C:\\Program Files\""},
    },
    .{
        .name = "引号内的转义引号",
        .raw = "\"say \\\"hi\\\"\"",
        .expected = &.{"say \"hi\""},
    },
    .{
        .name = "引号外的转义引号",
        .raw = "a\\\"b",
        .expected = &.{"a\"b"},
    },
    .{
        .name = "引号内的转义引号（单个参数）",
        .raw = "\"a\\\"b\"",
        .expected = &.{"a\"b"},
    },
    .{
        // 3 个反斜杠 + 引号 => 1 个反斜杠 + 字面量引号。
        .name = "三个反斜杠加引号",
        .raw = "\"a\\\\\\\"b\"",
        .expected = &.{"a\\\"b"},
    },
    .{
        // 2 个反斜杠 + 引号 => 1 个反斜杠 + 切换引号状态。
        .name = "两个反斜杠加引号",
        .raw = "\\\\\"a b\"",
        .expected = &.{"\\a b"},
    },
    .{
        .name = "四个反斜杠加结束引号",
        .raw = "\"a\\\\\\\\\"",
        .expected = &.{"a\\\\"},
    },
    .{
        .name = "参数中间的引号",
        .raw = "a\"b c\"d",
        .expected = &.{"ab cd"},
    },
    .{
        // CRT 的怪癖：闭合引号后紧跟的引号会被保留为字面量引号。
        .name = "相邻的引号段",
        .raw = "\"a\"\"b\"",
        .expected = &.{"a\"b"},
    },
    .{
        .name = "空引号前缀",
        .raw = "\"\"x",
        .expected = &.{"x"},
    },
    .{
        .name = "连续四个引号",
        .raw = "\"\"\"\"",
        .expected = &.{"\""},
    },
    .{
        .name = "制表符分隔",
        .raw = "alpha\tbeta",
        .expected = &.{ "alpha", "beta" },
    },
    .{
        .name = "连续空格与制表符",
        .raw = "one     two\t\tthree",
        .expected = &.{ "one", "two", "three" },
    },
    .{
        .name = "Unicode 参数",
        .raw = "\"中文 参数\" emoji😀",
        .expected = &.{ "中文 参数", "emoji😀" },
    },
    .{
        .name = "只含一个空格的参数",
        .raw = "\" \"",
        .expected = &.{" "},
    },
    .{
        .name = "选项值带空格",
        .raw = "--opt=\"a b\" -x",
        .expected = &.{ "--opt=a b", "-x" },
    },
    .{
        .name = "引号内的双反斜杠路径",
        .raw = "\"C:\\dir\\\\sub dir\\file.txt\" C:\\dir\\\\sub\\file.txt",
        .expected = &.{ "C:\\dir\\\\sub dir\\file.txt", "C:\\dir\\\\sub\\file.txt" },
    },
    .{
        .name = "引号之外的连续反斜杠",
        .raw = "a\\\\b c\\\\",
        .expected = &.{ "a\\\\b", "c\\\\" },
    },
    .{
        .name = "末尾多余空格",
        .raw = "alpha   ",
        .expected = &.{"alpha"},
    },
    .{
        .name = "程序名后的多余空格",
        .raw = "   alpha beta",
        .expected = &.{ "alpha", "beta" },
    },
    .{
        .name = "程序名后的制表符",
        .raw = "\talpha beta",
        .expected = &.{ "alpha", "beta" },
    },
    .{
        .name = "字面量引号",
        .raw = "\\\"quoted\\\"",
        .expected = &.{"\"quoted\""},
    },
    .{
        .name = "参数中间的相邻引号",
        .raw = "a\"\"b",
        .expected = &.{"ab"},
    },
    .{
        .name = "单个反斜杠",
        .raw = "\\",
        .expected = &.{"\\"},
    },
    .{
        .name = "正斜杠路径",
        .raw = "C:/foo/bar \"C:/with space/x\"",
        .expected = &.{ "C:/foo/bar", "C:/with space/x" },
    },
};

extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 4) {
        std.debug.print("usage: cli_test <run_hidden> <run_hidden_wait> <argv_echo>\n", .{});
        return error.BadArguments;
    }

    const tool_path = try absolutePath(io, arena, args[1]);
    const wait_path = try absolutePath(io, arena, args[2]);
    const helper_path = try absolutePath(io, arena, args[3]);

    // 测试目录特意包含空格与中文，以覆盖带引号的程序路径。
    const temp = init.environ_map.get("TEMP") orelse init.environ_map.get("TMP") orelse ".";
    const dir_name = try std.fmt.allocPrint(arena, "run_hidden cli test {d}", .{GetCurrentProcessId()});
    const test_dir = try Dir.path.join(arena, &.{ temp, dir_name });
    try Dir.cwd().createDirPath(io, test_dir);
    defer {
        Dir.cwd().deleteTree(io, test_dir) catch {};
    }

    const tool_copy = try Dir.path.join(arena, &.{ test_dir, "工具 run_hidden.exe" });
    const wait_copy = try Dir.path.join(arena, &.{ test_dir, "工具 run_hidden_wait.exe" });
    const helper_copy = try Dir.path.join(arena, &.{ test_dir, "argv echo.exe" });
    try Dir.copyFileAbsolute(tool_path, tool_copy, io, .{});
    try Dir.copyFileAbsolute(wait_path, wait_copy, io, .{});
    try Dir.copyFileAbsolute(helper_path, helper_copy, io, .{});

    const tool_q = try quote(arena, tool_copy);
    const wait_q = try quote(arena, wait_copy);
    const helper_q = try quote(arena, helper_copy);

    var failures: usize = 0;

    for (cases, 0..) |case, index| {
        const suffix = try std.fmt.allocPrint(arena, "{d}", .{index});
        const out_ref = try Dir.path.join(arena, &.{ test_dir, try std.fmt.allocPrint(arena, "ref-{s}.bin", .{suffix}) });
        const out_tool = try Dir.path.join(arena, &.{ test_dir, try std.fmt.allocPrint(arena, "tool-{s}.bin", .{suffix}) });
        const out_ref_q = try quote(arena, out_ref);
        const out_tool_q = try quote(arena, out_tool);

        // 参照运行：直接用相同的原始命令行片段启动 argv_echo。
        const ref_cmd = try commandLine(arena, &.{ helper_q, out_ref_q, case.raw });
        const ref_code = runCommandLine(arena, ref_cmd) catch |err| {
            std.debug.print("FAIL [{s}] 参照运行失败: {s}\n", .{ case.name, @errorName(err) });
            failures += 1;
            continue;
        };
        if (ref_code != 0) {
            std.debug.print("FAIL [{s}] 参照运行退出码为 {d}\n", .{ case.name, ref_code });
            failures += 1;
            continue;
        }

        const ref_args = readRecordedArgs(io, arena, out_ref) catch |err| {
            std.debug.print("FAIL [{s}] 读取参照结果失败: {s}\n", .{ case.name, @errorName(err) });
            failures += 1;
            continue;
        };
        if (!sameArgs(ref_args, case.expected)) {
            std.debug.print("FAIL [{s}] 参照结果与期望不一致（测试用例本身有问题）\n", .{case.name});
            describeArgs("  期望", case.expected);
            describeArgs("  实际", ref_args);
            failures += 1;
            continue;
        }

        // 实际运行：经由 run_hidden_wait 转发同一条原始命令行片段。
        const tool_cmd = try commandLine(arena, &.{ wait_q, helper_q, out_tool_q, case.raw });
        const tool_code = runCommandLine(arena, tool_cmd) catch |err| {
            std.debug.print("FAIL [{s}] run_hidden_wait 运行失败: {s}\n", .{ case.name, @errorName(err) });
            failures += 1;
            continue;
        };
        if (tool_code != 0) {
            std.debug.print("FAIL [{s}] run_hidden_wait 退出码为 {d}\n", .{ case.name, tool_code });
            failures += 1;
            continue;
        }

        const tool_args = readRecordedArgs(io, arena, out_tool) catch |err| {
            std.debug.print("FAIL [{s}] 读取转发结果失败: {s}\n", .{ case.name, @errorName(err) });
            failures += 1;
            continue;
        };
        if (!sameArgs(tool_args, case.expected)) {
            std.debug.print("FAIL [{s}] 命令行转发结果不正确\n", .{case.name});
            describeArgs("  期望", case.expected);
            describeArgs("  实际", tool_args);
            failures += 1;
        }
    }

    // 退出码语义。
    failures += checkExitCode(arena, try commandLine(arena, &.{ wait_q, "cmd /c exit 7" }), 7, "run_hidden_wait 透传子进程退出码");
    failures += checkExitCode(arena, try commandLine(arena, &.{ tool_q, "cmd /c exit 7" }), 0, "run_hidden 成功启动后返回 0");
    failures += checkExitCode(arena, wait_q, 1, "run_hidden_wait 缺少参数时返回 1");
    failures += checkExitCode(arena, tool_q, 1, "run_hidden 缺少参数时返回 1");

    // 未被引号包裹的工具路径（仅当路径本身不含空白时才有意义）。
    if (std.mem.indexOfAny(u8, wait_path, " \t") == null) {
        const out = try Dir.path.join(arena, &.{ test_dir, "unquoted.bin" });
        const out_q = try quote(arena, out);
        const cmd = try commandLine(arena, &.{ wait_path, helper_q, out_q, "unquoted-tool alpha beta" });
        const code = runCommandLine(arena, cmd) catch |err| blk: {
            std.debug.print("FAIL [未加引号的工具路径] 运行失败: {s}\n", .{@errorName(err)});
            failures += 1;
            break :blk 1;
        };
        if (code != 0) {
            std.debug.print("FAIL [未加引号的工具路径] 退出码为 {d}\n", .{code});
            failures += 1;
        } else if (readRecordedArgs(io, arena, out)) |actual| {
            const expected: []const []const u8 = &.{ "unquoted-tool", "alpha", "beta" };
            if (!sameArgs(actual, expected)) {
                std.debug.print("FAIL [未加引号的工具路径] 命令行转发结果不正确\n", .{});
                describeArgs("  期望", expected);
                describeArgs("  实际", actual);
                failures += 1;
            }
        } else |err| {
            std.debug.print("FAIL [未加引号的工具路径] 读取结果失败: {s}\n", .{@errorName(err)});
            failures += 1;
        }
    } else {
        std.debug.print("SKIP [未加引号的工具路径] 路径包含空白: {s}\n", .{wait_path});
    }

    if (failures != 0) {
        std.debug.print("\n{d} 个测试失败\n", .{failures});
        return error.TestsFailed;
    }

    std.debug.print("全部测试通过（{d} 个命令行用例 + 退出码用例）\n", .{cases.len});
}

fn absolutePath(io: Io, arena: Allocator, path: []const u8) ![]const u8 {
    return Dir.cwd().realPathFileAlloc(io, path, arena);
}

/// 为路径加上双引号。测试中的路径均不含引号，且不会以反斜杠结尾。
fn quote(arena: Allocator, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "\"{s}\"", .{value});
}

fn commandLine(arena: Allocator, parts: []const []const u8) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    for (parts, 0..) |part, index| {
        if (index != 0) try list.append(arena, ' ');
        try list.appendSlice(arena, part);
    }
    return list.items;
}

/// 用原始命令行字符串启动一个进程，等待其结束并返回退出码。
fn runCommandLine(arena: Allocator, command_line: []const u8) !u32 {
    // CreateProcessW 要求可写缓冲区；utf8ToUtf16LeAllocZ 返回可变的 arena 内存。
    const command_line_w = try std.unicode.utf8ToUtf16LeAllocZ(arena, command_line);

    var startup_info: win32.StartupInfoW = .{
        .dwFlags = win32.STARTF_USESHOWWINDOW,
        .wShowWindow = win32.SW_HIDE,
    };
    var process_info: win32.ProcessInformation = undefined;

    if (win32.CreateProcessW(
        null,
        command_line_w.ptr,
        null,
        null,
        0,
        win32.CREATE_NO_WINDOW,
        null,
        null,
        &startup_info,
        &process_info,
    ) == 0) {
        std.debug.print("CreateProcessW 失败（错误码 {d}）：{s}\n", .{ win32.GetLastError(), command_line });
        return error.CreateProcessFailed;
    }
    defer {
        _ = win32.CloseHandle(process_info.hThread);
        _ = win32.CloseHandle(process_info.hProcess);
    }

    _ = win32.WaitForSingleObject(process_info.hProcess, win32.INFINITE);

    var exit_code: win32.DWORD = 0;
    _ = win32.GetExitCodeProcess(process_info.hProcess, &exit_code);
    return exit_code;
}

fn readRecordedArgs(io: Io, arena: Allocator, out_path: []const u8) ![]const []const u8 {
    const data = try Dir.cwd().readFileAlloc(io, out_path, arena, .unlimited);
    if (data.len < 4) return error.CorruptOutput;

    const count = std.mem.readInt(u32, data[0..4], .little);
    var result: std.ArrayList([]const u8) = .empty;
    var offset: usize = 4;

    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (data.len < offset + 4) return error.CorruptOutput;
        const length = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;

        if (data.len < offset + length) return error.CorruptOutput;
        try result.append(arena, data[offset..][0..length]);
        offset += length;
    }

    return result.items;
}

fn sameArgs(actual: []const []const u8, expected: []const []const u8) bool {
    if (actual.len != expected.len) return false;
    for (actual, expected) |a, e| {
        if (!std.mem.eql(u8, a, e)) return false;
    }
    return true;
}

fn describeArgs(label: []const u8, args: []const []const u8) void {
    std.debug.print("{s}（{d} 个）：", .{ label, args.len });
    for (args) |arg| {
        std.debug.print(" [{s}]", .{arg});
    }
    std.debug.print("\n", .{});
}

fn checkExitCode(arena: Allocator, command_line: []const u8, expected: u32, label: []const u8) usize {
    const actual = runCommandLine(arena, command_line) catch return 1;
    if (actual != expected) {
        std.debug.print("FAIL [{s}] 期望退出码 {d}，实际 {d}\n", .{ label, expected, actual });
        return 1;
    }
    return 0;
}
