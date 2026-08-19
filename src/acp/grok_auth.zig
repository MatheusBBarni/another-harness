const std = @import("std");

pub const method_id = "grok_oauth";
pub const missing_session_message = "run fx login grok first";

pub const AuthenticateResult = union(enum) {
    ok,
    failed: []const u8,
};

pub fn authenticate(requested_method: []const u8, grok_session_present: bool) AuthenticateResult {
    if (!std.mem.eql(u8, requested_method, method_id)) {
        return .{ .failed = "unknown auth method" };
    }
    if (!grok_session_present) {
        return .{ .failed = missing_session_message };
    }
    return .ok;
}

pub fn authMethodsJson() []const u8 {
    return "[{\"id\":\"grok_oauth\",\"name\":\"Grok OAuth\",\"description\":\"Use a SuperGrok session from fx login grok\"}]";
}

test "ACP grok_oauth uses cached session or asks for fx login grok" {
    try std.testing.expectEqual(AuthenticateResult.ok, authenticate("grok_oauth", true));
    switch (authenticate("grok_oauth", false)) {
        .failed => |message| try std.testing.expect(std.mem.indexOf(u8, message, "fx login grok") != null),
        .ok => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.mem.indexOf(u8, authMethodsJson(), "grok_oauth") != null);
}
