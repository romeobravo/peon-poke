/**
 * peon-poke — pi (and oh-my-pi) extension
 * Buzzes the trackpad when the agent is ready for input.
 *
 * Routes through poke.sh so pattern config stays centralized in
 * config.json (default task.complete pattern: `chirp`).
 * Set POKE_ARGS to bypass poke.sh and drive bin/poke directly.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const DIR = process.env.POKE_DIR ?? join(homedir(), ".peon-poke");
const ARGS = (process.env.POKE_ARGS ?? "").split(/\s+/).filter(Boolean);

function fire(category: string) {
  try {
    const child = ARGS.length
      ? spawn(join(DIR, "bin/poke"), ARGS, { detached: true, stdio: "ignore" })
      : spawn("bash", [join(DIR, "poke.sh"), category], { detached: true, stdio: "ignore" });
    child.unref();
  } catch {
    // never let a failed poke break the session
  }
}

export default function (pi: ExtensionAPI) {
  // agent fully done (retries/compaction/follow-ups finished) and idle
  pi.on("agent_settled", async (_event, ctx) => {
    if (ctx.isIdle()) fire("task.complete");
  });

  // agent is asking the user something mid-run (permission gate, etc.)
  pi.on("ui_prompt_start", async () => {
    fire("input.required");
  });
}
