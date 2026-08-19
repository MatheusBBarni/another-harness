const std = @import("std");

test {
    _ = @import("openai_sse.zig");
}

pub const chat_completions_url = "https://api.x.ai/v1/chat/completions";
pub const responses_url = "https://api.x.ai/v1/responses";

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
    const url = if (std.mem.eql(u8, api_model, "grok-4.5")) responses_url else chat_completions_url;
    return .{
        .api_model = api_model,
        .url = url,
        .uses_gateway_headers = false,
    };
}

test "xai/grok-4.6 on grok creds hits chat completions without gateway headers" {
    const route = forModel("xai/grok-4.6") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("grok-4.6", route.api_model);
    try std.testing.expectEqualStrings("https://api.x.ai/v1/chat/completions", route.url);
    try std.testing.expect(!route.uses_gateway_headers);
}

test "xai/grok-4.5 uses responses; other grok ids stay on chat completions" {
    const responses = forModel("xai/grok-4.5") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("grok-4.5", responses.api_model);
    try std.testing.expectEqualStrings("https://api.x.ai/v1/responses", responses.url);

    for ([_][]const u8{ "xai/grok-4.6", "xai/grok-4.3", "xai/grok-build-0.1" }) |model| {
        const route = forModel(model) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings("https://api.x.ai/v1/chat/completions", route.url);
    }
}
