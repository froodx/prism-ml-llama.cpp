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
        app = mcp.streamable_http_app()
        # Force middleware stack rebuild so CORS is applied
        app.middleware_stack = None
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
