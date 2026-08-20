const std = @import("std");
const agent_stream_provider = @import("../core/agent/stream_provider.zig");
const io_mod = @import("../core/shared/io.zig");
const openai_sse = @import("openai_sse.zig");
const secret = @import("../core/auth/secret.zig");
const grok_billing = @import("grok_billing.zig");

const Allocator = std.mem.Allocator;

var rpm_remaining: std.atomic.Value(u64) = .init(0);
var rpm_limit: std.atomic.Value(u64) = .init(0);
var rpm_present: std.atomic.Value(bool) = .init(false);

pub fn isGrokChatUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "https://api.x.ai/");
}

pub fn lastRequestWindow() ?grok_billing.RequestWindow {
    if (!rpm_present.load(.seq_cst)) return null;
    return .{
        .remaining = rpm_remaining.load(.seq_cst),
        .limit = rpm_limit.load(.seq_cst),
    };
}

pub fn testingClearLastRequestWindow() void {
    rpm_present.store(false, .seq_cst);
}

fn rememberRequestWindow(window: grok_billing.RequestWindow) void {
    rpm_remaining.store(window.remaining, .seq_cst);
    rpm_limit.store(window.limit, .seq_cst);
    rpm_present.store(true, .seq_cst);
}

fn headerValue(head: std.http.Client.Response.Head, name: []const u8) ?[]const u8 {
    var it = head.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            return std.mem.trim(u8, header.value, " \t\r\n");
        }
    }
    return null;
}

fn requestWindowFromHead(head: std.http.Client.Response.Head) ?grok_billing.RequestWindow {
    return grok_billing.parseRequestWindow(
        headerValue(head, "x-ratelimit-remaining-requests"),
        headerValue(head, "x-ratelimit-limit-requests"),
    );
}

fn recordTransportFailure(request: agent_stream_provider.Request) void {
    request.attempt_evidence.network_failure = .{
        .cause = .transport_interrupted,
        .delivery = request.delivery.load(),
    };
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

    const uri = std.Uri.parse(request.chat_url) catch |err| {
        recordTransportFailure(request);
        return err;
    };

    var req = client.request(.POST, uri, .{
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = auth_header },
            .accept_encoding = .omit,
            .user_agent = .{ .override = "fx-grok" },
        },
        .extra_headers = &extra_headers,
        .redirect_behavior = .unhandled,
    }) catch |err| {
        recordTransportFailure(request);
        return err;
    };
    defer req.deinit();

    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    request.delivery.markPossiblySent();

    req.sendBodyComplete(@constCast(request.payload)) catch |err| {
        recordTransportFailure(request);
        return err;
    };

    var response = req.receiveHead(&.{}) catch |err| {
        recordTransportFailure(request);
        return err;
    };

    if (response.head.status == .ok) {
        if (requestWindowFromHead(response.head)) |window| {
            rememberRequestWindow(window);
        }
    }

    var transfer_buf: [64 * 1024]u8 = undefined;
    const body_reader = response.reader(&transfer_buf);
    _ = body_reader.streamRemaining(&out.writer) catch |err| {
        recordTransportFailure(request);
        return err;
    };

    const body = try out.toOwnedSlice();
    errdefer alloc.free(body);

    if (response.head.status != .ok) {
        return .{
            .status = response.head.status,
            .err_body = body,
            .generation_origin = "https://api.x.ai",
            .reconcile_generation_usage = false,
            .ownership = .owned,
        };
    }

    const completion = openai_sse.parseChatCompletionsSse(alloc, body) catch {
        return .{
            .status = response.head.status,
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

test "grok stream request window headers parse remaining and limit" {
    const response_bytes = "HTTP/1.1 200 OK\r\n" ++
        "x-ratelimit-remaining-requests: 8299\r\n" ++
        "x-ratelimit-limit-requests: 8300\r\n" ++
        "\r\n";
    const head = try std.http.Client.Response.Head.parse(response_bytes);
    const window = requestWindowFromHead(head) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 8299), window.remaining);
    try std.testing.expectEqual(@as(u64, 8300), window.limit);
    rememberRequestWindow(window);
    const cached = lastRequestWindow() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(window.remaining, cached.remaining);
    try std.testing.expectEqual(window.limit, cached.limit);
}

test "grok stream ignores missing or non-numeric request window headers" {
    const missing = try std.http.Client.Response.Head.parse("HTTP/1.1 200 OK\r\n\r\n");
    try std.testing.expect(requestWindowFromHead(missing) == null);

    const invalid = try std.http.Client.Response.Head.parse(
        "HTTP/1.1 200 OK\r\n" ++
            "x-ratelimit-remaining-requests: nope\r\n" ++
            "x-ratelimit-limit-requests: 8300\r\n" ++
            "\r\n",
    );
    try std.testing.expect(requestWindowFromHead(invalid) == null);
}
