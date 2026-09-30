#!/usr/bin/env bash
# Regenerate the skill's contract from the cmpose.dev backend source, so the
# documented validation rules can never silently drift.
#
# Usage:
#   sync-contract.sh            # (re)generate reference/contract.json + reference/payload.md
#   sync-contract.sh --check    # exit non-zero if the committed contract is stale (drift)
#
# Backend dir: env CMP_BACKEND_DIR > default below.
# Requires Node (the backend is Node, so it's already installed there).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # skill root (parent of scripts/)
MODE="generate"
[ "${1:-}" = "--check" ] && MODE="check"

# Point this at your cmpose.dev backend checkout (the generator's source of truth).
BACKEND_DIR="${CMP_BACKEND_DIR:-}"

command -v node >/dev/null 2>&1 || { echo "ERROR: node is required for sync-contract.sh"; exit 1; }
[ -n "$BACKEND_DIR" ] || { echo "ERROR: set CMP_BACKEND_DIR to your cmpose.dev backend checkout"; exit 1; }
[ -d "$BACKEND_DIR" ] || { echo "ERROR: backend dir not found: $BACKEND_DIR"; exit 1; }
[ -f "$BACKEND_DIR/shared/ProjectValidator.js" ] || { echo "ERROR: $BACKEND_DIR/shared/ProjectValidator.js missing"; exit 1; }

SKILL_DIR="$HERE" BACKEND_DIR="$BACKEND_DIR" MODE="$MODE" node <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');

const SKILL_DIR = process.env.SKILL_DIR;
const BACKEND_DIR = process.env.BACKEND_DIR;
const MODE = process.env.MODE;

const pvPath  = path.join(BACKEND_DIR, 'shared', 'ProjectValidator.js');
const cfgPath = path.join(BACKEND_DIR, 'config', 'config.js');
const contractPath = path.join(SKILL_DIR, 'reference', 'contract.json');
const payloadPath  = path.join(SKILL_DIR, 'reference', 'payload.md');

const warnings = [];

// --- Pull live-but-static values straight out of the backend modules ----------
const PV = require(pvPath);
const CFG = require(cfgPath);

// Configure ProjectValidator exactly like the server does at startup
// (controllers/projectController.js), so messages and limits reflect config.js.
PV.configure({
  minSdkMin: CFG.minSdkMin, minSdkMax: CFG.minSdkMax,
  iosVersionMin: CFG.iosVersionMin, iosVersionMax: CFG.iosVersionMax,
  maxModules: CFG.maxModules,
  reservedPackagePrefix: CFG.oldPackageName
});

// --- Extract the regex literals from the validator source --------------------
const pvSrc = fs.readFileSync(pvPath, 'utf8');
function grab(re, name, fallback) {
  const m = pvSrc.match(re);
  if (m && m[1]) return m[1];
  warnings.push(`could not extract ${name} regex from ProjectValidator.js — using fallback`);
  return fallback;
}
const regex = {
  projectName:      grab(/validateProjectName[\s\S]*?return\s+\/([^\/\n]+)\/\.test/, 'projectName', '^[a-zA-Z]+$'),
  packageName:      grab(/validatePackageName[\s\S]*?const\s+regex\s*=\s*\/([^\/\n]+)\//, 'packageName', '^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*){2,}$'),
  moduleName:       grab(/validateModuleName[\s\S]*?return\s+\/([^\/\n]+)\/\.test/, 'moduleName', '^[a-z][a-z0-9]*$'),
  iosVersionFormat: grab(/validateIosVersion[\s\S]*?if\s*\(!\/([^\/\n]+)\/\.test/, 'iosVersionFormat', '^\\d+(\\.\\d+){1,2}$')
};

// Kotlin hard keywords: rejected as package segments and as module names.
// The list is private to the validator module, so it is read from the source.
function grabKeywords() {
  const m = pvSrc.match(/KOTLIN_HARD_KEYWORDS\s*=\s*\[([^\]]*)\]/);
  const words = m ? (m[1].match(/'[^']*'|"[^"]*"/g) || []).map(w => w.slice(1, -1)) : [];
  if (words.length) return words;
  warnings.push('could not extract KOTLIN_HARD_KEYWORDS from ProjectValidator.js — using fallback');
  return ['as', 'break', 'class', 'continue', 'do', 'else', 'false', 'for', 'fun', 'if', 'in', 'interface', 'is', 'null', 'object', 'package', 'return', 'super', 'this', 'throw', 'true', 'try', 'typealias', 'typeof', 'val', 'var', 'when', 'while'];
}
const kotlinHardKeywords = grabKeywords();

// Reserved module names: valid by the regex, rejected by the server (file processing skips build/).
function grabReservedModuleNames() {
  const m = pvSrc.match(/RESERVED_MODULE_NAMES\s*=\s*\[([^\]]*)\]/);
  const words = m ? (m[1].match(/'[^']*'|"[^"]*"/g) || []).map(w => w.slice(1, -1)) : [];
  if (words.length) return words;
  warnings.push('could not extract RESERVED_MODULE_NAMES from ProjectValidator.js — using fallback');
  return ['build'];
}
const reservedModuleNames = grabReservedModuleNames();

// --- Body size limit: express.json({ limit }) lives in app.js (older backends: server.js)
let maxBodyLimit = null;
for (const file of ['app.js', 'server.js']) {
  let src;
  try { src = fs.readFileSync(path.join(BACKEND_DIR, file), 'utf8'); } catch (_) { continue; }
  const m = src.match(/express\.json\(\s*\{[^}]*\blimit:\s*['"]([^'"]+)['"]/);
  if (m) { maxBodyLimit = m[1]; break; }
}
if (!maxBodyLimit) {
  maxBodyLimit = '500kb';
  warnings.push('could not find express.json({ limit }) in app.js or server.js — defaulting maxBodyLimit to 500kb');
}

// --- Hand-maintained maps (NOT derivable from the backend over HTTP) ---------
// TR + EN intent keywords → featuresConfig flag. Lowercase substring match.
const keywordMap = {
  network:          ['network', 'ktor', 'networking', 'api client', 'http', 'ağ', 'istek'],
  networkInspector: ['network inspector', 'inspector', 'chucker', 'http inspector', 'network monitor', 'ağ izleyici'],
  theming:          ['theming', 'theme', 'dark mode', 'light mode', 'material', 'tema', 'karanlık mod', 'koyu tema'],
  multiLang:        ['multi-language', 'multilanguage', 'multi language', 'i18n', 'l10n', 'localization', 'localisation', 'çoklu dil', 'yerelleştirme', 'dil desteği'],
  dataStore:        ['datastore', 'data store', 'database', 'db', 'persistence', 'local storage', 'veritabanı', 'yerel depolama', 'saklama'],
  detekt:           ['detekt', 'static analysis', 'lint', 'kod analizi', 'statik analiz']
};
// Words that mean "give me the full example app".
const templateKeywords = {
  showcase: ['showcase', 'example app', 'full example', 'sample app', 'demo app', 'örnek uygulama', 'örnek proje', 'her şey', 'hepsi', 'dolu']
};
// featuresConfig flag → core modules it adds (for the anatomy preview tree).
// `requires` = all must be true; `requiresAny` = at least one true.
const anatomy = {
  always: ['androidApp', 'iosApp', 'shared', 'core/domain', 'core/presentation', 'core/navigation', 'build-logic'],
  alwaysNote: 'shared wires Koin (DI) + Navigation, which are always included.',
  coreModules: {
    'core/network':      { requires: ['network'], note: 'Ktor HTTP client' },
    'core/designsystem': { requiresAny: ['theming', 'multiLang'], note: 'theme (palette + KtTheme) and/or LocalStringResources' },
    'core/multilang':    { requires: ['multiLang'], note: 'i18n / localization' },
    'core/database':     { requires: ['dataStore'], note: 'DataStore persistence; with theming also the saved Light/Dark/System choice (DarkModeManager)' }
  },
  detektDir: { requires: ['detekt'], path: 'detekt/' },
  showcaseFeatures: ['feature/home', 'feature/onboarding'],
  customFeaturePath: 'feature/<name>',
  customFeatureLayers: ['contract', 'data', 'domain', 'presentation']
};
const dependencyRules = {
  alwaysOn: ['koin', 'navigation'],
  implies: { networkInspector: ['network'] },        // inspector ⇒ network
  auto:    { dataStore: ['theming', 'multiLang'] }    // theming || multiLang ⇒ dataStore
};

// --- Assemble the contract (everything except the volatile _generated block) -
function buildContract() {
  return {
    apiBaseDefault: 'https://cmpose.dev',
    endpoints: {
      generate: '/api/generate',
      config: '/api/config',
      rateLimitStatus: '/api/rate-limit-status',
      versions: '/api/versions'
    },
    endpointResolution: 'env CMP_API > defaults.json.apiBase > apiBaseDefault',
    // STATIC fallback values. At runtime the skill prefers live GET /api/config.
    limits: {
      minSdkMin: CFG.minSdkMin,
      minSdkMax: CFG.minSdkMax,
      iosVersionMin: CFG.iosVersionMin,
      iosVersionMax: CFG.iosVersionMax,
      maxModules: CFG.maxModules,
      sdkNote: 'targetSdk and compileSdk come from the template: GET {apiBase}/api/versions',
      rateLimitMax: CFG.rateLimitMaxRequests,
      rateLimitWindowMinutes: Math.round(CFG.rateLimitWindowMs / 60000),
      maxBodyLimit
    },
    maxLengths: {
      projectName: PV.MAX_LENGTH_PROJECT_NAME,
      appName: PV.MAX_LENGTH_APP_NAME,
      packageName: PV.MAX_LENGTH_PACKAGE_NAME,
      moduleName: PV.MAX_LENGTH_MODULE_NAME,
      minSdk: PV.MAX_LENGTH_MIN_SDK,
      iosVersion: PV.MAX_LENGTH_IOS_VERSION,
      networkBaseUrl: PV.MAX_LENGTH_BASE_URL
    },
    regex,
    // Package/module rules beyond the regex (server: ProjectValidator.validatePackageName/ModuleName)
    kotlinHardKeywords,
    reservedModuleNames,
    reservedPackagePrefix: CFG.oldPackageName,
    messages: PV.messages,
    templateTypes: ['blank', 'showcase'],
    featuresConfigKeys: ['network', 'networkInspector', 'networkBaseUrl', 'theming', 'multiLang', 'dataStore', 'detekt', 'detektYamlContent'],
    dependencyRules,
    keywordMap,
    templateKeywords,
    anatomy
  };
}

// --- Render the human-readable mirror ---------------------------------------
function renderPayloadMd(c, gen) {
  const L = c.limits, X = c.maxLengths, R = c.regex;
  return `<!-- GENERATED by scripts/sync-contract.sh on ${gen.date}. Mirrors the public cmpose.dev API contract.
     Do not hand-edit — run \`scripts/sync-contract.sh\` to refresh. -->

# \`/api/generate\` contract

Mirrors the public cmpose.dev API contract (\`POST /api/generate\`). **At runtime, always
prefer live \`GET /api/config\` + \`GET /api/versions\` over the static numbers below.**

## Endpoints
- \`POST {apiBase}${c.endpoints.generate}\`, header \`Content-Type: application/json\`.
  - Success → a **zip** (binary); the top-level folder inside is \`<projectName>\`.
  - \`400\` → JSON \`{ "error": "<validation message>" }\`.
  - \`429\` → JSON \`{ "error": "Too many requests", "message": "...", "retryAfterMinutes": N }\`.
  - \`413\` → request body over \`${L.maxBodyLimit}\` (usually a huge \`detektYamlContent\`).
  - \`503\` + \`Retry-After\` → the server is at its concurrent-generation limit; no quota was spent.
  - \`415\` → unsupported body charset or \`Content-Encoding\` (send plain UTF-8 JSON).
- \`GET {apiBase}${c.endpoints.config}\` → \`{ minSdkMin, minSdkMax, iosVersionMin, iosVersionMax, maxModules, reservedPackagePrefix, rateLimitMax, rateLimitWindowMinutes }\` (LIVE limits).
- \`GET {apiBase}${c.endpoints.versions}\` → \`{ kotlin, agp, composeMultiplatform, gradle, jdk }\` (LIVE library/tool versions — \`jdk\` is the build JDK).
- \`GET {apiBase}${c.endpoints.rateLimitStatus}\` → \`{ remaining, limit, resetSeconds, isLimited }\`.

Endpoint resolution: ${c.endpointResolution}.

## Body
\`\`\`jsonc
{
  "projectName": "MyApp",            // ${R.projectName}  · ≤${X.projectName} · no spaces
  "appName": "My App",               // letters/digits/space . _ ' - · trimmed · ≤${X.appName}
  "packageName": "dev.cmpose.myapp", // ${R.packageName} · ≤${X.packageName} · ≥3 segments · no Kotlin keyword segments · not ${c.reservedPackagePrefix} or under it
  "minSdk": "${L.minSdkMin}",                    // numeric string (1–${X.minSdk} digits) in [${L.minSdkMin}..${L.minSdkMax}]
  "iosVersion": "${L.iosVersionMin}",              // ${R.iosVersionFormat} in [${L.iosVersionMin}..${L.iosVersionMax}]
  "templateType": "blank",           // "blank" | "showcase"
  "featuresConfig": {                // used only for "blank"; ignored for "showcase"
    "network": true,
    "networkInspector": true,        // requires network=true
    "networkBaseUrl": "",            // optional; http(s) URL if non-empty · no whitespace, " \\ $ · ≤${X.networkBaseUrl}
    "theming": true,
    "multiLang": true,
    "dataStore": true,               // auto-true if theming || multiLang
    "detekt": true,
    "detektYamlContent": null        // optional custom detekt.yml as a string
  },
  "features": ["profile"]            // custom modules · each ${R.moduleName} · ≤${X.moduleName} · count ≤ maxModules (${L.maxModules})
}
\`\`\`

## Validation rules (mirror for fast feedback; server 400 is authoritative)
| Field | Rule | Max len |
|---|---|---|
| projectName | \`${R.projectName}\`, no spaces | ${X.projectName} |
| appName | non-empty, no leading/trailing space; only letters (any script, incl. combining marks), digits, space and \`. _ ' -\` | ${X.appName} |
| packageName | \`${R.packageName}\` (≥3 segments); no segment may be a Kotlin hard keyword (\`kotlinHardKeywords\`); must not equal or sit under the reserved template package \`${c.reservedPackagePrefix}\` (\`reservedPackagePrefix\`) | ${X.packageName} |
| module name | \`${R.moduleName}\`; not a Kotlin hard keyword; not a reserved name (${c.reservedModuleNames.map(n => '\`' + n + '\`').join(', ')}) | ${X.moduleName} |
| module count | ≤ \`maxModules\` (${L.maxModules}) | — |
| minSdk | numeric string of 1–${X.minSdk} digits, in [${L.minSdkMin}..${L.minSdkMax}] | ${X.minSdk} |
| iosVersion | \`${R.iosVersionFormat}\` within [${L.iosVersionMin}..${L.iosVersionMax}] | ${X.iosVersion} |
| networkBaseUrl | \`http://\` or \`https://\` only; no whitespace, \`"\`, \`\\\`, \`$\`; checked only for blank + \`network: true\` + non-empty | ${X.networkBaseUrl} |

Kotlin hard keywords (\`kotlinHardKeywords\`): ${c.kotlinHardKeywords.map(k => '\`' + k + '\`').join(', ')}.

## Always-on (not configurable, not in the payload)
- **Dependency Injection (Koin)** and **Navigation** are always included.

## Feature dependencies (enforce BEFORE sending)
- \`networkInspector: true\` ⇒ set \`network: true\`.
- \`theming: true\` or \`multiLang: true\` ⇒ set \`dataStore: true\`.

## blank vs showcase
- **blank**: \`featuresConfig\` reflects the user's choices; \`features\` = custom modules
  (each name once; a duplicate is a 400).
- **showcase**: send \`templateType:"showcase"\` and put any requested custom modules in
  \`features\` (\`features: []\` when none). The backend keeps the default \`home\` +
  \`onboarding\` modules and **ignores \`featuresConfig\`** (it strips any
  \`home\`/\`onboarding\` you put in \`features\`). Custom modules are added next to them,
  fully wired (their screens are registered; the showcase still opens on onboarding).

## Backend error messages (match these exactly when re-asking)
${Object.entries(c.messages).map(([k, v]) => `- \`${k}\`: ${v}`).join('\n')}

## Anatomy (which modules appear)
- Always: ${c.anatomy.always.join(', ')} — ${c.anatomy.alwaysNote}
${Object.entries(c.anatomy.coreModules).map(([m, r]) => `- \`${m}\`: ${r.requires ? 'if ' + r.requires.join(' && ') : 'if ' + r.requiresAny.join(' || ')} (${r.note})`).join('\n')}
- \`${c.anatomy.detektDir.path}\`: if ${c.anatomy.detektDir.requires.join(' && ')}
- showcase adds: ${c.anatomy.showcaseFeatures.join(', ')}
- each custom module → \`${c.anatomy.customFeaturePath}\` with layers: ${c.anatomy.customFeatureLayers.join(', ')}
`;
}

// --- Run ---------------------------------------------------------------------
const fresh = buildContract();
warnings.forEach(w => console.error('  WARN: ' + w));

if (MODE === 'check') {
  if (!fs.existsSync(contractPath)) { console.error('DRIFT: reference/contract.json is missing — run sync-contract.sh'); process.exit(1); }
  const existing = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
  delete existing._generated;
  if (JSON.stringify(fresh) !== JSON.stringify(existing)) {
    console.error('DRIFT: reference/contract.json is out of sync with the backend. Run scripts/sync-contract.sh to refresh.');
    // Best-effort field-level hint
    for (const k of Object.keys(fresh)) {
      if (JSON.stringify(fresh[k]) !== JSON.stringify(existing[k])) console.error(`  changed: ${k}`);
    }
    process.exit(1);
  }
  console.log('OK: contract.json is in sync with the backend' + (warnings.length ? ` (warnings: ${warnings.length})` : ''));
  process.exit(0);
}

// generate mode (no backend path / sha recorded — keep the public repo free of private-backend provenance)
const gen = {
  by: 'scripts/sync-contract.sh',
  date: new Date().toISOString().slice(0, 10)
};
const out = Object.assign({ _generated: gen }, fresh);
fs.mkdirSync(path.dirname(contractPath), { recursive: true });
fs.writeFileSync(contractPath, JSON.stringify(out, null, 2) + '\n');
fs.writeFileSync(payloadPath, renderPayloadMd(fresh, gen));
console.log(`Wrote ${path.relative(SKILL_DIR, contractPath)} and ${path.relative(SKILL_DIR, payloadPath)}.`);
NODE
