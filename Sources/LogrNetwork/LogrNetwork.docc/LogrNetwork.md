# ``LogrNetwork``

Records HTTP requests as Logr entries, one per request, without swizzling.

## Overview

Create one ``NetworkLogger`` for the service the app logs to, then send requests through
`URLSession/loggedData(for:to:file:function:line:)` or give a session ``LogrURLSessionProxyDelegate``.
Each request becomes an entry in category `.http` whose metadata keys are listed in ``HTTPLogFields``, so
retention, encryption and export apply as to any other entry. Secrets in headers, query items and JSON or form
bodies are redacted (``NetworkLoggerConfiguration``); bodies are kept only on request, encrypted outside the
entries (``NetworkBody``).

## Topics

### Recording requests

- ``NetworkLogger``
- ``NetworkLoggerConfiguration``
- ``LogrURLSessionProxyDelegate``
- ``Foundation/URLSession``

### Reading entries back

- ``HTTPLogFields``
- ``NetworkBody``
