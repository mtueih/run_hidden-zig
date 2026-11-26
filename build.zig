const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    if (target.result.os.tag != .windows) @panic("run_hidden only supports Windows targets.");

    // 本项目主要使用两种构建模式：开发阶段用 Debug（不带参数时的默认值），
    // 发布用 ReleaseFast（zig build -Doptimize=ReleaseFast，本工具的性质决定
    // 了速度比体积更重要）。其他模式（如 ReleaseSmall）同样可用。
    const optimize = b.standardOptimizeOption(.{});

    // 调试信息默认保留：所有模式（ReleaseSmall 除外）都会生成 .pdb 并安装到
    // zig-out/bin。发布时若不需要符号文件，传 -Dstrip=true 即可同时去掉
    // exe 内的调试记录和 .pdb（Zig 0.17 不再内置该选项，需在此声明）。
    const strip = b.option(bool, "strip", "Remove debug info and do not emit .pdb");

    addTool(b, target, optimize, strip, "run_hidden", false);
    addTool(b, target, optimize, strip, "run_hidden_wait", true);
}

fn addTool(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: ?bool,
    name: []const u8,
    wait: bool,
) void {
    const options = b.addOptions();
    options.addOption(bool, "wait", wait);

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = strip,
    });
    root_module.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = root_module,
    });

    // 指定 Windows（GUI）子系统：PE 头 Subsystem 字段将写为 IMAGE_SUBSYSTEM_WINDOWS_GUI，
    // 启动时不再分配控制台窗口（等效于 MSVC 的 /SUBSYSTEM:WINDOWS）。
    // 注意：入口符号 wWinMainCRTStartup 只是一个符号名，决定是否分配控制台的是该字段。
    exe.subsystem = .windows;

    b.installArtifact(exe);
}
