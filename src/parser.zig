// @TODO:
//   - add option to ignore wrong arguments
//   - check that there are no same arguments present in the info structure
//   - add integer arguments?
//   - add unicode support?

const std = @import("std");

// @TODO: maybe this should be a tagged union to specify additional information
/// Supported argument types:
///   .bool - a flag, can be either set or not set
///   .string - a string value
pub const ArgumentType = enum {
    bool,
    string,
};

pub const ArgumentInfo = struct {
    /// An identified that will be used to access the results of
    /// the parsed arguments, will be created as a field in the result struct.
    field_name: [:0]const u8,

    /// The long name of an argument, can be set by a user like that:
    ///   --{long} for a boolean argument (a flag)
    ///   --{long}=Hello or --{long} Hello for a string argument
    long: ?[]const u8 = null,

    /// The short name of an argument made out of 1 ascii character,
    /// can be set like that:
    ///   -{short} for a boolean argument (a flag)
    ///   -{short} Hello or -{short}Hello for a string argument
    /// In a case of multiple flags these are equivalent:
    ///   -xvf === -x -v -f
    short: ?u8 = null,

    argument_type: ArgumentType,
};

pub const ParseError = error {
    /// Argument that was not specified in ArgumentInfo struct
    UnexpectedArgument,

    /// We expect to see a value for an argument
    UnspecifiedArgument,
};

pub fn ArgsParser(comptime config_arguments: []const ArgumentInfo) type {
    var arg_fields: [config_arguments.len]std.builtin.Type.StructField = undefined;
    for (&arg_fields, config_arguments) |*arg_field, arg| {
        if (arg.short != null and !std.ascii.isAlphanumeric(arg.short.?)) {
            @compileError("Short options should be alphanumeric");
        }

        if (arg.short == null and arg.long == null) {
            @compileError("A short or a long name should be specified");
        }

        const argument_type = switch (arg.argument_type) {
            .bool => bool,
            .string => ?[]const u8,
        };

        arg_field.* = .{
            .name = arg.field_name,
            .type = argument_type,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(argument_type),
        };
    }

    const ArgValues = @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = &arg_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        }
    });

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        /// A struct containing all parsed named arguments
        named_args: ArgValues,
        /// An array containing all position arguments
        positional_args: [][]const u8,

        /// Parses arguments and returns a struct containing them.
        /// The values of strings and such are views into the args array
        /// so they should not be altered or freed before arguments are no longer used.
        /// The allocator is used to store an array of positional arguments, and it is
        /// freed when deinit is called.
        pub fn parse(
            allocator: std.mem.Allocator,
            args: []const []const u8
        ) (ParseError||std.mem.Allocator.Error)!Self {
            var arg_values: ArgValues = undefined;

            // Initialize default values
            inline for (config_arguments) |arg| {
                @field(arg_values, arg.field_name) = switch (arg.argument_type) {
                    .bool => false,
                    else => null,
                };
            }

            var self = Self {
                .allocator = allocator,

                .named_args = arg_values,
                .positional_args = undefined,
            };

            var positional_args_builder = std.ArrayList([]const u8).init(allocator);

            var cursor: usize = 0;
            while (cursor < args.len) {
                const arg = args[cursor];

                // We encountered -- which means all following arguments are positional
                if (arg.len == 2 and std.mem.eql(u8, arg, "--")) {
                    cursor += 1;
                    while (cursor < args.len) : (cursor += 1) {
                        try positional_args_builder.append(args[cursor]);
                    }
                    break;
                } else if (arg.len >= 2 and arg[0] == '-' and arg[1] != '-') {
                    cursor += try self.parseShort(args, cursor);
                } else if (arg.len >= 3 and arg[0] == '-' and arg[1] == '-') {
                    cursor += try self.parseLong(args, cursor);
                } else {
                    try positional_args_builder.append(args[cursor]);
                    cursor += 1;
                }
            }

            self.positional_args = try positional_args_builder.toOwnedSlice();

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.positional_args);
            self.* = undefined;
        }

        fn parseShort(self: *Self, args: []const []const u8, index: usize) ParseError!usize {
            const short_options = args[index][1..];
            for (short_options, 0..) |option, option_index| {
                const argument_info = try findShortArgumentInfo(option);

                switch (argument_info.argument_type) {
                    .bool => {
                        try self.setBool(argument_info.field_name, true);
                    },
                    .string => {
                        // A string argument cannot go after boolean argument
                        if (option_index != 0) {
                            return error.UnexpectedArgument;
                        }

                        // Argument is set without whitespaces
                        if (option_index < short_options.len - 1) {
                            try self.setString(argument_info.field_name, short_options[option_index+1..]);
                            return 1;
                        } else { // Argument is set with a whitespace
                            // Next argument exists
                            if (index + 1 < args.len) {
                                try self.setString(argument_info.field_name, args[index + 1]);
                                return 2;
                            } else {
                                return error.UnspecifiedArgument;
                            }
                        }
                    },
                }
            }

            return 1;
        }

        fn parseLong(self: *Self, args: []const []const u8, index: usize) ParseError!usize {
            const option_raw = args[index][2..];
            const equal_sign_index = std.mem.indexOfScalar(u8, option_raw, '=');

            var option: []const u8 = undefined;
            if (equal_sign_index) |equal_sign_index_value|
            {
                // The equal sign is at the end of the argument like '{arg}= '
                if (equal_sign_index_value == option_raw.len) {
                    return error.UnspecifiedArgument;
                }

                option = option_raw[0..equal_sign_index.?];
            } else {
                option = option_raw;
            }

            const argument_info = try findLongArgumentInfo(option);
            switch (argument_info.argument_type) {
                .bool => {
                    if (equal_sign_index != null) {
                        return error.UnexpectedArgument;
                    }

                    try self.setBool(argument_info.field_name, true);
                    return 1;
                },
                .string => {
                    if (equal_sign_index != null) {
                        if (equal_sign_index.? >= option_raw.len - 1) {
                            return error.UnspecifiedArgument;
                        }

                        try self.setString(argument_info.field_name, option_raw[equal_sign_index.?+1..]);

                        return 1;
                    } else {
                        if (index + 1 < args.len) {
                            try self.setString(argument_info.field_name, args[index + 1]);
                            return 2;
                        } else {
                            return error.UnspecifiedArgument;
                        }
                    }
                },
            }

            return 1;
        }

        fn findShortArgumentInfo(argument_name: u8) ParseError!ArgumentInfo {
            inline for (config_arguments) |config_argument| {
                if (config_argument.short != null and
                    config_argument.short.? == argument_name) {
                    return config_argument;
                }
            }

            return error.UnexpectedArgument;
        }

        fn findLongArgumentInfo(argument_name: []const u8) ParseError!ArgumentInfo {
            inline for (config_arguments) |config_argument| {
                if (config_argument.long != null and
                    std.mem.eql(u8, config_argument.long.?, argument_name)) {
                    return config_argument;
                }
            }

            return error.UnexpectedArgument;
        }

        fn setBool(self: *Self, name: []const u8, value: bool) ParseError!void {
            inline for (config_arguments) |config_argument| {
                if (@TypeOf(@field(self.named_args, config_argument.field_name)) == bool) {
                    if (std.mem.eql(u8, config_argument.field_name, name)) {
                        @field(self.named_args, config_argument.field_name) = value;
                        return;
                    }
                }
            }

            return error.UnexpectedArgument;
        }

        fn setString(self: *Self, name: []const u8, value: []const u8) ParseError!void {
            inline for (config_arguments) |config_argument| {
                if (@TypeOf(@field(self.named_args, config_argument.field_name)) == ?[]const u8) {
                    if (std.mem.eql(u8, config_argument.field_name, name)) {
                        @field(self.named_args, config_argument.field_name) = value;
                        return;
                    }
                }
            }

            return error.UnexpectedArgument;
        }
    };
}
