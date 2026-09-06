#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const lib = path.join(root, "lib");

const copies = [
  ["node_modules/vue/dist/vue.global.prod.js", "vue.global.js"],
  ["node_modules/qrcodejs/qrcode.min.js", "qrcode.min.js"],
  ["node_modules/pako/dist/pako.min.js", "pako.min.js"],
  ["node_modules/@undecaf/zbar-wasm/dist/index.js", "zbar-wasm.js"],
  ["node_modules/@undecaf/zbar-wasm/dist/zbar.wasm", "zbar.wasm"],
];

fs.mkdirSync(lib, { recursive: true });

for (const [from, to] of copies) {
  const src = path.join(root, from);
  const dest = path.join(lib, to);
  if (!fs.existsSync(src)) {
    console.error(`Missing dependency file: ${from}`);
    console.error("Run: npm install");
    process.exit(1);
  }
  fs.copyFileSync(src, dest);
  console.log(`Copied ${to}`);
}
