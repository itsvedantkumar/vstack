# MCP servers

`install.sh` merges `servers.json` into the global `mcpServers` map in `~/.claude.json` and
substitutes `__HOME__` at install time. Global servers load in every session, so only servers
you want everywhere belong here.

Two servers ship globally:

| server | needs | notes |
|---|---|---|
| `cloudflare-mcp` | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` in `secrets.env` | wrapper at `bin/cloudflare-mcp`. Set `CLOUDFLARE_MCP_DIST` if the server lives outside `~/Projects/cloudflare-mcp` |
| `context7` | nothing | fetches current library docs. Runs via `npx` |

## Project-scoped servers

Scope a server that only matters in one repo to that repo instead of loading it globally.
Doing so keeps the tool list, and its token cost, out of every other session. Add it under
the project key in `~/.claude.json`:

```bash
jq '.projects["/abs/path/to/repo"].mcpServers["namecheap"] =
    {"type":"stdio","command":"'"$HOME"'/.config/agents/bin/namecheap-mcp","args":[]}' \
  ~/.claude.json > /tmp/cj && jq -e . /tmp/cj >/dev/null && mv /tmp/cj ~/.claude.json
```

`bin/namecheap-mcp` ships as a ready wrapper on this basis. Nothing loads it until you scope
it to a project, as shown above.

## Add credentials

Every wrapper sources `~/.config/agents/secrets.env` before exec. Add the variable there,
never in `servers.json`. That file is committed.
