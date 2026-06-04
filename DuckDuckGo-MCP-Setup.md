# DuckDuckGo MCP Server — Setup & Usage

Adds web search and news search to the llama.cpp Web UI via the Model Context Protocol (MCP). No API key required.

---

## Files

| File | Purpose |
|------|---------|
| `mcp-duckduckgo/server.py` | MCP server (FastMCP + DDGS) |
| `mcp-duckduckgo/requirements.txt` | Python deps: `mcp`, `ddgs` |
| `webui-config.json` | Tells llama.cpp Web UI where the MCP server lives |
| `start-mcp-search.ps1` | Standalone: start MCP server only |
| `launch.ps1` | Full launcher: starts MCP server + llama-server together |

---

## Quick Start (recommended)

Run the full launcher — it starts the MCP server and llama-server in one step:

```powershell
.\launch.ps1
```

Then open **http://localhost:8080** in your browser. Click **MCP Servers** in the sidebar — "DuckDuckGo Search" should show as connected.

---

## MCP Server Only

To start just the MCP server (useful for testing or if llama-server is already running):

```powershell
.\start-mcp-search.ps1
```

Or manually:

```powershell
$env:PYTHONUNBUFFERED = "1"
npx supergateway --port 8808 --cors --stdio "python -u mcp-duckduckgo\server.py"
```

The server listens at: **http://localhost:8808/sse**

---

## Adding the MCP Server in the Web UI

If the server isn't auto-detected, add it manually in the UI:

1. Open **http://localhost:8080**
2. Go to **Settings → MCP**
3. Click **+ Add New Server**
4. Enter:
   - **URL**: `http://localhost:8808/sse`
   - **Name**: `DuckDuckGo Search`
5. Click **Save settings**

---

## Available Tools

| Tool | Description |
|------|-------------|
| `web_search` | Web search — returns titles, URLs, and snippets |
| `news_search` | News search — returns headlines, URLs, dates |

Both accept `query: str` and `max_results: int` (default 5).

---

## First-Time Setup

Install Python dependencies once:

```powershell
pip install mcp ddgs
```

Verify everything works:

```powershell
python -c "from ddgs import DDGS; r=list(DDGS().text('test',max_results=1)); print(r[0]['title'])"
npx supergateway --version
```

---

## Troubleshooting

**Pylance shows "import could not be resolved"**
This is a false positive — Pylance uses a different Python environment than the one where `ddgs` is installed. The server runs fine. The `pyrightconfig.json` in `mcp-duckduckgo/` suppresses these warnings.

**Port 8808 already in use**
```powershell
Get-NetTCPConnection -LocalPort 8808 | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

**Server starts but llama.cpp Web UI doesn't connect**
Make sure `webui-config.json` exists at the project root and llama-server is started with the `--webui-config-file` flag (handled automatically by `launch.ps1`).
