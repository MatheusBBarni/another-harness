const std = @import("std");

test "login grok and vercel skip the picker; unknown args fail" {
    try std.testing.expectEqual(LoginProvider.picker, try parseLoginProvider(&.{}));
    try std.testing.expectEqual(LoginProvider.grok, try parseLoginProvider(&.{"grok"}));
    try std.testing.expectEqual(LoginProvider.vercel, try parseLoginProvider(&.{"vercel"}));
    try std.testing.expectError(error.InvalidLoginProvider, parseLoginProvider(&.{"openai"}));
    try std.testing.expectError(error.InvalidLoginProvider, parseLoginProvider(&.{ "grok", "vercel" }));
}
