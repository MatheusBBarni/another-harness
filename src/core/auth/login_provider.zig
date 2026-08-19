const std = @import("std");
const types = @import("../shared/types.zig");

pub const LoginProvider = enum {
    picker,
    grok,
    vercel,
};

pub const grok_default_model = "xai/grok-4.6";
pub const gateway_default_model = "zai/glm-5.2";

pub const LastLoginOwnership = struct {
    credential_source: types.CredentialSource,
    model: []const u8,
};

pub fn parseLoginProvider(rest: anytype) error{InvalidLoginProvider}!LoginProvider {
    if (rest.len == 0) return .picker;
    if (rest.len != 1) return error.InvalidLoginProvider;
    if (std.mem.eql(u8, rest[0], "grok")) return .grok;
    if (std.mem.eql(u8, rest[0], "vercel")) return .vercel;
    return error.InvalidLoginProvider;
}

pub fn lastLoginOwnership(provider: LoginProvider, previous_model: []const u8) LastLoginOwnership {
    return switch (provider) {
        .picker, .vercel => .{
            .credential_source = .fx_login,
            .model = restoreGatewayModel(previous_model),
        },
        .grok => .{
            .credential_source = .grok_oauth,
            .model = grok_default_model,
        },
    };
}

fn restoreGatewayModel(previous_model: []const u8) []const u8 {
    if (previous_model.len == 0 or std.mem.startsWith(u8, previous_model, "xai/grok-")) {
        return gateway_default_model;
    }
    return previous_model;
}

test "login grok and vercel skip the picker; unknown args fail" {
    try std.testing.expectEqual(LoginProvider.picker, try parseLoginProvider(&.{}));
    try std.testing.expectEqual(LoginProvider.grok, try parseLoginProvider(&.{"grok"}));
    try std.testing.expectEqual(LoginProvider.vercel, try parseLoginProvider(&.{"vercel"}));
    try std.testing.expectError(error.InvalidLoginProvider, parseLoginProvider(&.{"openai"}));
    try std.testing.expectError(error.InvalidLoginProvider, parseLoginProvider(&.{ "grok", "vercel" }));
}

test "last grok login selects grok_oauth and xai/grok-4.6" {
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
