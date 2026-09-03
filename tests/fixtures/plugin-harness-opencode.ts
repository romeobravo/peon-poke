/**
 * plugin-harness-opencode.ts — loads the real peon-poke OpenCode plugin
 * and drives its event hook with a fake Plugin API.
 *
 *   bun plugin-harness-opencode.ts <path-to-peon-poke.ts>
 *
 * Exit 0 = all events handled without throwing; dispatches are recorded
 * by the stub poke.sh referenced via POKE_DIR.
 */
const pluginPath = process.argv[2];
if (!pluginPath) {
  console.error("usage: bun plugin-harness-opencode.ts <peon-poke.ts>");
  process.exit(2);
}

const mod = await import(pluginPath);
const pluginFn = mod.PeonPokePlugin;
if (typeof pluginFn !== "function") {
  console.error("no PeonPokePlugin export");
  process.exit(3);
}

const hooks = await pluginFn(
  {
    project: "proj_test",
    directory: "/",
    worktree: "/",
    serverUrl: new URL("http://127.0.0.1:1"),
    experimental_workspace: { register() {} },
    client: {} as never,
    $: {} as never,
  },
  {},
);

if (typeof hooks.event !== "function") {
  console.error("plugin returned no event hook");
  process.exit(4);
}
console.log("event hook registered");

const events = [
  { type: "session.idle", properties: { sessionID: "ses_1" } },
  { type: "session.error", properties: { sessionID: "ses_1" } },
  { type: "permission.updated", properties: { sessionID: "ses_1", title: "run command" } },
  { type: "session.created", properties: { sessionID: "ses_2" } },
  { type: "message.updated", properties: {} }, // must be ignored
  { type: "totally.unknown", properties: {} }, // must be ignored
];

for (const event of events) {
  await hooks.event({ event: event as never });
}

setTimeout(() => process.exit(0), 400);
