#ifndef PALLADIUM_QUICKJS_EVALUATE_H
#define PALLADIUM_QUICKJS_EVALUATE_H

#include <stddef.h>

typedef enum {
    PALLADIUM_QJS_OK,
    PALLADIUM_QJS_EXCEPTION,
    PALLADIUM_QJS_TIMEOUT,
    PALLADIUM_QJS_CANCELLED,
    PALLADIUM_QJS_OUTPUT_LIMIT,
    PALLADIUM_QJS_MEMORY_LIMIT
} PalladiumQJSStatus;

typedef struct {
    PalladiumQJSStatus status;
    char *output;
    size_t output_length;
    char *error;
} PalladiumQJSResult;

PalladiumQJSResult palladium_qjs_evaluate(
    const char *source, size_t source_length, const char *cancel_file,
    unsigned int timeout_ms, size_t memory_limit);
void palladium_qjs_result_free(PalladiumQJSResult *result);

#endif
