"""DuckDuckGo web search MCP server — no API key required."""

from mcp.server.fastmcp import FastMCP

try:
    from ddgs import DDGS
except ImportError:
    from duckduckgo_search import DDGS  # legacy name

mcp = FastMCP("duckduckgo-search")

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
    mcp.run(transport="stdio")
