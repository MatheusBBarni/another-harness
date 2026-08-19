const std = @import("std");

test "xai/grok-4.6 on grok creds hits chat completions without gateway headers" {
    const route = forModel("xai/grok-4.6") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("grok-4.6", route.api_model);
    try std.testing.expectEqualStrings("https://api.x.ai/v1/chat/completions", route.url);
    try std.testing.expect(!route.uses_gateway_headers);
}
