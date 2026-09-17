#ifndef PALLADIUM_QUICKJS_H
#define PALLADIUM_QUICKJS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Both JSON requests and responses are UTF-8. The caller owns the response.
__attribute__((visibility("default")))
char *palladium_quickjs_bridge_run(const char *request_json);
__attribute__((visibility("default")))
void palladium_quickjs_bridge_free(char *response_json);

#ifdef __cplusplus
}
#endif
#endif
