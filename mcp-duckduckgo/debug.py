"""Debug script — run this to see exactly what's broken."""
import sys, traceback

print(f"Python: {sys.version}")
print()

# Test 1: mcp import
try:
    import mcp
    print(f"OK  mcp installed")
except Exception as e:
    print(f"FAIL mcp import: {e}")
    sys.exit(1)

# Test 2: FastMCP
try:
    from mcp.server.fastmcp import FastMCP
    server = FastMCP("test")
    print(f"OK  FastMCP")
except Exception as e:
    print(f"FAIL FastMCP: {e}")
    traceback.print_exc()
    sys.exit(1)

# Test 3: ddgs
try:
    from ddgs import DDGS
    print(f"OK  ddgs")
except Exception as e:
    try:
        from duckduckgo_search import DDGS
        print(f"OK  duckduckgo_search (legacy)")
    except Exception as e2:
        print(f"FAIL ddgs: {e} / {e2}")
        sys.exit(1)

# Test 4: actual search
try:
    results = list(DDGS().text("python", max_results=2))
    print(f"OK  search ({len(results)} results)")
    if results:
        print(f"    keys: {list(results[0].keys())}")
except Exception as e:
    print(f"FAIL search: {e}")
    traceback.print_exc()

# Test 5: full server.py import
print()
try:
    import importlib.util, pathlib
    spec = importlib.util.spec_from_file_location(
        "server",
        pathlib.Path(__file__).parent / "server.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    print(f"OK  server.py imports cleanly")
except Exception as e:
    print(f"FAIL server.py: {e}")
    traceback.print_exc()
