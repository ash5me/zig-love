const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const production = b.option(bool, "production", "Build the native library with ReleaseFast") orelse false;
    const optimize = if (production) .ReleaseFast else b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "game_systems",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src_zig/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    b.installArtifact(lib);

    const release_step = b.step("release", "Build the optimized native library");
    release_step.dependOn(b.getInstallStep());
}
