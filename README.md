# About
A pretty simple zig argument parser that uses compile-time stuff

Examples of argument passing syntax can be found tests in main.zig, here's a quick overview:

- `-ab` or `-a -b` for short boolean arguments
- `--first --second` for long boolean arguments
- `-aHelloWorld` for short string arguments
- `-a HelloWorld` for short string arguments
- `--first HelloWorld` for long string arguments
- `--first=HelloWorld` for long string arguments with an equal sign
- `hello --first=something world` for positional arguments will parse as `{"hello", "world"}`

# Usage example
```zig
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

```
