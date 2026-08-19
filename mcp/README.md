# MCP servers

`servers.json` is merged into the **global** `mcpServers` map in `~/.claude.json` by
`install.sh`. Global servers load in every session, so only servers you want everywhere
belong here. `__HOME__` is substituted at install time.

Two servers ship globally:

| server | needs | notes |
|---|---|---|
| `cloudflare-mcp` | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` in `secrets.env` | wrapper at `bin/cloudflare-mcp`; set `CLOUDFLARE_MCP_DIST` if the server lives outside `~/Projects/cloudflare-mcp` |
| `context7` | nothing | fetches current library docs; runs via `npx` |

## Project-scoped servers

A server that only matters in one repo should be scoped to that repo instead — it keeps the
tool list (and its token cost) out of every other session. Add it under the project key in
`~/.claude.json`:

```bash
jq '.projects["/abs/path/to/repo"].mcpServers["namecheap"] =
    {"type":"stdio","command":"'"$HOME"'/.config/agents/bin/namecheap-mcp","args":[]}' \
  ~/.claude.json > /tmp/cj && jq -e . /tmp/cj >/dev/null && mv /tmp/cj ~/.claude.json
```

`bin/` ships wrappers for `namecheap-mcp` and `spaceship-mcp` on this basis: the wrapper is
installed and ready, but nothing loads it until you scope it to a project.

## Adding credentials

Every wrapper sources `~/.config/agents/secrets.env` before exec. Add the variable there,
never in `servers.json` — that file is committed.
