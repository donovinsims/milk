#!/usr/bin/env node
// Handshake each MCP server declared in .mcp.json over stdio and report what it
// advertises. This proves the server starts and lists tools; it does not prove
// a particular client will accept it.
//
//   node scripts/check-mcp.mjs
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const { mcpServers = {} } = JSON.parse(readFileSync(join(root, ".mcp.json"), "utf8"));

const TIMEOUT_MS = 120_000;

function probe(name, { command, args = [], env }) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env, ...env },
    });
    let buffer = "";
    let settled = false;
    let protocol = null;

    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      child.kill("SIGTERM");
      resolve({ name, ...result });
    };

    const timer = setTimeout(
      () => finish({ ok: false, error: `no tools/list within ${TIMEOUT_MS / 1000}s` }),
      TIMEOUT_MS,
    );

    const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);

    child.stdout.on("data", (chunk) => {
      buffer += chunk.toString();
      let newline;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line) continue;
        let message;
        try {
          message = JSON.parse(line);
        } catch {
          continue;
        }
        if (message.id === 1) {
          protocol = message.result?.protocolVersion ?? null;
          send({ jsonrpc: "2.0", method: "notifications/initialized", params: {} });
          send({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });
        } else if (message.id === 2) {
          const tools = message.result?.tools ?? [];
          const prompts = message.result?.prompts;
          finish({
            ok: tools.length > 0,
            protocol,
            tools: tools.length,
            sample: tools.slice(0, 3).map((tool) => tool.name),
            ...(prompts ? { prompts: prompts.length } : {}),
          });
        } else if (message.id === 1 && message.error) {
          finish({ ok: false, error: `initialize failed: ${message.error.message}` });
        }
      }
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString().trim();
      if (text) process.stderr.write(`[${name}] ${text}\n`);
    });

    child.on("error", (error) => finish({ ok: false, error: error.message }));
    child.on("exit", (code) => {
      if (!settled) finish({ ok: false, error: `exited with code ${code} before replying` });
    });

    send({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "milk-mcp-check", version: "0.0.0" },
      },
    });
  });
}

const names = Object.keys(mcpServers);
if (names.length === 0) {
  console.error("No servers in .mcp.json");
  process.exit(1);
}

const results = await Promise.all(names.map((name) => probe(name, mcpServers[name])));

for (const result of results) {
  if (result.ok) {
    console.log(
      `ok   ${result.name}: ${result.tools} tools, protocol ${result.protocol}` +
        (result.prompts ? `, ${result.prompts} prompts` : "") +
        (result.sample?.length ? ` (${result.sample.join(", ")}…)` : ""),
    );
  } else {
    console.log(`FAIL ${result.name}: ${result.error}`);
  }
}

process.exit(results.every((result) => result.ok) ? 0 : 1);
