const std = @import("std");

test {
    _ = @import("openai_sse.zig");
}

pub const chat_completions_url = "https://api.x.ai/v1/chat/completions";

pub const Route = struct {
    api_model: []const u8,
    url: []const u8,
    uses_gateway_headers: bool = false,
};

pub fn forModel(fx_model: []const u8) ?Route {
    const prefix = "xai/";
    if (!std.mem.startsWith(u8, fx_model, prefix)) return null;
    const api_model = fx_model[prefix.len..];
    if (api_model.len == 0) return null;
    return .{
        .api_model = api_model,
        .url = chat_completions_url,
        .uses_gateway_headers = false,
    };
}

test "xai/grok-4.6 on grok creds hits chat completions without gateway headers" {
    const route = forModel("xai/grok-4.6") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("grok-4.6", route.api_model);
    try std.testing.expectEqualStrings("https://api.x.ai/v1/chat/completions", route.url);
    try std.testing.expect(!route.uses_gateway_headers);
}
