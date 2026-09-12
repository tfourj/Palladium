#include "evaluate.h"
#include <quickjs.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define OUTPUT_LIMIT (16 * 1024 * 1024)
#define STACK_LIMIT (2 * 1024 * 1024)

typedef struct Rejection {
    JSValue promise;
    JSValue reason;
    struct Rejection *next;
} Rejection;

typedef struct {
    PalladiumQJSResult result;
    size_t capacity;
    double deadline;
    const char *cancel_file;
    Rejection *rejections;
} Evaluation;

static double monotonic_seconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec + (double)now.tv_nsec / 1e9;
}

static int interrupt(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    Evaluation *evaluation = opaque;
    if (evaluation->cancel_file && evaluation->cancel_file[0]
        && access(evaluation->cancel_file, F_OK) == 0) {
        evaluation->result.status = PALLADIUM_QJS_CANCELLED;
    } else if (evaluation->result.status == PALLADIUM_QJS_OK
               && monotonic_seconds() >= evaluation->deadline) {
        evaluation->result.status = PALLADIUM_QJS_TIMEOUT;
    }
    return evaluation->result.status != PALLADIUM_QJS_OK;
}

static bool append_output(Evaluation *evaluation, const char *text, size_t length) {
    size_t needed = evaluation->result.output_length + length + 1;
    if (needed > OUTPUT_LIMIT) {
        evaluation->result.status = PALLADIUM_QJS_OUTPUT_LIMIT;
        return false;
    }
    if (needed > evaluation->capacity) {
        size_t capacity = evaluation->capacity ? evaluation->capacity : 256;
        while (capacity < needed) capacity *= 2;
        char *buffer = realloc(evaluation->result.output, capacity);
        if (!buffer) {
            evaluation->result.status = PALLADIUM_QJS_MEMORY_LIMIT;
            return false;
        }
        evaluation->result.output = buffer;
        evaluation->capacity = capacity;
    }
    memcpy(evaluation->result.output + evaluation->result.output_length, text, length);
    evaluation->result.output_length += length;
    evaluation->result.output[evaluation->result.output_length] = '\0';
    return true;
}

static JSValue console_log(JSContext *context, JSValueConst this_value, int argc, JSValueConst *argv) {
    (void)this_value;
    Evaluation *evaluation = JS_GetContextOpaque(context);
    for (int index = 0; index < argc; index++) {
        size_t length;
        const char *text = JS_ToCStringLen(context, &length, argv[index]);
        if (!text) return JS_EXCEPTION;
        bool appended = (index == 0 || append_output(evaluation, " ", 1))
            && append_output(evaluation, text, length);
        JS_FreeCString(context, text);
        if (!appended) return JS_ThrowInternalError(context, "console output limit or allocation failure");
    }
    if (!append_output(evaluation, "\n", 1)) {
        return JS_ThrowInternalError(context, "console output limit or allocation failure");
    }
    return JS_UNDEFINED;
}

static void capture_error(JSContext *context, Evaluation *evaluation, JSValueConst exception) {
    // Do not execute user-defined getters/toString after an interrupt or resource failure.
    if (evaluation->result.status != PALLADIUM_QJS_OK) return;
    const char *message = JS_ToCString(context, exception);
    evaluation->result.error = strdup(message ? message : "JavaScript exception");
    if (message) JS_FreeCString(context, message);
    if (evaluation->result.status == PALLADIUM_QJS_OK) {
        evaluation->result.status = PALLADIUM_QJS_EXCEPTION;
    }
}

static void track_rejection(
    JSContext *context, JSValueConst promise, JSValueConst reason, bool handled, void *opaque
) {
    Evaluation *evaluation = opaque;
    Rejection **link = &evaluation->rejections;
    while (*link && JS_VALUE_GET_PTR((*link)->promise) != JS_VALUE_GET_PTR(promise)) {
        link = &(*link)->next;
    }
    if (handled) {
        if (*link) {
            Rejection *rejection = *link;
            *link = rejection->next;
            JS_FreeValue(context, rejection->promise);
            JS_FreeValue(context, rejection->reason);
            free(rejection);
        }
    } else if (!*link) {
        Rejection *rejection = malloc(sizeof(*rejection));
        if (!rejection) {
            evaluation->result.status = PALLADIUM_QJS_MEMORY_LIMIT;
            return;
        }
        *rejection = (Rejection){JS_DupValue(context, promise), JS_DupValue(context, reason), NULL};
        *link = rejection;
    }
}

static bool install_console(JSContext *context) {
    JSValue global = JS_GetGlobalObject(context);
    JSValue console = JS_NewObject(context);
    bool success = !JS_IsException(console);
    const char *methods[] = {"log", "info", "warn", "error", "debug"};
    for (size_t index = 0; success && index < sizeof(methods) / sizeof(methods[0]); index++) {
        JSValue function = JS_NewCFunction(context, console_log, methods[index], 1);
        success = !JS_IsException(function)
            && JS_SetPropertyStr(context, console, methods[index], function) >= 0;
    }
    if (success) {
        success = JS_SetPropertyStr(context, global, "console", console) >= 0;
    } else {
        JS_FreeValue(context, console);
    }
    JS_FreeValue(context, global);
    return success;
}

PalladiumQJSResult palladium_qjs_evaluate(
    const char *source, size_t source_length, const char *cancel_file,
    unsigned int timeout_ms, size_t memory_limit
) {
    Evaluation evaluation = {
        .deadline = monotonic_seconds() + (double)timeout_ms / 1000,
        .cancel_file = cancel_file,
    };
    if (interrupt(NULL, &evaluation)) return evaluation.result;
    JSRuntime *runtime = JS_NewRuntime();
    if (!runtime) {
        evaluation.result.status = PALLADIUM_QJS_MEMORY_LIMIT;
        return evaluation.result;
    }
    JS_SetMemoryLimit(runtime, memory_limit);
    JS_SetMaxStackSize(runtime, STACK_LIMIT);
    JS_SetCanBlock(runtime, false);
    JS_SetInterruptHandler(runtime, interrupt, &evaluation);
    JS_SetHostPromiseRejectionTracker(runtime, track_rejection, &evaluation);
    JSContext *context = JS_NewContext(runtime);
    if (!context) {
        evaluation.result.status = PALLADIUM_QJS_MEMORY_LIMIT;
        JS_FreeRuntime(runtime);
        return evaluation.result;
    }
    JS_SetContextOpaque(context, &evaluation);
    JSValue value = JS_EXCEPTION;
    if (install_console(context)) {
        value = JS_Eval(context, source, source_length, "palladium-ejs.js", JS_EVAL_TYPE_GLOBAL);
    }
    if (JS_IsException(value)) {
        JSValue exception = JS_GetException(context);
        capture_error(context, &evaluation, exception);
        JS_FreeValue(context, exception);
    }
    JS_FreeValue(context, value);
    while (evaluation.result.status == PALLADIUM_QJS_OK && JS_IsJobPending(runtime)) {
        if (interrupt(runtime, &evaluation)) break;
        JSContext *job_context = NULL;
        if (JS_ExecutePendingJob(runtime, &job_context) < 0) {
            JSValue exception = JS_GetException(job_context);
            capture_error(job_context, &evaluation, exception);
            JS_FreeValue(job_context, exception);
            break;
        }
    }
    if (evaluation.rejections && evaluation.result.status == PALLADIUM_QJS_OK) {
        capture_error(context, &evaluation, evaluation.rejections->reason);
    }
    JS_SetHostPromiseRejectionTracker(runtime, NULL, NULL);
    while (evaluation.rejections) {
        Rejection *rejection = evaluation.rejections;
        evaluation.rejections = rejection->next;
        JS_FreeValue(context, rejection->promise);
        JS_FreeValue(context, rejection->reason);
        free(rejection);
    }
    JS_FreeContext(context);
    JS_FreeRuntime(runtime);
    return evaluation.result;
}

void palladium_qjs_result_free(PalladiumQJSResult *result) {
    free(result->output);
    free(result->error);
    *result = (PalladiumQJSResult){0};
}
