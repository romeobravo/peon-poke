/**
 * peon-poke — OpenCode plugin
 * Managed by peon-poke-setup: reinstalling peon-poke refreshes this file.
 *
 * Auto-discovered from ~/.config/opencode/plugin/ (no config edits
 * needed). opencode scans both plugin/ and plugins/ — verified against
 * 1.18.27 — so the singular dir stays supported.
 * Routes through the peon-poke CLI so pattern config stays centralized in
 * ~/.config/peon-poke/config.json.
 *
 * Event contract verified against @opencode-ai/sdk 1.18 (Event union):
 *   session.idle       agent finished responding        -> task.complete
 *   session.error      session errored                  -> task.error
 *   permission.updated a permission is awaiting the user -> input.required
 *   session.created    new session (off by default)     -> session.start
 */
import type { Plugin } from "@opencode-ai/plugin";
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const DIR = process.env.POKE_DIR ?? join(homedir(), ".peon-poke");

function fire(category: string) {
  try {
    const child = spawn(join(DIR, "bin/peon-poke"), ["dispatch", category], {
      detached: true,
      stdio: "ignore",
    });
    // spawn() failures (ENOENT, EACCES) arrive as an ASYNC "error" event —
    // without a listener they would crash the host. A missed poke must
    // never take the session down.
    child.on("error", () => {});
    child.unref();
  } catch {
    // never let a failed poke break the session
  }
}

export const PeonPokePlugin: Plugin = async () => ({
  event: async ({ event }) => {
    switch (event.type) {
      case "session.idle":
        fire("task.complete");
        break;
      case "session.error":
        fire("task.error");
        break;
      case "permission.updated":
        fire("input.required");
        break;
      case "session.created":
        fire("session.start");
        break;
    }
  },
});
