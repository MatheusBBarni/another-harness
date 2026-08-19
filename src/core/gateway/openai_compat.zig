const std = @import("std");
const types = @import("../shared/types.zig");

const Allocator = std.mem.Allocator;

pub fn buildChatCompletionsBody(
    alloc: Allocator,
    api_model: []const u8,
    messages: []const types.ChatMessage,
    tools_json: []const u8,
    tool_choice: types.ToolChoice,
    max_output_tokens: ?u32,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{\"model\":");
    try std.json.Stringify.value(api_model, .{}, writer);
    try writer.writeAll(",\"stream\":true,\"messages\":[");
    for (messages, 0..) |message, i| {
        if (i > 0) try writer.writeByte(',');
        try writeMessage(writer, message);
    }
    try writer.writeAll("],\"tools\":");
    try writeTools(alloc, writer, tools_json);
    try writer.writeAll(",\"tool_choice\":");
    try std.json.Stringify.value(tool_choice.label(), .{}, writer);
    if (max_output_tokens) |value| {
        try writer.print(",\"max_tokens\":{d}", .{value});
    }
    try writer.writeByte('}');
    return out.toOwnedSlice();
}

fn writeMessage(writer: *std.Io.Writer, message: types.ChatMessage) !void {
    try writer.writeAll("{\"role\":");
    try std.json.Stringify.value(switch (message.role) {
        .system => "system",
        .user => "user",
        .assistant => "assistant",
        .tool => "tool",
    }, .{}, writer);
    if (message.role == .tool) {
        if (message.tool_call_id) |id| {
            try writer.writeAll(",\"tool_call_id\":");
            try std.json.Stringify.value(id, .{}, writer);
        }
    }
    if (message.tool_calls.len > 0) {
        try writer.writeAll(",\"tool_calls\":[");
        for (message.tool_calls, 0..) |call, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"id\":");
            try std.json.Stringify.value(call.id, .{}, writer);
            try writer.writeAll(",\"type\":\"function\",\"function\":{\"name\":");
            try std.json.Stringify.value(call.name, .{}, writer);
            try writer.writeAll(",\"arguments\":");
            try std.json.Stringify.value(call.arguments_json, .{}, writer);
            try writer.writeAll("}}");
        }
        try writer.writeByte(']');
    }
    if (message.content) |content| {
        try writer.writeAll(",\"content\":");
        try std.json.Stringify.value(content, .{}, writer);
    } else if (message.tool_calls.len == 0) {
        try writer.writeAll(",\"content\":\"\"");
    }
    try writer.writeByte('}');
}

fn writeTools(alloc: Allocator, writer: *std.Io.Writer, tools_json: []const u8) !void {
    if (tools_json.len == 0 or std.mem.eql(u8, tools_json, "[]")) {
        try writer.writeAll("[]");
        return;
    }
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, tools_json, .{}) catch {
        try writer.writeAll("[]");
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .array) {
        try writer.writeAll("[]");
        return;
    }
    try writer.writeByte('[');
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const name_value = item.object.get("name") orelse continue;
        if (name_value != .string or name_value.string.len == 0) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeAll("{\"type\":\"function\",\"function\":{\"name\":");
        try std.json.Stringify.value(name_value.string, .{}, writer);
        if (item.object.get("description")) |description| {
            if (description == .string) {
                try writer.writeAll(",\"description\":");
                try std.json.Stringify.value(description.string, .{}, writer);
            }
        }
        try writer.writeAll(",\"parameters\":");
        if (item.object.get("inputSchema")) |schema| {
            try std.json.Stringify.value(schema, .{}, writer);
        } else {
            try writer.writeAll("{\"type\":\"object\",\"properties\":{}}");
        }
        try writer.writeAll("}}");
    }
    try writer.writeByte(']');
}

test "openai compat body strips xai prefix and streams chat messages" {
    const messages = [_]types.ChatMessage{.{
        .role = .user,
        .content = "hi",
    }};
    const body = try buildChatCompletionsBody(
        std.testing.allocator,
        "grok-4.6",
        &messages,
        "[]",
        .auto,
        null,
    );
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"model\":\"grok-4.6\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"stream\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"role\":\"user\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"content\":\"hi\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "ai-language-model") == null);
}

test "openai compat remaps gateway tools to function tools" {
    const body = try buildChatCompletionsBody(
        std.testing.allocator,
        "grok-4.6",
        &.{},
        "[{\"type\":\"function\",\"name\":\"read\",\"description\":\"Read a file\",\"inputSchema\":{\"type\":\"object\"}}]",
        .none,
        16,
    );
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"function\":{\"name\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"parameters\":{\"type\":\"object\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"tool_choice\":\"none\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"max_tokens\":16") != null);
}
