"""DuckDuckGo web search MCP server + Bonsai model switcher UI."""

import os
import sys
import subprocess
from pathlib import Path

try:
    from ddgs import DDGS  # type: ignore[import-untyped]
except ImportError:
    from duckduckgo_search import DDGS  # type: ignore[import-untyped]

from mcp.server.fastmcp import FastMCP
from starlette.middleware.cors import CORSMiddleware

_port = 8808
if "--port" in sys.argv:
    _port = int(sys.argv[sys.argv.index("--port") + 1])

# Config injected by start-up.sh via environment variables
_LLAMA_PORT  = int(os.environ.get("LLAMA_PORT",       "8080"))
_MODEL_DIR   = os.path.expanduser(os.environ.get("LLAMA_MODEL_DIR", "~/.lmstudio/models"))
_SERVER_BIN  = os.environ.get("LLAMA_SERVER_BIN",  "")
_GPU_LAYERS  = os.environ.get("LLAMA_GPU_LAYERS",  "999")
_WEBUI_CFG   = os.environ.get("LLAMA_WEBUI_CFG",   "")
_CTX_SIZE    = os.environ.get("LLAMA_CTX_SIZE",    "8192")
_THREADS     = str(os.cpu_count() or 16)

_llama_proc = None  # subprocess handle when we started llama-server ourselves

mcp = FastMCP("duckduckgo-search", host="0.0.0.0", port=_port, stateless_http=True)


@mcp.tool()
def web_search(query: str, max_results: int = 5) -> str:
    """Search the web using DuckDuckGo. Returns titles, URLs, and snippets."""
    results = list(DDGS().text(query, max_results=max_results))
    if not results:
        return "No results found."
    lines = []
    for i, r in enumerate(results, 1):
        lines.append(f"{i}. {r['title']}\n   {r['href']}\n   {r['body']}\n")
    return "\n".join(lines)


@mcp.tool()
def news_search(query: str, max_results: int = 5) -> str:
    """Search recent news using DuckDuckGo."""
    results = list(DDGS().news(query, max_results=max_results))
    if not results:
        return "No news found."
    lines = []
    for i, r in enumerate(results, 1):
        lines.append(f"{i}. {r['title']}\n   {r['url']}\n   {r['body']}\n   Published: {r.get('date','unknown')}\n")
    return "\n".join(lines)


# ── Model switcher helpers ────────────────────────────────────────────────────

def _scan_models():
    """Return list of .gguf files under MODEL_DIR, sorted by folder then name."""
    models = []
    base = Path(_MODEL_DIR)
    if not base.exists():
        return models
    for path in sorted(base.rglob("*.gguf")):
        try:
            size_mb = path.stat().st_size / (1024 * 1024)
        except OSError:
            size_mb = 0
        rel = path.relative_to(base)
        folder = str(rel.parent) if str(rel.parent) != "." else ""
        models.append({
            "path":    str(path),
            "name":    path.name,
            "folder":  folder,
            "size_mb": round(size_mb, 1),
        })
    return models


def _kill_llama():
    global _llama_proc
    import os as _os
    _os.system(f"kill $(lsof -ti tcp:{_LLAMA_PORT} 2>/dev/null) 2>/dev/null || true")
    if _llama_proc and _llama_proc.poll() is None:
        _llama_proc.terminate()
    _llama_proc = None


def _start_llama(model_path: str):
    global _llama_proc
    if not _SERVER_BIN or not Path(_SERVER_BIN).exists():
        raise RuntimeError(f"LLAMA_SERVER_BIN not found: {_SERVER_BIN!r}")
    cmd = [
        _SERVER_BIN,
        "--model",   model_path,
        "--host",    "0.0.0.0",
        "--port",    str(_LLAMA_PORT),
        "-ngl",      _GPU_LAYERS,
        "--ctx-size", _CTX_SIZE,
        "--threads", _THREADS,
        "--webui-mcp-proxy",
    ]
    if _WEBUI_CFG and Path(_WEBUI_CFG).exists():
        cmd += ["--webui-config-file", _WEBUI_CFG]
    _llama_proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,   # detach so it survives MCP server restart
    )


# ── Switcher HTML ─────────────────────────────────────────────────────────────

_SWITCHER_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bonsai — Model Switcher</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:system-ui,sans-serif;background:#0d0d0d;color:#d4d4d4;padding:2rem 2.5rem;min-height:100vh}}
h1{{font-size:1.35rem;font-weight:600;color:#fff;margin-bottom:.25rem}}
.sub{{font-size:.82rem;color:#555;margin-bottom:1.8rem}}
.status-row{{display:flex;align-items:center;gap:.7rem;padding:.75rem 1rem;background:#161616;border-radius:8px;margin-bottom:1.8rem;border:1px solid #222}}
.dot{{width:10px;height:10px;border-radius:50%;flex-shrink:0;transition:background .3s}}
.dot.green{{background:#22c55e}}
.dot.amber{{background:#f59e0b;animation:blink 1s infinite}}
.dot.red{{background:#ef4444}}
@keyframes blink{{0%,100%{{opacity:1}}50%{{opacity:.25}}}}
#status-text{{font-size:.88rem}}
.section-label{{font-size:.7rem;font-weight:600;letter-spacing:.1em;text-transform:uppercase;color:#444;padding:.5rem 0 .4rem;border-bottom:1px solid #1e1e1e;margin-bottom:.35rem}}
.folder-group{{margin-bottom:1.4rem}}
.model-row{{display:flex;align-items:center;gap:.9rem;padding:.55rem .75rem;border-radius:6px;transition:background .12s}}
.model-row:hover{{background:#181818}}
.model-row.is-current{{background:#0f2318;border-left:3px solid #22c55e;padding-left:.5rem}}
.model-name{{flex:1;font-size:.9rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}
.model-size{{font-size:.78rem;color:#555;min-width:5.5rem;text-align:right;flex-shrink:0}}
.badge{{font-size:.75rem;font-weight:600;padding:.25rem .6rem;border-radius:4px;flex-shrink:0}}
.badge-current{{background:transparent;color:#22c55e;border:1px solid #22c55e33}}
.badge-loading{{background:transparent;color:#f59e0b;border:1px solid #f59e0b44;animation:blink 1s infinite}}
.btn-load{{background:#2563eb;color:#fff;border:none;font-size:.78rem;font-weight:600;padding:.3rem .85rem;border-radius:5px;cursor:pointer;transition:background .15s}}
.btn-load:hover:not(:disabled){{background:#1d4ed8}}
.btn-load:disabled{{background:#1e1e1e;color:#444;cursor:not-allowed}}
.open-ui{{display:inline-flex;align-items:center;gap:.4rem;margin-top:1.6rem;color:#3b82f6;font-size:.85rem;text-decoration:none}}
.open-ui:hover{{color:#60a5fa}}
.mcp-info{{margin-top:2rem;font-size:.75rem;color:#383838;border-top:1px solid #1a1a1a;padding-top:1rem}}
code{{font-size:.82em;background:#181818;padding:.1em .3em;border-radius:3px;color:#888}}
</style>
</head>
<body>
<h1>Bonsai Model Switcher</h1>
<p class="sub">Models from <code>{model_dir}</code> &nbsp;·&nbsp; MCP on port {mcp_port}</p>

<div class="status-row">
  <div class="dot amber" id="dot"></div>
  <span id="status-text">Connecting to llama-server...</span>
</div>

<div id="model-list"><p style="color:#444;font-size:.85rem">Scanning models...</p></div>

<a class="open-ui" href="http://localhost:{llama_port}" target="_blank">
  &#9654; Open llama.cpp Web UI
</a>

<div class="mcp-info">
  DuckDuckGo MCP endpoint: <code>http://localhost:{mcp_port}/mcp</code>
  &nbsp;·&nbsp; Tools: <code>web_search</code>, <code>news_search</code>
</div>

<script>
const LLAMA = {llama_port};
const MCP   = {mcp_port};
let models      = [];
let current     = null;   // name of loaded model
let serverReady = false;
let switching   = null;   // name of model being loaded

async function loadModels() {{
  try {{
    const r = await fetch(`http://localhost:${{MCP}}/models`);
    models = await r.json();
    render();
  }} catch(e) {{}}
}}

async function pollStatus() {{
  try {{
    const r = await fetch(`http://localhost:${{MCP}}/current`, {{cache:'no-store'}});
    const d = await r.json();
    serverReady = d.ready;
    current     = d.model;
    if (serverReady && switching && d.model === switching) switching = null;
    if (serverReady && switching) {{
      // still loading — check if port is up but wrong model
      // (can happen briefly); just wait
    }}
    updateStatus();
    render();
  }} catch(e) {{
    serverReady = false;
    current     = null;
    updateStatus();
  }}
}}

function updateStatus() {{
  const dot = document.getElementById('dot');
  const txt = document.getElementById('status-text');
  if (switching) {{
    dot.className = 'dot amber';
    txt.textContent = `Loading ${{switching}} — please wait...`;
  }} else if (serverReady) {{
    dot.className = 'dot green';
    txt.textContent = current ? `Running: ${{current}}` : 'Server ready (no model info)';
  }} else {{
    dot.className = 'dot red';
    txt.textContent = 'llama-server offline';
  }}
}}

function fmt(mb) {{
  return mb >= 1000 ? (mb/1024).toFixed(1)+' GB' : mb.toFixed(0)+' MB';
}}

function render() {{
  if (!models.length) return;
  const groups = {{}};
  for (const m of models) {{
    const g = m.folder || '(root)';
    (groups[g] = groups[g] || []).push(m);
  }}
  let html = '';
  for (const [folder, ms] of Object.entries(groups)) {{
    html += `<div class="folder-group">
      <div class="section-label">${{folder}}</div>`;
    ms.forEach((m, idx) => {{
      const isCurrent  = current && m.name === current;
      const isLoading  = switching === m.name;
      const disabled   = !!switching || !serverReady;
      let badge = '';
      if (isCurrent)     badge = `<span class="badge badge-current">&#10003; Loaded</span>`;
      else if (isLoading) badge = `<span class="badge badge-loading">Loading...</span>`;
      else badge = `<button class="btn-load" ${{disabled?'disabled':''}}
                      onclick="doSwitch(${{models.indexOf(m)}})">Load</button>`;
      html += `<div class="model-row ${{isCurrent?'is-current':''}}">
        <span class="model-name" title="${{m.name}}">${{m.name}}</span>
        <span class="model-size">${{fmt(m.size_mb)}}</span>
        ${{badge}}
      </div>`;
    }});
    html += '</div>';
  }}
  document.getElementById('model-list').innerHTML = html;
}}

async function doSwitch(idx) {{
  if (switching) return;
  const m = models[idx];
  switching = m.name;
  updateStatus();
  render();
  try {{
    await fetch(`http://localhost:${{MCP}}/switch`, {{
      method: 'POST',
      headers: {{'Content-Type':'application/json'}},
      body: JSON.stringify({{model_path: m.path}}),
    }});
  }} catch(e) {{}}
  // Poll until ready
  for (let i = 0; i < 120; i++) {{
    await new Promise(r => setTimeout(r, 1000));
    await pollStatus();
    if (!switching) break;
  }}
  switching = null;
  updateStatus();
  render();
}}

loadModels();
setInterval(pollStatus, 1500);
pollStatus();
</script>
</body>
</html>"""


if __name__ == "__main__":
    if "--streamable-http" in sys.argv:
        import uvicorn
        import json as _json
        import urllib.request
        from starlette.applications import Starlette
        from starlette.requests import Request
        from starlette.responses import HTMLResponse, JSONResponse
        from starlette.routing import Mount, Route

        async def homepage(request: Request) -> HTMLResponse:
            return HTMLResponse(_SWITCHER_HTML.format(
                mcp_port=_port,
                llama_port=_LLAMA_PORT,
                model_dir=_MODEL_DIR,
            ))

        async def api_models(request: Request) -> JSONResponse:
            return JSONResponse(_scan_models())

        async def api_current(request: Request) -> JSONResponse:
            """Proxy check to llama-server /v1/models — avoids browser CORS."""
            import asyncio
            def _check():
                try:
                    with urllib.request.urlopen(
                        f"http://127.0.0.1:{_LLAMA_PORT}/v1/models", timeout=2
                    ) as resp:
                        data = _json.loads(resp.read())
                        items = data.get("data", [])
                        model_id = items[0]["id"] if items else None
                        name = Path(model_id).name if model_id else None
                        return {"ready": True, "model": name}
                except Exception:
                    return {"ready": False, "model": None}
            result = await asyncio.get_event_loop().run_in_executor(None, _check)
            return JSONResponse(result)

        async def api_switch(request: Request) -> JSONResponse:
            data     = await request.json()
            model_path = data.get("model_path", "")
            if not model_path or not Path(model_path).exists():
                return JSONResponse({"error": "model not found"}, status_code=400)
            import asyncio
            await asyncio.get_event_loop().run_in_executor(None, _kill_llama)
            await asyncio.sleep(0.8)
            try:
                _start_llama(model_path)
            except RuntimeError as e:
                return JSONResponse({"error": str(e)}, status_code=500)
            return JSONResponse({"status": "starting", "model": Path(model_path).name})

        mcp_app = mcp.streamable_http_app()
        app = Starlette(routes=[
            Route("/",        homepage),
            Route("/models",  api_models),
            Route("/current", api_current),
            Route("/switch",  api_switch, methods=["POST"]),
            Mount("/",        app=mcp_app),
        ])
        app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        uvicorn.run(app, host="0.0.0.0", port=_port, log_level="warning")

    elif "--sse" in sys.argv:
        mcp.run(transport="sse")
    else:
        mcp.run(transport="stdio")
