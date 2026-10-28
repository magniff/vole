// The extension's manifest (npm run test:package): vole is the default
// formatter of .vl files, they are formatted on save, indented by four
// spaces; the language, the grammar and the client's entry point exist;
// (0.25.2) the C settings are given to the server.
// Plain node, no dependencies.

"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const id = `${pkg.publisher}.${pkg.name}`;

const defaults = pkg.contributes.configurationDefaults["[vole]"];
assert.ok(defaults, "configurationDefaults has [vole]");
assert.strictEqual(defaults["editor.defaultFormatter"], id, "vole formats .vl files");
assert.strictEqual(defaults["editor.formatOnSave"], true, "on save");
assert.strictEqual(defaults["editor.tabSize"], 4);
assert.strictEqual(defaults["editor.insertSpaces"], true);

const lang = pkg.contributes.languages.find((l) => l.id === "vole");
assert.ok(lang && lang.extensions.includes(".vl"), "the vole language, .vl files");
assert.ok(pkg.activationEvents.includes("onLanguage:vole"));
for (const g of pkg.contributes.grammars) {
  assert.ok(fs.existsSync(path.join(root, g.path)), `grammar ${g.path}`);
}
assert.ok(fs.existsSync(path.join(root, "src", "extension.ts")), "the client");
// (0.25.2) the project's C settings, arrays of paths
const props = pkg.contributes.configuration.properties;
for (const key of ["vole.includePaths", "vole.cSources"]) {
  assert.ok(props[key], key);
  assert.strictEqual(props[key].type, "array", `${key} is an array`);
  assert.deepStrictEqual(props[key].default, [], `${key} is empty by default`);
}
const client = fs.readFileSync(path.join(root, "src", "extension.ts"), "utf8");
assert.match(client, /initializationOptions: projectSettings\(config\)/, "the settings at the start");
assert.match(client, /configurationSection: "vole"/, "and when they change");
assert.match(pkg.version, /^\d+\.\d+\.\d+$/);

console.log(`ok: package.json (${id} ${pkg.version})`);
