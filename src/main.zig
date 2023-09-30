const std = @import("std");

// Try to get directory and default to current directory if string not provided
fn getTargetDirectory(dir_string: ?[]const u8) !std.fs.Dir {
    if (dir_string) |path| {
        if (std.fs.path.isAbsolute(path)) {
            return try std.fs.openDirAbsolute(path, .{});
        } else {
            return std.fs.cwd().openDir(path, .{});
        }
    } else {
        return std.fs.cwd();
    }
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const program_name = args.next(); // skip program name
    _ = program_name;

    const project_name = args.next() orelse {
        try stderr.print("No project name specified", .{});
        return error.InvalidProjectName;
    };
    try stdout.print("Creating {s}\n", .{project_name});

    const project_path_arg = args.next();
    var project_parent_dir = getTargetDirectory(project_path_arg) catch |err| {
        try stderr.print("Unable to open directory: {s}\n", .{project_path_arg.?});
        return err;
    };
    defer project_parent_dir.close();

    const project_dir = project_parent_dir.makeOpenPath(project_name, .{}) catch |err| {
        try stderr.print("Error: Unable to create directory: {s}\n", .{project_path_arg.?});
        return err;
    };

    var out_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.getFdPath(project_dir.fd, &out_buffer);
    const child_args = [_][]const u8{ "zig", "init-exe" };
    var child = std.ChildProcess.init(&child_args, allocator);

    child.cwd = path;
    const term = try child.spawnAndWait();
    _ = term;
}
