const std = @import("std");
const agent_stream_provider = @import("../core/agent/stream_provider.zig");
const io_mod = @import("../core/shared/io.zig");
const openai_sse = @import("openai_sse.zig");
const secret = @import("../core/auth/secret.zig");

const Allocator = std.mem.Allocator;

pub fn isGrokChatUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "https://api.x.ai/");
}

pub fn stream(
    alloc: Allocator,
    request: agent_stream_provider.Request,
) !agent_stream_provider.Result {
    var client: std.http.Client = .{ .allocator = alloc, .io = io_mod.getIo() };
    defer client.deinit();

    const auth_header = try std.fmt.allocPrint(alloc, "Bearer {s}", .{request.api_key});
    defer secret.zeroAndFree(alloc, auth_header);

    const extra_headers = [_]std.http.Header{
        .{ .name = "Accept", .value = "text/event-stream" },
    };

    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    request.delivery.markPossiblySent();

    const fetched = client.fetch(.{
        .location = .{ .url = request.chat_url },
        .method = .POST,
        .payload = request.payload,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = auth_header },
            .accept_encoding = .omit,
            .user_agent = .{ .override = "fx-grok" },
        },
        .extra_headers = &extra_headers,
        .response_writer = &out.writer,
    }) catch |err| {
        request.attempt_evidence.network_failure = .{
            .cause = .transport_interrupted,
            .delivery = request.delivery.load(),
        };
        return err;
    };

    const body = try out.toOwnedSlice();
    errdefer alloc.free(body);

    if (fetched.status != .ok) {
        return .{
            .status = fetched.status,
            .err_body = body,
            .generation_origin = "https://api.x.ai",
            .reconcile_generation_usage = false,
            .ownership = .owned,
        };
    }

    const completion = openai_sse.parseChatCompletionsSse(alloc, body) catch {
        return .{
            .status = fetched.status,
            .err_body = body,
            .generation_origin = "https://api.x.ai",
            .reconcile_generation_usage = false,
            .ownership = .owned,
        };
    };
    alloc.free(body);

    if (completion.content) |content| {
        if (content.len > 0) request.on_content_chunk(request.callback_ctx, content);
    }
    if (request.on_tool_start) |on_tool_start| {
        for (completion.tool_calls) |call| {
            on_tool_start(request.callback_ctx, call.id, call.name, null);
        }
    }

    return .{
        .status = .ok,
        .completion = completion,
        .generation_origin = "https://api.x.ai",
        .reconcile_generation_usage = false,
        .ownership = .owned,
    };
}
