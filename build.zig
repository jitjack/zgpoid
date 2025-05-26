const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gpiod_lib = b.addStaticLibrary(.{
        .name = "gpoid",
        .target = target,
        .optimize = optimize,
    });
    gpiod_lib.linkLibC();

    gpiod_lib.root_module.addCMacro("GPIOD_VERSION_STR", "\"2.3\"");
    gpiod_lib.addIncludePath(b.path("src/deps/libgpiod/include"));
    gpiod_lib.addIncludePath(b.path("src/deps/libgpiod/lib"));
    gpiod_lib.addCSourceFiles(.{
        .root = b.path("src/deps/libgpiod/lib"),
        .files = &.{
            "chip.c",
            "chip-info.c",
            "edge-event.c",
            "info-event.c",
            "internal.c",
            "line-config.c",
            "line-info.c",
            "line-request.c",
            "line-settings.c",
            "misc.c",
            "request-config.c",
        },
        .flags = &.{
            "-std=gnu89",
        },
    });
    gpiod_lib.installHeader(b.path("src/deps/libgpiod/include/gpiod.h"), "gpiod.h");
    b.installArtifact(gpiod_lib);

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addStaticLibrary(.{
        .name = "zgpiod",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibrary(gpiod_lib);
    lib.linkLibC();
    b.installArtifact(lib);

    buildExamples(b, lib, gpiod_lib, target, optimize);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    lib_unit_tests.linkLibrary(gpiod_lib);
    lib_unit_tests.linkLibC();
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

fn buildExamples(
    b: *std.Build,
    zgpiod_lib: *std.Build.Step.Compile,
    gpiod_lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const examples_step = b.step("examples", "Build all examples");

    var examples_dir = std.fs.cwd().openDir("src/examples", .{ .iterate = true }) catch |err| {
        std.debug.print("Could not open examples directory: {}\n", .{err});
        return;
    };
    defer examples_dir.close();

    var it = examples_dir.iterate();
    while (it.next() catch |err| {
        std.debug.print("Error iterating examples directory: {}\n", .{err});
        return;
    }) |entry| {
        // Skip non-Zig files and directories
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) {
            continue;
        }

        const example_name = entry.name[0 .. entry.name.len - 4];
        var buffer: [1028]u8 = .{0} ** 1028;
        const f_name = std.fmt.bufPrintZ(&buffer, "src/examples/{s}", .{entry.name}) catch |err| {
            std.log.err("bad buf: {}\n", .{err});
            return;
        };
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(buffer[0..f_name.len :0]),
            .target = target,
            .optimize = optimize,
        });

        example.root_module.addImport("zgpiod", zgpiod_lib.root_module);

        example.linkLibrary(zgpiod_lib);
        example.linkLibrary(gpiod_lib);
        example.linkLibC();

        b.installArtifact(example);

        const run_example = b.addRunArtifact(example);
        run_example.step.dependOn(b.getInstallStep());

        var buf2: [1028]u8 = .{0} ** 1028;
        const run_name = std.fmt.bufPrintZ(&buffer, "run-{s}", .{example_name}) catch "run-???";
        const run_desc = std.fmt.bufPrintZ(&buf2, "Run the {s} example", .{example_name}) catch "run desc ???";
        const run_step = b.step(buffer[0..run_name.len :0], buf2[0..run_desc.len :0]);
        run_step.dependOn(&run_example.step);

        examples_step.dependOn(&example.step);
    }
}
