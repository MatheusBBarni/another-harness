const std = @import("std");

test "ACP grok_oauth uses cached session or asks for fx login grok" {
    try std.testing.expectEqual(AuthenticateResult.ok, authenticate("grok_oauth", true));
    switch (authenticate("grok_oauth", false)) {
        .failed => |message| try std.testing.expect(std.mem.indexOf(u8, message, "fx login grok") != null),
        .ok => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.mem.indexOf(u8, authMethodsJson(), "grok_oauth") != null);
}
