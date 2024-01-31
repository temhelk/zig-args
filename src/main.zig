const std = @import("std");
const args_parser = @import("parser.zig");

const ArgsParserExample = args_parser.ArgsParser(
    &[_] args_parser.ArgumentInfo {
        .{ .field_name = "speed", .long = "speed", .short = 's', .argument_type = .bool },
        .{ .field_name = "path", .long = "path", .short = 'p', .argument_type = .string },
    }
);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = ArgsParserExample.parse(allocator, args[1..]) catch {
        std.log.warn("Wrong arguments", .{});
        std.os.exit(1);
    };
    defer parser.deinit();

    if (parser.named_args.speed) {
        std.debug.print("Speed mode!\n", .{});
    } else {
        std.debug.print("Slow mode :(\n", .{});
    }

    if (parser.named_args.path) |path| {
        std.debug.print("Path: {s}\n", .{path});
    }

    std.debug.print("Positional: ", .{});
    for (parser.positional_args) |arg| {
        std.debug.print("'{s}' ", .{arg});
    }
    std.debug.print("\n", .{});
}

test "Bool arguments" {
    const allocator = std.testing.allocator;

    const ArgsParser = args_parser.ArgsParser(
        &[_] args_parser.ArgumentInfo {
            .{ .field_name = "first", .long = "first", .short = 'f', .argument_type = .bool },
            .{ .field_name = "second", .long = "second", .short = 's', .argument_type = .bool },
        }
    );

    { // Empty bool arguments
        const args: []const []const u8 = &[_][]const u8 {
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqual(false, parser.named_args.first);
        try std.testing.expectEqual(false, parser.named_args.second);
    }
    { // Short arguments separate
        const args: []const []const u8 = &[_][]const u8 {
            "-f", "-s",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqual(true, parser.named_args.first);
        try std.testing.expectEqual(true, parser.named_args.second);
    }
    { // Short arguments together
        const args: []const []const u8 = &[_][]const u8 {
            "-fs",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqual(true, parser.named_args.first);
        try std.testing.expectEqual(true, parser.named_args.second);
    }
    { // Short arguments one set
        const args: []const []const u8 = &[_][]const u8 {
            "-f",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqual(true, parser.named_args.first);
        try std.testing.expectEqual(false, parser.named_args.second);
    }
    { // Long arguments
        const args: []const []const u8 = &[_][]const u8 {
            "--first", "--second",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqual(true, parser.named_args.first);
        try std.testing.expectEqual(true, parser.named_args.second);
    }
    { // Short and long
        const args: []const []const u8 = &[_][]const u8 {
            "-f", "--second",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqual(true, parser.named_args.first);
        try std.testing.expectEqual(true, parser.named_args.second);
    }
}

test "String arguments" {
    const allocator = std.testing.allocator;

    const ArgsParser = args_parser.ArgsParser(
        &[_] args_parser.ArgumentInfo {
            .{ .field_name = "first", .long = "first", .short = 'f', .argument_type = .string },
            .{ .field_name = "second", .long = "second", .short = 's', .argument_type = .string },
        }
    );

    { // Short arguments separate
        const args: []const []const u8 = &[_][]const u8 {
            "-f", "hello_there",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqualSlices(u8, "hello_there", parser.named_args.first.?);
        try std.testing.expectEqual(null, parser.named_args.second);
    }
    { // Short arguments together
        const args: []const []const u8 = &[_][]const u8 {
            "-fhello_there",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqualSlices(u8, "hello_there", parser.named_args.first.?);
        try std.testing.expectEqual(null, parser.named_args.second);
    }
    { // Long arguments
        const args: []const []const u8 = &[_][]const u8 {
            "--second", "hello_there",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqual(null, parser.named_args.first);
        try std.testing.expectEqualSlices(u8, "hello_there", parser.named_args.second.?);
    }
}

test "Positional arguments" {
    const allocator = std.testing.allocator;

    const ArgsParser = args_parser.ArgsParser(
        &[_] args_parser.ArgumentInfo {
            .{ .field_name = "arg", .long = "arg", .short = 'a', .argument_type = .string },
        }
    );

    {
        const args: []const []const u8 = &[_][]const u8 {
            "first", "--arg", "hello_there", "second", "third",
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqualSlices(u8, "hello_there", parser.named_args.arg.?);
        try std.testing.expectEqualDeep(
            &[_][]const u8 { "first", "second", "third" },
            parser.positional_args
        );
    }
}

test "Empty string arguments" {
    const allocator = std.testing.allocator;

    const ArgsParser = args_parser.ArgsParser(
        &[_] args_parser.ArgumentInfo {
            .{ .field_name = "arg", .long = "arg", .short = 'a', .argument_type = .string },
        }
    );

    {
        const args: []const []const u8 = &[_][]const u8 {
            "--arg", ""
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqualSlices(u8, "", parser.named_args.arg.?);
    }
    {
        const args: []const []const u8 = &[_][]const u8 {
            "-a", ""
        };

        var parser = try ArgsParser.parse(allocator, args);
        defer parser.deinit();

        try std.testing.expectEqualSlices(u8, "", parser.named_args.arg.?);
    }
}

test "Errors" {
    const allocator = std.testing.allocator;

    const ArgsParser = args_parser.ArgsParser(
        &[_] args_parser.ArgumentInfo {
            .{ .field_name = "arg", .long = "arg", .short = 'a', .argument_type = .string },
            .{ .field_name = "arg2", .long = "arg2", .short = 'b', .argument_type = .bool },
        }
    );

    { // String short argument after boolean arguments
        const args: []const []const u8 = &[_][]const u8 {
            "-ba"
        };

        const parser = ArgsParser.parse(allocator, args);
        try std.testing.expectError(error.UnexpectedArgument, parser);
    }
    { // Short boolean argument with an equal sign
        const args: []const []const u8 = &[_][]const u8 {
            "-b="
        };

        const parser = ArgsParser.parse(allocator, args);
        try std.testing.expectError(error.UnexpectedArgument, parser);
    }
    { // Long boolean argument with an equal sign
        const args: []const []const u8 = &[_][]const u8 {
            "--arg2="
        };

        const parser = ArgsParser.parse(allocator, args);
        try std.testing.expectError(error.UnexpectedArgument, parser);
    }
    { // Short unknown argument
        const args: []const []const u8 = &[_][]const u8 {
            "-u"
        };

        const parser = ArgsParser.parse(allocator, args);
        try std.testing.expectError(error.UnexpectedArgument, parser);
    }
    { // Long unknown argument
        const args: []const []const u8 = &[_][]const u8 {
            "--unknown"
        };

        const parser = ArgsParser.parse(allocator, args);
        try std.testing.expectError(error.UnexpectedArgument, parser);
    }
    { // Short string argument without any value
        const args: []const []const u8 = &[_][]const u8 {
            "-a"
        };

        const parser = ArgsParser.parse(allocator, args);
        try std.testing.expectError(error.UnspecifiedArgument, parser);
    }
    { // Long string argument without any value
        const args: []const []const u8 = &[_][]const u8 {
            "--arg"
        };

        const parser = ArgsParser.parse(allocator, args);
        try std.testing.expectError(error.UnspecifiedArgument, parser);
    }
    { // Long string argument with an equal sign but without any value
        const args: []const []const u8 = &[_][]const u8 {
            "--arg=", "something",
        };

        const parser = ArgsParser.parse(allocator, args);
        try std.testing.expectError(error.UnspecifiedArgument, parser);
    }
}
