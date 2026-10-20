#!/usr/bin/env node
import { main } from "./cli.mjs";

if (process.env.npm_config_global === "true") {
  await main(["install"]);
} else {
  console.log("Desktop installation: npx @liuzhao1225/codex-account-switcher install");
}
