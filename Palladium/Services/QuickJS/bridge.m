#import <Foundation/Foundation.h>
#include <quickjs.h>
#include "PalladiumQuickJS.h"
#include "evaluate.h"

static char *encode_response(NSDictionary *response) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    if (!data) return NULL;
    char *buffer = malloc(data.length + 1);
    if (!buffer) return NULL;
    memcpy(buffer, data.bytes, data.length);
    buffer[data.length] = '\0';
    return buffer;
}

char *palladium_quickjs_bridge_run(const char *request_json) {
    @autoreleasepool {
        NSData *data = request_json ? [NSData dataWithBytes:request_json length:strlen(request_json)] : nil;
        id request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![request isKindOfClass:[NSDictionary class]]) {
            return encode_response(@{@"ok": @NO, @"status": @"invalid_request", @"error": @"Invalid JSON request"});
        }
        NSString *version = [NSString stringWithUTF8String:JS_GetVersion()];
        if ([request[@"operation"] isEqual:@"info"]) {
            return encode_response(@{@"ok": @YES, @"name": @"quickjs-ng", @"version": version});
        }
        NSString *source = request[@"source"];
        NSString *cancel_file = request[@"cancel_file"] ?: @"";
        if (![request[@"operation"] isEqual:@"evaluate"] || ![source isKindOfClass:[NSString class]]
            || ![cancel_file isKindOfClass:[NSString class]]
            || [cancel_file rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound) {
            return encode_response(@{@"ok": @NO, @"status": @"invalid_request", @"error": @"Invalid evaluation request"});
        }
        NSData *source_data = [source dataUsingEncoding:NSUTF8StringEncoding];
        PalladiumQJSResult result = palladium_qjs_evaluate(
            source.UTF8String, source_data.length, cancel_file.UTF8String, 30000, 256 * 1024 * 1024);
        const char *statuses[] = {"ok", "exception", "timeout", "cancelled", "output_limit", "memory_limit"};
        NSString *status = [NSString stringWithUTF8String:statuses[result.status]];
        NSString *output = result.output
            ? [[NSString alloc] initWithBytes:result.output length:result.output_length encoding:NSUTF8StringEncoding]
            : @"";
        NSString *error = result.error ? [NSString stringWithUTF8String:result.error] : status;
        char *response = encode_response(@{
            @"ok": @(result.status == PALLADIUM_QJS_OK), @"status": status,
            @"output": output ?: @"", @"error": result.status == PALLADIUM_QJS_OK ? @"" : (error ?: status),
            @"version": version,
        });
        palladium_qjs_result_free(&result);
        return response;
    }
}

void palladium_quickjs_bridge_free(char *response_json) {
    free(response_json);
}
