# Can OpenCode host a Stop gate? Feasibility, and what vstack does with the answer

Provenance: drafted 2026-09-03 by a GLM 5.3 Flash research agent (OpenCode Go) against the
`sst/opencode` dev tree and the published docs, brief at `/tmp/glm-research/opencode-gate/`.
Read and used by RICK the same day; the "What vstack does with it" section at the end is RICK's.

Why it matters here: the showcase benchmark found its only false completions on bare GLM 5.3
Flash, not on any Claude arm (see `measured-so-far.md`). vstack's false-done gate is a Claude
Code Stop hook. To test whether the gate itself changes that number, the gate has to run where the
false completions happen, and vstack's hooks do not load in OpenCode.


Question: can an OpenCode (opencode.ai, open-source CLI coding agent, 1.18.x) plugin or configuration implement a stop gate that runs a shell command (for example a test suite) when the agent is about to finish its turn or the session goes idle, blocks completion on non-zero exit, sends the failure output back to the model as a new message so it keeps working, with a cap on retries?

Short answer: a plugin can observe session idle and can start a follow-up turn by calling `client.session.prompt` with the failure output, with a retry cap implemented in the plugin. What it cannot do is veto or block the completion itself: no hook fires before turn end with the power to stop it, and under `opencode run` headless the CLI exits at the first idle event, so a plugin-driven continuation races process exit. Details and evidence below.

Sources used (all fetched or read on Sep 3 2026):

- https://opencode.ai/docs/plugins/ (last updated Sep 2, 2026)
- https://opencode.ai/docs/config/ (last updated Sep 2, 2026)
- https://opencode.ai/docs/sdk/ (last updated Sep 2, 2026)
- https://raw.githubusercontent.com/sst/opencode/dev/packages/plugin/src/index.ts
- Full dev-branch source tree, cloned from https://github.com/sst/opencode (shallow clone of `dev`, HEAD commit `4eb29a6`, `packages/opencode/package.json` version `1.18.26`). File references below are relative to that tree.
- https://opencode.ai/docs/hooks/ returns HTTP 404. No hooks documentation page exists. The docs site has no page between "Custom Tools" and "Develop" named hooks; hook material lives only in the plugins page and the plugin package source.

Caveat: the dev branch moves; the released 1.18.x may differ in minor ways. The hook names in section 1 match the plugins docs page event list, so the two sources agree.

## 1. Plugin hook names and signatures

From `packages/plugin/src/index.ts`, the plugin entry point and hook container are:

```ts
export type PluginInput = {
  client: ReturnType<typeof createOpencodeClient>
  project: Project
  directory: string
  worktree: string
  experimental_workspace: {
    register(type: string, adapter: WorkspaceAdapter): void
  }
  serverUrl: URL
  $: BunShell
}

export type Plugin = (input: PluginInput, options?: PluginOptions) => Promise<Hooks>
```

The `Hooks` interface, quoted from the same file (this is the complete set of hook names a server-side plugin can implement):

```ts
export interface Hooks {
  dispose?: () => Promise<void>
  event?: (input: { event: Event }) => Promise<void>
  config?: (input: Config) => Promise<void>
  tool?: {
    [key: string]: ToolDefinition
  }
  auth?: AuthHook
  provider?: ProviderHook
  /**
   * Called when a new message is received
   */
  "chat.message"?: (
    input: {
      sessionID: string
      agent?: string
      model?: { providerID: string; modelID: string }
      messageID?: string
      variant?: string
    },
    output: { message: UserMessage; parts: Part[] },
  ) => Promise<void>
  /**
   * Modify parameters sent to LLM
   */
  "chat.params"?: (
    input: { sessionID: string; agent: string; model: Model; provider: ProviderContext; message: UserMessage },
    output: {
      temperature: number
      topP: number
      topK: number
      maxOutputTokens: number | undefined
      options: Record<string, any>
    },
  ) => Promise<void>
  "chat.headers"?: (
    input: { sessionID: string; agent: string; model: Model; provider: ProviderContext; message: UserMessage },
    output: { headers: Record<string, string> },
  ) => Promise<void>
  "permission.ask"?: (input: Permission, output: { status: "ask" | "deny" | "allow" }) => Promise<void>
  "command.execute.before"?: (
    input: { command: string; sessionID: string; arguments: string },
    output: { parts: Part[] },
  ) => Promise<void>
  "tool.execute.before"?: (
    input: { tool: string; sessionID: string; callID: string },
    output: { args: any },
  ) => Promise<void>
  "shell.env"?: (
    input: { cwd: string; sessionID?: string; callID?: string },
    output: { env: Record<string, string> },
  ) => Promise<void>
  "tool.execute.after"?: (
    input: { tool: string; sessionID: string; callID: string; args: any },
    output: {
      title: string
      output: string
      metadata: any
    },
  ) => Promise<void>
  "experimental.chat.messages.transform"?: (
    input: {},
    output: {
      messages: {
        info: Message
        parts: Part[]
      }[]
    },
  ) => Promise<void>
  "experimental.chat.system.transform"?: (
    input: { sessionID?: string; model: Model },
    output: {
      system: string[]
    },
  ) => Promise<void>
  "experimental.provider.small_model"?: (input: { provider: ProviderV2 }, output: { model?: ModelV2 }) => Promise<void>
  /**
   * Called before session compaction starts. Allows plugins to customize
   * the compaction prompt.
   */
  "experimental.session.compacting"?: (
    input: { sessionID: string },
    output: { context: string[]; prompt?: string },
  ) => Promise<void>
  /**
   * Called after compaction succeeds and before a synthetic user
   * auto-continue message is added.
   */
  "experimental.compaction.autocontinue"?: (
    input: {
      sessionID: string
      agent: string
      model: Model
      provider: ProviderContext
      message: UserMessage
      overflow: boolean
    },
    output: { enabled: boolean },
  ) => Promise<void>
  "experimental.text.complete"?: (
    input: { sessionID: string; messageID: string; partID: string },
    output: { text: string },
  ) => Promise<void>
  /**
   * Modify tool definitions (description and parameters) sent to LLM
   */
  "tool.definition"?: (input: { toolID: string }, output: { description: string; parameters: any }) => Promise<void>
}
```

Besides these named hooks, the generic `event` hook receives every server event. The plugins docs list the event types, which include, under Session Events: `session.created`, `session.compacted`, `session.deleted`, `session.diff`, `session.error`, `session.idle`, `session.status`, `session.updated`; and under Tool Events: `tool.execute.after`, `tool.execute.before`; plus `permission.asked`, `message.updated`, `message.part.updated`, and others.

How hooks are dispatched, from `packages/opencode/src/plugin/index.ts`. The `event` hook is called fire-and-forget:

```ts
return Effect.sync(() => {
  for (const hook of hooks) {
    void hook["event"]?.({ event: { id: event.id, type: event.type, properties: event.data } as any })
  }
})
```

The `void` matters: an async `event` hook cannot delay anything downstream, including the CLI's exit. Named hooks run through `Plugin.trigger`, which awaits each hook sequentially and returns the mutated `output` object.

## 2. What fires at turn end or idle, and how a plugin keeps the session going

There is no hook that fires before turn completion. The turn loop in `packages/opencode/src/session/processor.ts` returns `"continue" | "stop" | "compact"` internally and no plugin hook participates in that decision. What a plugin can observe is the post-hoc idle signal. `packages/opencode/src/session/status.ts` publishes both a status event and a dedicated idle event when a session finishes:

```ts
const set = Effect.fn("SessionStatus.set")(function* (sessionID: SessionID, status: Info) {
  const data = yield* InstanceState.get(state)
  yield* events.publish(Event.Status, { sessionID, status })
  if (status.type === "idle") {
    yield* events.publish(Event.Idle, { sessionID })
    data.delete(sessionID)
    return
  }
  data.set(sessionID, status)
})
```

So a plugin's `event` hook receives `{ type: "session.idle", properties: { sessionID } }` (and a `session.status` event whose `properties.status.type` is `"idle"`) when the turn is over. The docs' notification example confirms this is the intended "session completed" signal:

```js
event: async ({ event }) => {
  // Send notification on session completion
  if (event.type === "session.idle") {
    await $`osascript -e 'display notification "Session completed!" with title "opencode"'`
  }
}
```

Injecting a follow-up message: yes, through the SDK client the plugin receives in its input. The SDK docs document `client.session.prompt`:

- `session.prompt({ path, body })`, "Send prompt message", default returns an `AssistantMessage` with the AI response.
- `body.noReply: true` "returns UserMessage (context only)", documented as "Inject context without triggering AI response (useful for plugins)".

So the stop-gate pattern is: on `session.idle`, run the gate command with Bun's `$`, and on failure call

```ts
await client.session.prompt({
  path: { id: sessionID },
  body: { parts: [{ type: "text", text: failureReport }] },
})
```

without `noReply`, which starts a new turn in the same session with the failure output as the user message. Do not set `noReply: true` here; that injects context without triggering a response.

The headless `opencode run` problem: the non-interactive CLI subscribes to the event stream, streams output, and exits when it sees the first idle status for the session. From `packages/opencode/src/cli/cmd/run.ts`:

```ts
if (
  event.type === "session.status" &&
  event.properties.sessionID === sessionID &&
  event.properties.status.type === "idle"
) {
  break
}
```

After the loop breaks, the command returns and the process (which hosts the server in-process) tears down. Because the plugin `event` hook is invoked with `void` (fire-and-forget, quoted in section 1) at the same moment the idle event is published, the plugin's subsequent gate run and `session.prompt` call race the CLI's exit. I verified the exit-on-idle behavior in the source; I did not empirically measure whether an injected prompt sometimes completes before teardown, and nothing in the source makes that a supported contract. Conclusion: the idle-gate plugin works where the process stays alive (TUI, `opencode serve`, an SDK-driven client). Under bare `opencode run` it is not reliable, and the deterministic headless options are (a) drive the loop from the outside with the SDK (`createOpencodeClient`, `event.subscribe()`, `session.prompt` on failure), or (b) run the gate as a custom tool inside the turn, described in sections 4 and 5.

For completeness: `client.tui.appendPrompt` and `client.tui.submitPrompt` exist but are TUI-only, and `client.session.command` sends a slash command. `experimental.compaction.autocontinue` is the one hook that touches the loop's auto-continue behavior, but only to set `output.enabled: false` (skip the synthetic continue after compaction), and it fires only in the compaction path, not at normal turn end.

## 3. Blocking a tool call and reading tool results

Blocking a tool call: yes, from `tool.execute.before`. The plugins docs' .env protection example throws inside the hook:

```js
"tool.execute.before": async (input, output) => {
  if (input.tool === "read" && output.args.filePath.includes(".env")) {
    throw new Error("Do not read .env files")
  }
}
```

The trigger site in `packages/opencode/src/session/tools.ts` runs the hook before the tool executes, so a throw fails the tool call and the error surfaces to the model:

```ts
yield* plugin.trigger(
  "tool.execute.before",
  { tool: item.id, sessionID: ctx.sessionID, callID: ctx.callID },
  { args },
)
const result = yield* item.execute(args, ctx)
```

The same hook can also rewrite `output.args` before execution (the docs' shell-escaping example does this).

Reading tool results: yes, from `tool.execute.after`, which receives the completed result and can mutate it:

```ts
yield* plugin.trigger(
  "tool.execute.after",
  { tool: item.id, sessionID: ctx.sessionID, callID: ctx.callID, args },
  output,
)
```

with `output: { title: string; output: string; metadata: any }` per the signature in section 1.

The `permission.ask` hook is declared in the Hooks interface (quoted in section 1):

```ts
"permission.ask"?: (input: Permission, output: { status: "ask" | "deny" | "allow" }) => Promise<void>
```

I searched every `plugin.trigger` call site in `packages/opencode/src` and `packages/core/src` and found no site that triggers `"permission.ask"`. The permission machinery I found (`packages/opencode/src/permission/index.ts`, `packages/core/src/permission.ts`) evaluates config rulesets, publishes `permission.asked` / `permission.replied` events, and parks the tool on a deferred until answered; none of it calls the plugin hook. So I cannot confirm from source that `permission.ask` fires in this build, and a stop gate should not depend on it. The observable, documented path is the `permission.asked` event plus the SDK reply call; `run.ts` itself answers permission requests this way:

```ts
await client.permission.reply({
  requestID: permission.id,
  reply: "once",  // or "reject" when not auto-approved
})
```

Note this is not usable as a stop gate either: permission requests happen per tool call during the turn, and the CLI in non-interactive mode auto-rejects them unless `--auto` is passed.

## 4. Minimal plugin sketch

Design A: idle-event gate. Runs the gate when the session goes idle and, on failure and under the cap, injects the failure output as a new user message via `client.session.prompt`. This is the direct answer to the question and works wherever the host process survives the idle event (TUI, `opencode serve`, SDK-driven sessions). Under bare `opencode run` headless it races the CLI's exit, per section 2.

```ts
// .opencode/plugins/stop-gate.ts
import type { Plugin } from "@opencode-ai/plugin"

const MAX_ATTEMPTS = 3
const attempts = new Map<string, number>()
const busy = new Set<string>()

export const StopGate: Plugin = async ({ client, $ }) => {
  return {
    event: async ({ event }) => {
      if (event.type !== "session.idle") return
      const sessionID = (event.properties as { sessionID?: string }).sessionID
      if (!sessionID || busy.has(sessionID)) return
      if ((attempts.get(sessionID) ?? 0) >= MAX_ATTEMPTS) return // cap reached: let it end
      busy.add(sessionID)
      try {
        const proc = await $`npm test`.quiet().nothrow()
        if (proc.exitCode === 0) {
          attempts.delete(sessionID)
          return
        }
        const n = (attempts.get(sessionID) ?? 0) + 1
        attempts.set(sessionID, n)
        if (n >= MAX_ATTEMPTS) return // failed but cap reached: let it end
        const tail =
          ("" + proc.stderr).slice(-4000) + ("\n" + proc.stdout).slice(-2000)
        await client.session.prompt({
          path: { id: sessionID },
          body: {
            parts: [
              {
                type: "text",
                text:
                  `STOP GATE FAILED: \`npm test\` exited ${proc.exitCode} (gate attempt ${n}/${MAX_ATTEMPTS}). ` +
                  `Fix the failures so the suite passes, then finish.\n\n${tail}`,
              },
            ],
          },
        })
      } finally {
        busy.delete(sessionID)
      }
    },
  }
}
```

That is 41 lines. `$` is Bun's shell from the plugin input; `.nothrow()` returns the process with `exitCode` instead of throwing, `.quiet()` captures output. The `busy` set guards against double-fire, the per-session counter is the retry cap, and a passing run clears the count. Place the file in `.opencode/plugins/` (project) or `~/.config/opencode/plugins/` (global); the docs say files there are loaded automatically at startup.

Design B: gate as a custom tool, which does work deterministically under `opencode run` headless. A custom tool executes inside the turn, so the CLI is still listening while it runs, and its string return value goes straight back to the model as the tool result. Pair it with one line in AGENTS.md or the agent prompt: "Always call the stop_gate tool before you finish; if it reports FAIL, fix the code and call it again."

```ts
// .opencode/plugins/stop-gate-tool.ts
import { type Plugin, tool } from "@opencode-ai/plugin"

const MAX_ATTEMPTS = 3
const calls = new Map<string, number>()

export const StopGateTool: Plugin = async ({ $ }) => {
  return {
    tool: {
      stop_gate: tool({
        description:
          "Runs the full test suite. Call this before finishing. " +
          "If it returns FAIL, fix the code and call it again.",
        args: {},
        async execute(_args, ctx) {
          const n = (calls.get(ctx.sessionID) ?? 0) + 1
          calls.set(ctx.sessionID, n)
          if (n > MAX_ATTEMPTS) {
            return `Retry cap (${MAX_ATTEMPTS}) reached. Report current status and finish.`
          }
          const proc = await $`npm test`.quiet().nothrow()
          if (proc.exitCode === 0) {
            calls.delete(ctx.sessionID)
            return "PASS: test suite green. You may finish."
          }
          const tail = ("" + proc.stderr).slice(-4000) + ("\n" + proc.stdout).slice(-2000)
          return `FAIL (gate attempt ${n}/${MAX_ATTEMPTS}): exit ${proc.exitCode}\n${tail}`
        },
      }),
    },
  }
}
```

The docs document the `tool` helper and note "If a plugin tool uses the same name as a built-in tool, the plugin tool takes precedence." Weakness of Design B: it is advisory, not a hard gate, since the model could skip the call; there is no hook that forces a tool invocation at turn end.

## 5. What cannot be done, and why

- No veto of turn completion. The Hooks interface (section 1) contains no "before finish" or "session.idle before" hook with a blocking output. The processor's continue/stop/compact decision in `packages/opencode/src/session/processor.ts` runs without plugin participation. `session.idle` is published after the turn is over, and the `event` hook is invoked fire-and-forget (`void hook["event"]?.(...)` in `packages/opencode/src/plugin/index.ts`), so it cannot delay or block anything. "Block completion" in the literal sense is not implementable; the gate can only react and re-prompt.
- Not reliably under `opencode run` for plugin-driven continuation. The CLI breaks its event loop at the first `session.status` idle and exits (quoted in section 2). A plugin that starts a follow-up `session.prompt` at idle is racing process teardown, with no source-level guarantee. The supported headless patterns are an SDK-side driver loop or the in-turn custom tool (Design B).
- The `permission.ask` hook is declared but I found no trigger site in the dev tree (section 3), so gating on it is not evidence-backed. Config-level `permission` rules can deny or ask per tool, but that is per tool call, not per turn end.
- No config-only stop gate. I read the full config schema docs (model, agent, command, hooks-adjacent options such as `formatter`, `lsp`, `mcp`, `permission`, `compaction`, `experimental`); there is no option that runs a command at turn end or blocks completion. Plugins are the extension point for this.
- No assistant-message injection or forged tool results. The plugin can add user messages (`session.prompt`), inject context without a reply (`noReply: true`), or mutate tool args and tool outputs in-flight (`tool.execute.before` / `tool.execute.after`). `experimental.chat.messages.transform` can rewrite the message list sent to the LLM, but it fires when LLM input is prepared (call sites in `session/prompt.ts` and `session/compaction.ts`), that is, at the start of a turn, so it cannot trigger a new turn by itself. Making the model "keep working" must go through `session.prompt`.
- No built-in retry cap. Nothing in the hooks or config counts gate attempts; the cap must live in plugin state, as in the sketches. Restarting the server resets an in-memory counter, which is the cap's main soft spot.

## 6. What vstack does with it (RICK, 2026-09-03)

The report's conclusion: a plugin can observe idle and re-prompt, but it cannot veto a turn end,
and `opencode run` exits at the first idle event, so a plugin-side gate races process exit.

So the gate for the OpenCode engine lives in the harness, not in the agent. The `gate` arm in
`tests/evals/showcase/run.sh` reproduces `verify-gate.sh`'s semantics from outside the process:
run the agent once; run the fixture's visible `verify.sh`; while it is red and the round count is
under the cap of three, continue the same session (`opencode run --session <id>`) with the
verification output and the instruction to fix the code, not the tests; then score the held-out
checks as for every other arm. The row records `gate_rounds`, the number of red rounds the driver
fed back, so a gate that never fired is visible as a zero and not as a green.

That makes the experiment "bare GLM vs gated GLM on a fixture with visible tests", the one
comparison every Claude arm was unable to give because Claude never produced a false completion.
The numbers are in `measured-so-far.md` once the run lands.
