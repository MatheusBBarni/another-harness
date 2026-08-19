const std = @import("std");
const types = @import("../core/shared/types.zig");

const Allocator = std.mem.Allocator;

const PendingTool = struct {
    id: std.ArrayList(u8) = .empty,
    name: std.ArrayList(u8) = .empty,
    arguments: std.ArrayList(u8) = .empty,

    fn deinit(self: *PendingTool, alloc: Allocator) void {
        self.id.deinit(alloc);
        self.name.deinit(alloc);
        self.arguments.deinit(alloc);
        self.* = undefined;
    }
};

pub fn parseChatCompletionsSse(alloc: Allocator, sse: []const u8) !types.GatewayCompletion {
    var content: std.ArrayList(u8) = .empty;
    errdefer content.deinit(alloc);
    var tools: std.ArrayList(PendingTool) = .empty;
    defer {
        for (tools.items) |*tool| tool.deinit(alloc);
        tools.deinit(alloc);
    }

    var finish_reason: ?types.ProviderFinishReason = null;
    var lines = std.mem.splitScalar(u8, sse, '\n');
    while (lines.next()) |line| {
        const payload = dataPayload(line) orelse continue;
        if (std.mem.eql(u8, payload, "[DONE]")) break;
        applyDelta(alloc, payload, &content, &tools, &finish_reason) catch continue;
    }

    const owned_content = if (content.items.len == 0) null else try content.toOwnedSlice(alloc);
    errdefer if (owned_content) |value| alloc.free(value);

    const owned_tools = try finishTools(alloc, tools.items);
    return .{
        .content = owned_content,
        .tool_calls = owned_tools,
        .finish_reason = finish_reason orelse if (owned_tools.len > 0) .tool_calls else .stop,
    };
}

fn dataPayload(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \r");
    if (!std.mem.startsWith(u8, trimmed, "data:")) return null;
    return std.mem.trim(u8, trimmed["data:".len..], " ");
}

fn applyDelta(
    alloc: Allocator,
    payload: []const u8,
    content: *std.ArrayList(u8),
    tools: *std.ArrayList(PendingTool),
    finish_reason: *?types.ProviderFinishReason,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return;
    const choices = parsed.value.object.get("choices") orelse return;
    if (choices != .array or choices.array.items.len == 0) return;
    const first = choices.array.items[0];
    if (first != .object) return;
    if (first.object.get("finish_reason")) |value| {
        if (value == .string) {
            if (types.ProviderFinishReason.parse_legacy(value.string)) |reason| {
                finish_reason.* = reason;
            }
        }
    }
    const delta = first.object.get("delta") orelse return;
    if (delta != .object) return;

    if (delta.object.get("content")) |value| {
        if (value == .string) try content.appendSlice(alloc, value.string);
    }
    const tool_calls = delta.object.get("tool_calls") orelse return;
    if (tool_calls != .array) return;
    for (tool_calls.array.items) |entry| {
        if (entry != .object) continue;
        const index_value = entry.object.get("index") orelse continue;
        if (index_value != .integer or index_value.integer < 0) continue;
        const index: usize = @intCast(index_value.integer);
        try ensureTool(alloc, tools, index);
        var tool = &tools.items[index];
        if (entry.object.get("id")) |id| {
            if (id == .string) try tool.id.appendSlice(alloc, id.string);
        }
        const function = entry.object.get("function") orelse continue;
        if (function != .object) continue;
        if (function.object.get("name")) |name| {
            if (name == .string) try tool.name.appendSlice(alloc, name.string);
        }
        if (function.object.get("arguments")) |arguments| {
            if (arguments == .string) try tool.arguments.appendSlice(alloc, arguments.string);
        }
    }
}

fn ensureTool(alloc: Allocator, tools: *std.ArrayList(PendingTool), index: usize) !void {
    while (tools.items.len <= index) {
        try tools.append(alloc, .{});
    }
}

fn finishTools(alloc: Allocator, pending: []PendingTool) ![]types.ToolCall {
    if (pending.len == 0) return &.{};
    const calls = try alloc.alloc(types.ToolCall, pending.len);
    errdefer alloc.free(calls);
    var filled: usize = 0;
    errdefer {
        var i: usize = 0;
        while (i < filled) : (i += 1) types.freeToolCall(alloc, calls[i]);
    }
    for (pending, 0..) |*tool, i| {
        calls[i] = .{
            .id = try tool.id.toOwnedSlice(alloc),
            .name = try tool.name.toOwnedSlice(alloc),
            .arguments_json = try tool.arguments.toOwnedSlice(alloc),
        };
        tool.* = .{};
        filled += 1;
    }
    return calls;
}

pub fn freeCompletion(alloc: Allocator, completion: *types.GatewayCompletion) void {
    if (completion.content) |content| alloc.free(@constCast(content));
    types.freeToolCallSlice(alloc, @constCast(completion.tool_calls));
    completion.* = .{};
}

test "openai sse maps text and tool calls to GatewayCompletion" {
    const sse = "data: {\"choices\":[{\"delta\":{\"content\":\"Hi \"}}]}\n\n" ++
        "data: {\"choices\":[{\"delta\":{\"content\":\"there\"}}]}\n\n" ++
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]}}]}\n\n" ++
        "data: [DONE]\n";
    var completion = try parseChatCompletionsSse(std.testing.allocator, sse);
    defer freeCompletion(std.testing.allocator, &completion);

    try std.testing.expectEqualStrings("Hi there", completion.content.?);
    try std.testing.expectEqual(@as(usize, 1), completion.tool_calls.len);
    try std.testing.expectEqualStrings("call_1", completion.tool_calls[0].id);
    try std.testing.expectEqualStrings("read", completion.tool_calls[0].name);
    try std.testing.expectEqualStrings("{}", completion.tool_calls[0].arguments_json);
    try std.testing.expectEqual(types.ProviderFinishReason.tool_calls, completion.finish_reason.?);
}

test "openai sse stop finish reason completes instead of interrupting" {
    const sse = "data: {\"choices\":[{\"delta\":{\"content\":\"Hi.\"}}]}\n\n" ++
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" ++
        "data: [DONE]\n";
    var completion = try parseChatCompletionsSse(std.testing.allocator, sse);
    defer freeCompletion(std.testing.allocator, &completion);
    try std.testing.expectEqualStrings("Hi.", completion.content.?);
    try std.testing.expectEqual(types.ProviderFinishReason.stop, completion.finish_reason.?);
    try std.testing.expectEqual(types.ProviderCompletionDisposition.completed, types.classifyProviderCompletion(completion));
}
