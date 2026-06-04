"""DuckDuckGo web search MCP server — no API key required."""

import sys

try:
    from ddgs import DDGS  # type: ignore[import-untyped]
except ImportError:
    from duckduckgo_search import DDGS  # type: ignore[import-untyped]

from mcp.server.fastmcp import FastMCP
from starlette.middleware.cors import CORSMiddleware

_port = 8808
if "--port" in sys.argv:
    _port = int(sys.argv[sys.argv.index("--port") + 1])

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

if __name__ == "__main__":
    if "--streamable-http" in sys.argv:
        import uvicorn
        from starlette.applications import Starlette
        from starlette.requests import Request
        from starlette.responses import HTMLResponse
        from starlette.routing import Mount, Route

        async def homepage(request: Request) -> HTMLResponse:
            return HTMLResponse(f"""<!DOCTYPE html>
<html><head><title>DuckDuckGo MCP Server</title>
<style>body{{font-family:sans-serif;max-width:560px;margin:3em auto;padding:0 1.2em}}
code{{background:#f0f0f0;padding:.2em .4em;border-radius:3px}}</style></head>
<body>
<h2>DuckDuckGo MCP Server</h2>
<p>Status: <strong style="color:#2a2">Running</strong> &mdash; port {_port}</p>
<p>MCP endpoint: <code>http://localhost:{_port}/mcp</code></p>
<h3>Tools</h3>
<ul>
  <li><code>web_search(query, max_results=5)</code> &mdash; web search</li>
  <li><code>news_search(query, max_results=5)</code> &mdash; recent news</li>
</ul>
<p>Connect in the llama.cpp Web UI via <b>Settings &rarr; MCP Servers</b>.</p>
</body></html>""")

        mcp_app = mcp.streamable_http_app()
        app = Starlette(routes=[
            Route("/", homepage),
            Mount("/", app=mcp_app),
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
