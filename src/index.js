import { Plugin, Skill } from "@opencode/plugin";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { agents, commands, skills } from "./assets.js";

const PLUGIN_ID = "opencode-lite-subagent";
const MANIFEST = `.${PLUGIN_ID}.json`;
const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)));

function configRoot() {
  const base = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  return join(base, "opencode");
}

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

function readJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return fallback;
  }
}

function warn(message) {
  console.warn(`[${PLUGIN_ID}] ${message}`);
}

// Agents have no editor.add in the V2 agent transform, so they are materialized
// as files. The manifest remembers which content this plugin installed: a file
// the user edited (or that predates the plugin) is never overwritten.
function installAgents(root) {
  const directory = join(root, "agents");
  const manifestPath = join(root, MANIFEST);
  const manifest = readJson(manifestPath, { version: 1, files: {} });
  manifest.files ??= {};

  let changed = false;

  for (const agent of agents) {
    const name = `${agent.id}.md`;
    const target = join(directory, name);
    const next = sha256(agent.content);

    let current;
    try {
      current = sha256(readFileSync(target, "utf8"));
    } catch {
      current = undefined;
    }

    if (current === next) {
      if (manifest.files[name] !== next) {
        manifest.files[name] = next;
        changed = true;
      }
      continue;
    }

    if (current !== undefined && manifest.files[name] !== current) {
      warn(`skip ${target}: existing file is not the version installed by this plugin`);
      continue;
    }

    try {
      mkdirSync(directory, { recursive: true });
      writeFileSync(target, agent.content);
      manifest.files[name] = next;
      changed = true;
    } catch (error) {
      warn(`could not write ${target}: ${error.message}`);
    }
  }

  if (changed) {
    try {
      writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    } catch (error) {
      warn(`could not write ${manifestPath}: ${error.message}`);
    }
  }
}

function runShell(command, cwd) {
  try {
    return execFileSync("/bin/sh", ["-c", command], {
      cwd,
      encoding: "utf8",
      timeout: 5000,
      maxBuffer: 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    const output = [error.stdout, error.stderr].filter(Boolean).join("\n").trim();
    return output || `(command failed: ${command})`;
  }
}

function renderCommand(command, argumentsText, cwd) {
  let text = command.body.replaceAll("$ARGUMENTS", () => argumentsText);

  text = text.replace(/!`([^`]+)`/g, (_match, shellCommand) => {
    const output = runShell(shellCommand, cwd);
    return output ? `\`\`\`\n${output}\n\`\`\`` : "";
  });

  if (!command.agent) return text;

  // A command transform has no agent field, so the binding is expressed in the
  // prompt. Running the command is the authorization for this delegation.
  return `> 用 \`${command.agent}\` 子 agent 执行本命令（命令即授权）。\n\n${text}`;
}

async function registerCommands(ctx) {
  if (typeof ctx.command?.transform !== "function") {
    warn("command transform is unavailable; /scout and /review were not registered");
    return;
  }

  await ctx.command.transform((editor) => {
    for (const command of commands) {
      editor.add({
        name: command.name,
        description: command.description,
        execute: async ({ sessionID, prompt, delivery }) => {
          const text = renderCommand(command, prompt.text ?? "", ctx.location.directory);
          await ctx.session.prompt({ ...prompt, sessionID, text, delivery });
        },
      });
    }
  });
}

async function registerSkills(ctx) {
  if (typeof ctx.skill?.transform !== "function") {
    warn("skill transform is unavailable; the delegate skill was not registered");
    return;
  }

  await ctx.skill.transform((editor) => {
    for (const skill of skills) {
      editor.add({
        id: Skill.ID.make(skill.id),
        name: Skill.Name.make(skill.name),
        description: skill.description,
        path: Skill.Info.fields.path.make(
          join(packageRoot, "config", "skills", skill.id, "SKILL.md"),
        ),
        content: skill.content,
        autoinvoke: true,
      });
    }
  });
}

export default Plugin.define({
  id: PLUGIN_ID,
  async setup(ctx) {
    installAgents(configRoot());
    await registerCommands(ctx);
    await registerSkills(ctx);
  },
});
