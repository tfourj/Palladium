import os
import sys
import traceback

from .shared import WEBKIT_JSI_API_PACKAGE_RELATIVE_PATH


def iter_webkit_jsi_api_paths(install_target=None):
    seen = set()

    def add(path):
        candidate = os.path.abspath(str(path))
        if candidate in seen or not os.path.isfile(candidate):
            return
        seen.add(candidate)
        yield candidate

    if install_target:
        yield from add(os.path.join(install_target, WEBKIT_JSI_API_PACKAGE_RELATIVE_PATH))

    for root in sys.path:
        if not root:
            continue
        yield from add(os.path.join(str(root), WEBKIT_JSI_API_PACKAGE_RELATIVE_PATH))


def patch_webkit_jsi_api_source(source_text):
    updated = str(source_text)
    changed = False

    pref_old = "c_byte(1), argtypes=(c_byte,))"
    pref_new = "c_byte(0), argtypes=(c_byte,))"
    if pref_old in updated:
        updated = updated.replace(pref_old, pref_new, 1)
        changed = True

    method_anchor = """            def webView0_didFinishNavigation1(this: CRet.Py_PVoid, sel: CRet.Py_PVoid, rp_webview: CRet.Py_PVoid, rp_navi: CRet.Py_PVoid) -> None:
                pa.logger.trace(f'Callback: [(PyForeignClass_WebViewHandler){this} webView: {rp_webview} didFinishNavigation: {rp_navi}]')
                if cb := navi_cbdct.get(rp_navi or 0):
                    cb()
"""
    method_injection = method_anchor + """

            @staticmethod
            def webView0_decidePolicyForNavigationAction1_decisionHandler2(
                this: CRet.Py_PVoid, sel: CRet.Py_PVoid,
                rp_webview: CRet.Py_PVoid, rp_action: CRet.Py_PVoid, rp_decision_handler: CRet.Py_PVoid
            ) -> None:
                decision_handler = cast(rp_decision_handler or 0, POINTER(ObjCBlock)).contents
                respond = decision_handler.as_pycb(None, c_long)
                rp_request = c_void_p(pa.send_message(c_void_p(rp_action), b'request', restype=c_void_p))
                rp_url = c_void_p(pa.send_message(rp_request, b'URL', restype=c_void_p)) if rp_request.value else c_void_p()
                url_text = str_from_nsstring(
                    pa,
                    c_void_p(pa.send_message(rp_url, b'absoluteString', restype=c_void_p)) if rp_url.value else c_void_p(),
                    default='',
                )
                lower_url = url_text.lower()
                should_block = lower_url.startswith('youtube:') or 'yt-dlp-wins' in lower_url
                if should_block:
                    pa.logger.info(f'blocked navigation request: {url_text}')
                    respond(c_long(0))
                    return
                respond(c_long(1))

            @staticmethod
            def webView0_createWebViewWithConfiguration1_forNavigationAction2_windowFeatures3(
                this: CRet.Py_PVoid, sel: CRet.Py_PVoid,
                rp_webview: CRet.Py_PVoid, rp_config: CRet.Py_PVoid,
                rp_action: CRet.Py_PVoid, rp_window_features: CRet.Py_PVoid
            ) -> CRet.Py_PVoid:
                rp_request = c_void_p(pa.send_message(c_void_p(rp_action), b'request', restype=c_void_p))
                rp_url = c_void_p(pa.send_message(rp_request, b'URL', restype=c_void_p)) if rp_request.value else c_void_p()
                url_text = str_from_nsstring(
                    pa,
                    c_void_p(pa.send_message(rp_url, b'absoluteString', restype=c_void_p)) if rp_url.value else c_void_p(),
                    default='',
                )
                pa.logger.info(f'suppressed popup webview request: {url_text}')
                return None
"""
    if "webView0_decidePolicyForNavigationAction1_decisionHandler2" not in updated and method_anchor in updated:
        updated = updated.replace(method_anchor, method_injection, 1)
        changed = True

    meth_list_anchor = """            (
                pa.sel_registerName(b'userContentController:didReceiveScriptMessage:replyHandler:'),
                CFUNCTYPE(
                    None,
                    c_void_p, c_void_p, c_void_p, c_void_p, c_void_p)(
                        PFC_WVHandler.userContentController0_didReceiveScriptMessage1_replyHandler2),
                b'v@:@@@?',
            ),
        )
"""
    meth_list_injection = """            (
                pa.sel_registerName(b'userContentController:didReceiveScriptMessage:replyHandler:'),
                CFUNCTYPE(
                    None,
                    c_void_p, c_void_p, c_void_p, c_void_p, c_void_p)(
                        PFC_WVHandler.userContentController0_didReceiveScriptMessage1_replyHandler2),
                b'v@:@@@?',
            ),
            (
                pa.sel_registerName(b'webView:decidePolicyForNavigationAction:decisionHandler:'),
                CFUNCTYPE(
                    None,
                    c_void_p, c_void_p, c_void_p, c_void_p, c_void_p)(
                        PFC_WVHandler.webView0_decidePolicyForNavigationAction1_decisionHandler2),
                b'v@:@@@?',
            ),
            (
                pa.sel_registerName(b'webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:'),
                CFUNCTYPE(
                    c_void_p,
                    c_void_p, c_void_p, c_void_p, c_void_p, c_void_p, c_void_p)(
                        PFC_WVHandler.webView0_createWebViewWithConfiguration1_forNavigationAction2_windowFeatures3),
                b'@@:@@@@',
            ),
        )
"""
    if "webView:decidePolicyForNavigationAction:decisionHandler:" not in updated and meth_list_anchor in updated:
        updated = updated.replace(meth_list_anchor, meth_list_injection, 1)
        changed = True

    is_safe = (
        "c_byte(0), argtypes=(c_byte,))" in updated
        and "webView0_decidePolicyForNavigationAction1_decisionHandler2" in updated
        and "webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:" in updated
    )
    return updated, changed, is_safe


def ensure_safe_webkit_jsi_runtime(install_target=None):
    patched_count = 0
    found_any = False

    for path in iter_webkit_jsi_api_paths(install_target):
        found_any = True
        try:
            with open(path, "r", encoding="utf-8") as handle:
                source = handle.read()
        except Exception:
            print(f"[palladium] failed to read webkit jsi runtime: {path}")
            traceback.print_exc()
            continue

        updated, changed, is_safe = patch_webkit_jsi_api_source(source)
        if not is_safe:
            print(f"[palladium] webkit jsi runtime still unsafe after patch attempt: {path}")
            continue
        if not changed:
            print(f"[palladium] webkit jsi runtime already safe: {path}")
            patched_count += 1
            continue

        temp_path = path + ".tmp"
        try:
            with open(temp_path, "w", encoding="utf-8") as handle:
                handle.write(updated)
            os.replace(temp_path, path)
            patched_count += 1
            print(f"[palladium] patched webkit jsi runtime: {path}")
        except Exception:
            print(f"[palladium] failed to patch webkit jsi runtime: {path}")
            traceback.print_exc()
            try:
                if os.path.exists(temp_path):
                    os.remove(temp_path)
            except Exception:
                pass

    if not found_any:
        print("[palladium] webkit jsi runtime not found")

    return patched_count > 0
