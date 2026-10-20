#!/usr/bin/env node
import { main } from "./cli.mjs";

// Retain the published 0.1.0 command's download-only default.
await main(process.argv.length > 2 ? process.argv.slice(2) : ["--links"]);
