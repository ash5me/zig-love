const std = @import("std");

pub fn build(b: *std.Build) void {
    const entt = b.dependency("entt", .{});
    const target = b.standardTargetOptions(.{});
    const production = b.option(bool, "production", "Build the native library with ReleaseFast") orelse false;
    const optimize = if (production) .ReleaseFast else b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src_zig/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("ecs", entt.module("zig-ecs"));
    const lib = b.addLibrary(.{
        .name = "game_systems",
        .root_module = root_module,
        .linkage = .dynamic,
    });

    b.installArtifact(lib);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src_zig/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("ecs", entt.module("zig-ecs"));
    const engine_tests = b.addTest(.{ .root_module = test_module });
    const test_step = b.step("test", "Run native engine tests");
    test_step.dependOn(&b.addRunArtifact(engine_tests).step);

    const release_step = b.step("release", "Build the optimized native library");
    release_step.dependOn(b.getInstallStep());

    const cross_optimize = b.option(bool, "cross-release", "Optimize cross-target verification builds") orelse true;
    const cross_mode: std.builtin.OptimizeMode = if (cross_optimize) .ReleaseFast else .Debug;
    const windows_module = b.createModule(.{
        .root_source_file = b.path("src_zig/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }),
        .optimize = cross_mode,
    });
    windows_module.addImport("ecs", entt.module("zig-ecs"));
    const linux_module = b.createModule(.{
        .root_source_file = b.path("src_zig/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu }),
        .optimize = cross_mode,
        .link_libc = true,
    });
    linux_module.addImport("ecs", entt.module("zig-ecs"));
    const macos_module = b.createModule(.{
        .root_source_file = b.path("src_zig/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .macos, .abi = .none }),
        .optimize = cross_mode,
        .link_libc = true,
    });
    macos_module.addImport("ecs", entt.module("zig-ecs"));
    const windows_lib = b.addLibrary(.{ .name = "game_systems_windows", .root_module = windows_module, .linkage = .dynamic });
    const linux_lib = b.addLibrary(.{ .name = "game_systems_linux", .root_module = linux_module, .linkage = .dynamic });
    const macos_lib = b.addLibrary(.{ .name = "game_systems_macos", .root_module = macos_module, .linkage = .dynamic });
    const cross_windows = b.step("cross-windows", "Verify the Windows DLL ABI");
    const cross_linux = b.step("cross-linux", "Verify the Linux shared-library ABI");
    const cross_macos = b.step("cross-macos", "Verify the macOS dynamic-library ABI");
    cross_windows.dependOn(&windows_lib.step);
    cross_linux.dependOn(&linux_lib.step);
    cross_macos.dependOn(&macos_lib.step);
}
