/**
 * Record every read the console makes: which endpoint, and which field names it
 * expects back. Written for `admin_contract_dump.py` to consume, so the dump
 * exercises exactly the endpoints this console depends on — no more (wasted) and
 * no less (a blind spot is how `todayDeals` survived).
 *
 *   node scripts/extract-api-usage.mjs > ../backend/scripts/admin_api_usage.json
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

// Defaults to this console; pass another app's root to sweep it instead — the
// store panel talks to a different API prefix but has the identical shape.
const ROOT =
  process.argv[2] ||
  new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (entry === "node_modules" || entry === ".next" || entry === "scripts") continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (/\.tsx?$/.test(entry)) out.push(full);
  }
  return out;
}

/** Named interfaces -> their member names, including nested object literals.
 *  Nested members matter: `byZone: {zone: string}[]` is where a mismatch hides. */
function parseInterfaces(src) {
  const found = new Map();
  const re = /\b(?:interface|type)\s+(\w+)\s*=?\s*\{/g;
  let m;
  while ((m = re.exec(src))) {
    let depth = 1;
    let i = re.lastIndex;
    for (; i < src.length && depth > 0; i++) {
      if (src[i] === "{") depth++;
      else if (src[i] === "}") depth--;
    }
    const body = src.slice(re.lastIndex, i - 1);
    const fields = [];
    for (const fm of body.matchAll(/(?:^|[;,{\n])\s*(\w+)\s*\??\s*:/g)) fields.push(fm[1]);
    found.set(m[1], [...new Set(fields)]);
  }
  return found;
}

/** The member names a call's generic declares. Inline generics (`<{id: string}>`)
 *  resolve to nothing by name, so their members are read straight out of the
 *  literal instead. */
function fieldsFor(typeName, interfaces) {
  const bare = typeName.replace(/\[\]/g, "").trim();
  if (bare.startsWith("{")) {
    return [...new Set([...bare.matchAll(/(?:^|[;,{\n])\s*(\w+)\s*\??\s*:/g)].map((m) => m[1]))];
  }
  return interfaces.get(bare) ?? [];
}

const calls = [];
for (const file of walk(ROOT)) {
  const src = readFileSync(file, "utf8");
  if (!src.includes("api.")) continue;
  const interfaces = parseInterfaces(src);
  const re = /api\.(get|getPaged|getWithMeta)<([^>]+)>\(\s*[`"']([^`"']+)[`"']/g;
  let m;
  while ((m = re.exec(src))) {
    const [, method, type, path] = m;
    calls.push({
      path,
      method,
      type: type.trim(),
      fields: fieldsFor(type, interfaces),
      file: relative(ROOT, file).replace(/\\/g, "/"),
    });
  }
}

process.stdout.write(JSON.stringify({ calls }, null, 2));
