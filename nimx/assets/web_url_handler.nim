import url_stream
import async_http_request except Handler
import logging

import nimx.http_request except Handler

const web = defined(js) or defined(emscripten)

type URLLoadingError* = object
    description*: string

when web:
    import jsbind

    when defined(js):
        import nimx.private.js_data_view_stream

    proc loadJSURL*(url: string, resourceType: cstring, onProgress: proc(p: float), onError: proc(e: URLLoadingError), onComplete: proc(result: JSObj)) =
        assert(not onComplete.isNil)

        let oReq = newXMLHTTPRequest()
        var reqListener: proc()
        var errorListener: proc()
        reqListener = proc() =
            jsUnref(reqListener)
            jsUnref(errorListener)
            handleJSExceptions:
                onComplete(oReq.response)
        errorListener = proc() =
            jsUnref(reqListener)
            jsUnref(errorListener)
            handleJSExceptions:
                var err: URLLoadingError
                var statusText = oReq.statusText
                if statusText.isNil: statusText = "(nil)"
                err.description = "XMLHTTPRequest error(" & url & "): " & $oReq.status & ": " & $statusText
                info "XMLHTTPRequest failure: ", err.description
                if not onError.isNil:
                    onError(err)
        jsRef(reqListener)
        jsRef(errorListener)

        oReq.addEventListener("load", reqListener)
        oReq.addEventListener("error", errorListener)
        oReq.open("GET", url)
        oReq.responseType = resourceType
        oReq.send()

    when defined(emscripten):
        import jsbind.emscripten

        proc arrayBufferToString(arrayBuffer: JSObj): string =
            let r = EM_ASM_INT("""
            var a = new Int8Array(_nimem_o[$0]);
            var b = _nimem_ps(a.length);
            writeArrayToMemory(a, _nimem_sb(b));
            return b;
            """, arrayBuffer.p)
            result = cast[string](r)

proc getHttpStream(url: string, handler: Handler) =
    when web:
        let reqListener = proc(data: JSObj) =
            when defined(js):
                var dataView : ref RootObj
                {.emit: "`dataView` = new DataView(`data`);".}
                handler(newStreamWithDataView(dataView), nil)
            else:
                info "Processing url: ", url
                handler(newStringStream(arrayBufferToString(data)), nil)

        let errorListener = proc(e: URLLoadingError) =
            handler(nil, e.description)

        loadJSURL(url, "arraybuffer", nil, errorListener, reqListener)
    else:
        sendRequest("GET", url, nil, []) do(r: Response):
            if r.statusCode >= 200 and r.statusCode < 300:
                let s = newStringStream(r.body)
                handler(s, nil)
            else:
                handler(nil, "Error downloading url " & url & ": " & $r.statusCode)

registerUrlHandler("http", getHttpStream)
registerUrlHandler("https", getHttpStream)

when web:
    registerUrlHandler("file", getHttpStream)
