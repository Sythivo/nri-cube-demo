const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nri_dep = b.dependency("nri", .{
        .target = target,
        .optimize = optimize,
    });
    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });
    const zmath_dep = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });

    const vulkan12_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv64,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        .os_tag = .vulkan,
        .ofmt = .spirv,
    });
    const shader_mod = b.createModule(.{
        .target = vulkan12_target,
        .optimize = .ReleaseFast,
        .root_source_file = b.path("src/shaders/cube.zig"),
    });
    const shader = b.addObject(.{
        .name = "shader",
        .root_module = shader_mod,
        .use_llvm = false,
        .use_lld = false,
    });

    shader_mod.addImport("zmath", zmath_dep.module("root"));

    const shader_step = b.addInstallFile(shader.getEmittedBin(), "../src/shaders/cube.spv");

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    main_mod.addImport("nri", nri_dep.module("root"));
    main_mod.addImport("zglfw", zglfw_dep.module("root"));
    main_mod.addImport("zmath", zmath_dep.module("root"));
    main_mod.linkLibrary(zglfw_dep.artifact("glfw"));

    const exe = b.addExecutable(.{
        .name = "nri_game_demo",
        .root_module = main_mod,
    });

    exe.step.dependOn(&shader_step.step);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
