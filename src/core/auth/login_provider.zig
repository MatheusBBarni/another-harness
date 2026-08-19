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

test "last grok login selects grok_oauth and xai/grok-4.6" {
    const types = @import("../shared/types.zig");
    const grok = lastLoginOwnership(.grok, "zai/glm-5.2");
    try std.testing.expectEqual(types.CredentialSource.grok_oauth, grok.credential_source);
    try std.testing.expectEqualStrings("xai/grok-4.6", grok.model);

    const vercel_from_grok = lastLoginOwnership(.vercel, "xai/grok-4.6");
    try std.testing.expectEqual(types.CredentialSource.fx_login, vercel_from_grok.credential_source);
    try std.testing.expectEqualStrings("zai/glm-5.2", vercel_from_grok.model);

    const vercel_keep = lastLoginOwnership(.vercel, "anthropic/claude-sonnet");
    try std.testing.expectEqual(types.CredentialSource.fx_login, vercel_keep.credential_source);
    try std.testing.expectEqualStrings("anthropic/claude-sonnet", vercel_keep.model);
}
