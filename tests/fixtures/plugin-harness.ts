/**
 * plugin-harness.ts — loads the real peon-poke pi extension and fires its
 * events against a fake ExtensionAPI. Used by tests/test-plugin.sh.
 *
 *   bun plugin-harness.ts <path-to-poke.ts>
 *
 * Exit 0 = both events handled without an unhandled spawn error; any
 * unhandled 'error' event (missing POKE_DIR binaries) crashes bun with a
 * nonzero exit — that is the regression we guard against.
 */
const pluginPath = process.argv[2];
if (!pluginPath) {
  console.error("usage: bun plugin-harness.ts <poke.ts>");
  process.exit(2);
}

const mod = await import(pluginPath);
const handlers: Record<string, Array<(ev: unknown, ctx: unknown) => unknown>> = {};
const fakePi = {
  on(event: string, fn: (ev: unknown, ctx: unknown) => unknown) {
    (handlers[event] ??= []).push(fn);
  },
};

mod.default(fakePi);

const registered = Object.keys(handlers).sort();
console.log(`registered: ${registered.join(",")}`);

for (const fn of handlers["agent_settled"] ?? []) {
  await fn({}, { isIdle: () => true });
}
for (const fn of handlers["ui_prompt_start"] ?? []) {
  await fn({});
}

// let async spawn errors surface before declaring success
setTimeout(() => process.exit(0), 400);
