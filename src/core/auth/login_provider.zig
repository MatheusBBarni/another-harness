const std = @import("std");

pub const LoginProvider = enum {
    picker,
    grok,
    vercel,
};

pub fn parseLoginProvider(rest: []const []const u8) error{InvalidLoginProvider}!LoginProvider {
    if (rest.len == 0) return .picker;
    if (rest.len != 1) return error.InvalidLoginProvider;
    if (std.mem.eql(u8, rest[0], "grok")) return .grok;
    if (std.mem.eql(u8, rest[0], "vercel")) return .vercel;
    return error.InvalidLoginProvider;
}

test "login grok and vercel skip the picker; unknown args fail" {
    try std.testing.expectEqual(LoginProvider.picker, try parseLoginProvider(&.{}));
    try std.testing.expectEqual(LoginProvider.grok, try parseLoginProvider(&.{"grok"}));
    try std.testing.expectEqual(LoginProvider.vercel, try parseLoginProvider(&.{"vercel"}));
    try std.testing.expectError(error.InvalidLoginProvider, parseLoginProvider(&.{"openai"}));
    try std.testing.expectError(error.InvalidLoginProvider, parseLoginProvider(&.{ "grok", "vercel" }));
}
