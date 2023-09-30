const std = @import("std");

// Try to get directory and default to current directory if string not provided
fn getTargetDirectory(dir_string: ?*const []const u8) !std.fs.Dir {
    if (dir_string) |path| {
        if (std.fs.path.isAbsolute(path.*)) {
            return try std.fs.openDirAbsolute(path.*, .{});
        } else {
            return std.fs.cwd().openDir(path.*, .{});
        }
    } else {
        return std.fs.cwd();
    }
}

fn subDirectoryExists(directory: std.fs.Dir, subdir: []const u8) bool {
    var dir = directory.openDir(subdir, .{}) catch {
        return false;
    };
    dir.close();
    return true;
}

const BuildType = enum {
    Lib,
    Exe,
};

const Options = struct {
    build_type: BuildType = BuildType.Exe,
    clean: bool = false,
};

const OptionType = enum {
    lib,
    exe,
    clean,
};

pub fn parseOption(options: *Options, arg: []const u8) void {
    const option_enum = std.meta.stringToEnum(OptionType, arg) orelse return;
    switch (option_enum) {
        OptionType.lib => options.build_type = BuildType.Lib,
        OptionType.exe => options.build_type = BuildType.Exe,
        OptionType.clean => options.clean = true,
    }
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var options: Options = .{};

    var project_name: ?*const [:0]const u8 = null;
    var path_name: ?*const [:0]const u8 = null;
    // Skip program name
    for (args[1..]) |arg| {
        // Long option
        if (arg.len > 2 and std.mem.eql(u8, arg[0..2], "--")) {
            parseOption(&options, arg[2..]);
        } else {
            if (project_name == null) {
                project_name = &arg;
            } else {
                path_name = &arg;
            }
        }
    }

    if (project_name == null) {
        try stderr.print("No project name specified", .{});
        return error.InvalidProjectName;
    }

    var project_parent_dir = getTargetDirectory(path_name) catch |err| {
        try stderr.print("Unable to open directory: {s}\n", .{project_name.?.*});
        return err;
    };
    defer project_parent_dir.close();

    try stdout.print("Creating {s}\n", .{project_name.?.*});

    if (subDirectoryExists(project_parent_dir, project_name.?.*)) {
        if (options.clean == true) {
            try project_parent_dir.deleteTree(project_name.?.*);
        } else {
            try stderr.print("Unable to create new directory, path already exists\n", .{});
            return error.PathAlreadyExists;
        }
    }

    var project_dir = project_parent_dir.makeOpenPath(project_name.?.*, .{}) catch |err| {
        try stderr.print("Error: Unable to create directory: {s}\n", .{path_name.?.*});
        return err;
    };
    defer project_dir.close();

    var out_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.getFdPath(project_dir.fd, &out_buffer);
    const build_type = if (options.build_type == BuildType.Lib) "init-lib" else "init-exe";
    const child_args = [_][]const u8{ "zig", build_type };
    var child = std.ChildProcess.init(&child_args, allocator);

    child.cwd = path;
    const term = try child.spawnAndWait();
    _ = term;
}
