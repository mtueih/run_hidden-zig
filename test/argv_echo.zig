// SPDX-License-Identifier: ISC
// Copyright (c) 2026 mtueih

//! 集成测试用的参数记录器。
//!
//! 用法：`argv_echo <out-file> [args...]`
//!
//! 把 `args[2..]`（也就是除自身路径与输出文件路径之外的参数）序列化到
//! `<out-file>`：
//!
//! ```text
//! u32 参数个数
//! 重复「参数个数」次：
//!     u32 参数字节数
//!     UTF-8 参数内容
//! ```
//!
//! 所有整数均为小端序。之所以写文件而不是标准输出，是因为 `run_hidden`
//! 以隐藏窗口方式启动子进程，标准输出没有可用的控制台。

const std = @import("std");

fn appendU32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buffer: [4]u8 = undefined;
    std.mem.writeInt(u32, &buffer, value, .little);
    try list.appendSlice(allocator, &buffer);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    // args[0] 是自身路径，args[1] 是输出文件路径。
    if (args.len < 2) return error.MissingOutputPath;

    var data: std.ArrayList(u8) = .empty;
    const forwarded = args[2..];

    try appendU32(&data, arena, @intCast(forwarded.len));
    for (forwarded) |arg| {
        try appendU32(&data, arena, @intCast(arg.len));
        try data.appendSlice(arena, arg);
    }

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = args[1],
        .data = data.items,
    });
}
