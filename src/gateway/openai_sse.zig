const std = @import("std");
const types = @import("../core/shared/types.zig");

test "openai sse maps text and tool calls to GatewayCompletion" {
    const sse =
        \\data: {"choices":[{"delta":{"content":"Hi "}}]}
        \\
        \\data: {"choices":[{"delta":{"content":"there"}}]}
        \\
        \\data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read","arguments":"{\"p\""}}}]}}]}
        \\
        \\data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":1}"}}]}}]}
        \\
        \\data: [DONE]
        \\
    ;
    var completion = try parseChatCompletionsSse(std.testing.allocator, sse);
    defer freeCompletion(std.testing.allocator, &completion);

    try std.testing.expectEqualStrings("Hi there", completion.content.?);
    try std.testing.expectEqual(@as(usize, 1), completion.tool_calls.len);
    try std.testing.expectEqualStrings("call_1", completion.tool_calls[0].id);
    try std.testing.expectEqualStrings("read", completion.tool_calls[0].name);
    try std.testing.expectEqualStrings("{\"p\":1}", completion.tool_calls[0].arguments_json);
}
