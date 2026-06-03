# Local Setup — Bonsai + DuckDuckGo MCP

This documents the Windows/Linux scripts added to this fork on top of the upstream Prism-ML and llama.cpp codebases.

## What's been added

| File | Purpose |
|------|---------|
| `launch.ps1` / `launch.sh` | **Main entry point** — picks model, starts MCP server, opens Web UI |
| `cmake-build.ps1` / `cmake-build.sh` | One-shot CPU-only build |
| `setup-mcp-search.ps1` / `setup-mcp-search.sh` | Install DuckDuckGo MCP deps |
| `start-mcp-search.ps1` / `start-mcp-search.sh` | Run the MCP HTTP/SSE server |
| `mcp-duckduckgo/server.py` | FastMCP server wrapping DuckDuckGo (web + news search) |
| `mcp-duckduckgo/requirements.txt` | Python deps: `mcp`, `duckduckgo-search` |
| `webui-config.json` | Pre-configures the MCP server URL in the llama.cpp Web UI |

## Quick start — Windows

```powershell
# 1. Build (first time only, takes 5-15 min)
.\cmake-build.ps1

# 2. Install MCP deps (first time only)
.\setup-mcp-search.ps1

# 3. Launch — picks model, starts everything, opens browser
.\launch.ps1
```

## Quick start — Linux / Ubuntu

```bash
# 1. Build (first time only)
./cmake-build.sh

# 2. Install MCP deps (first time only)
./setup-mcp-search.sh

# 3. Launch — picks model, starts everything, opens browser
./launch.sh
```

On Linux the models are looked up in `~/models/` by default.
Override with the `MODELS_DIR` env var:

```bash
MODELS_DIR=/data/llms ./launch.sh
```

## Models

Two Bonsai models are supported. Download from HuggingFace and place them in your models directory:

| Model | Size | Speed |
|-------|------|-------|
| `Bonsai-1.7B-Q1_0.gguf` | ~250 MB | Fast |
| `Bonsai-8B-Q1_0.gguf` | ~1.5 GB | Smarter |

Windows default path: `C:\Local\Local-LLMs\1-Bit-Bonsai\`

## DuckDuckGo MCP Search

The Web UI at `http://localhost:8080` has search built in via the MCP server running on port `8808`.

- **No API key needed** — uses DuckDuckGo freely
- Two tools available to the model: `web_search` and `news_search`
- The `webui-config.json` pre-configures the MCP endpoint so no manual setup is needed

To ask the model to search: just say "search the web for X" or "find recent news about Y".

## Ports

| Service | Port |
|---------|------|
| llama-server Web UI | 8080 |
| DuckDuckGo MCP (SSE) | 8808 |

## Architecture

```
Browser  ──►  llama-server :8080  (Bonsai model, --webui-mcp-proxy)
                    │
                    └──►  MCP proxy  ──►  supergateway :8808  ──►  Python server  ──►  DuckDuckGo
```
