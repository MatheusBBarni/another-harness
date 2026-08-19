const std = @import("std");
const oauth = @import("oauth.zig");
const oauth_session = @import("oauth_session.zig");
const secret = @import("secret.zig");

const Allocator = std.mem.Allocator;

test "grok token response becomes a session with auth.x.ai issuer" {
    var token = try oauth.parseTokenSet(
        std.testing.allocator,
        "{\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"scope\":\"openid profile email offline_access grok-cli:access api:access\",\"token_type\":\"Bearer\"}",
    );
    defer token.deinit(std.testing.allocator);

    var session = try takeLoginSession(std.testing.allocator, &token, 1_000);
    defer session.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), token.access_token.len);
    try std.testing.expect(token.refresh_token == null);

    const text = try stringify(std.testing.allocator, session);
    defer secret.zeroAndFree(std.testing.allocator, text);

    try std.testing.expectError(error.InvalidAuthSession, oauth_session.parse(std.testing.allocator, text));

    var parsed = try parse(std.testing.allocator, text);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("https://auth.x.ai", parsed.issuer);
    try std.testing.expectEqualStrings("b1a00492-073a-47ea-816f-4c329264a828", parsed.client_id);
    try std.testing.expectEqualStrings("access", parsed.access_token);
    try std.testing.expectEqualStrings("refresh", parsed.refresh_token);
    try std.testing.expectEqual(@as(i64, 3_601_000), parsed.expires_at_ms);
    try std.testing.expectEqualStrings("openid profile email offline_access grok-cli:access api:access", parsed.scope);
    try std.testing.expectEqualStrings("Bearer", parsed.token_type);
}
