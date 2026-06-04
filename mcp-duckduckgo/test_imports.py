"""Quick import and search test — run before starting the server."""
import sys

try:
    from mcp.server.fastmcp import FastMCP
    print("OK: mcp.server.fastmcp")
except ImportError as e:
    print(f"FAIL mcp: {e}")
    sys.exit(1)

# ddgs is the new name; fall back to duckduckgo_search if needed
try:
    from ddgs import DDGS
    print("OK: ddgs")
except ImportError:
    try:
        from duckduckgo_search import DDGS
        print("OK: duckduckgo_search (legacy name)")
    except ImportError as e:
        print(f"FAIL ddgs/duckduckgo_search: {e}")
        sys.exit(1)

try:
    results = list(DDGS().text("llama.cpp", max_results=2))
    print(f"OK: search returned {len(results)} results")
    print(f"   First: {results[0]['title'][:60]}")
except Exception as e:
    print(f"FAIL search: {e}")
    sys.exit(1)

print("\nAll OK — server.py should work.")
