const std = @import("std");

test {
    _ = @import("openai_sse.zig");
    _ = @import("grok_billing.zig");
}

pub const chat_completions_url = "https://api.x.ai/v1/chat/completions";
pub const responses_url = "https://api.x.ai/v1/responses";

pub const catalog_ids = [_][]const u8{
    "xai/grok-4.6",
    "xai/grok-4.5",
    "xai/grok-4.3",
    "xai/grok-build-0.1",
};

pub fn catalogIds() []const []const u8 {
    return &catalog_ids;
}

pub fn serverSearchToolsJson(enabled: bool) []const u8 {
    return if (enabled) "[{\"type\":\"web_search\"}]" else "[]";
}

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

test "grok-active catalog is the four static ids" {
    const ids = catalogIds();
    try std.testing.expectEqual(@as(usize, 4), ids.len);
    try std.testing.expectEqualStrings("xai/grok-4.6", ids[0]);
    try std.testing.expectEqualStrings("xai/grok-4.5", ids[1]);
    try std.testing.expectEqualStrings("xai/grok-4.3", ids[2]);
    try std.testing.expectEqualStrings("xai/grok-build-0.1", ids[3]);
}

test "grok web search is server-side web_search" {
    const enabled = serverSearchToolsJson(true);
    try std.testing.expectEqualStrings("[{\"type\":\"web_search\"}]", enabled);
    try std.testing.expect(std.mem.indexOf(u8, enabled, "perplexity") == null);
    try std.testing.expect(std.mem.indexOf(u8, enabled, "parallel") == null);
    try std.testing.expectEqualStrings("[]", serverSearchToolsJson(false));
}
