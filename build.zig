const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    if (target.result.os.tag != .windows) @panic("run_hidden only supports Windows targets.");

    // 本项目主要使用两种构建模式：开发阶段用 Debug（不带参数时的默认值），
    // 发布用 ReleaseFast（zig build -Doptimize=ReleaseFast，本工具的性质决定
    // 了速度比体积更重要）。其他模式（如 ReleaseSmall）同样可用。
    const optimize = b.standardOptimizeOption(.{});

    addTool(b, target, optimize, "run_hidden", false);
    addTool(b, target, optimize, "run_hidden_wait", true);
}

fn addTool(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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
    });
    root_module.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = root_module,
    });
    b.installArtifact(exe);
}
