#!/usr/bin/env bash
# Regenerate the skill's contract from the cmpose.dev backend source, so the
# documented validation rules can never silently drift.
#
# Usage:
#   sync-contract.sh            # (re)generate reference/contract.json + reference/payload.md
#   sync-contract.sh --check    # verify the committed contract is current
#
# Backend dir: env CMP_BACKEND_DIR (a checkout that has services/contract.js, the
# backend's single contract module; contractVersion is computed only there).
# Requires Node (the backend is Node, so it's already installed there).
#
# Exit codes: 0 = ok / written; 1 = --check found drift; 2 = configuration error
# (node missing, CMP_BACKEND_DIR unset or wrong).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # skill root (parent of scripts/)
MODE="generate"
[ "${1:-}" = "--check" ] && MODE="check"

# Point this at your cmpose.dev backend checkout (the generator's source of truth).
BACKEND_DIR="${CMP_BACKEND_DIR:-}"

command -v node >/dev/null 2>&1 || { echo "ERROR: node is required for sync-contract.sh"; exit 2; }
[ -n "$BACKEND_DIR" ] || { echo "ERROR: set CMP_BACKEND_DIR to your cmpose.dev backend checkout"; exit 2; }
[ -d "$BACKEND_DIR" ] || { echo "ERROR: backend dir not found: $BACKEND_DIR"; exit 2; }
[ -f "$BACKEND_DIR/services/contract.js" ] || { echo "ERROR: $BACKEND_DIR/services/contract.js missing"; exit 2; }

DOTENV_CONFIG_QUIET=true SKILL_DIR="$HERE" BACKEND_DIR="$BACKEND_DIR" MODE="$MODE" node <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');

const SKILL_DIR = process.env.SKILL_DIR;
const BACKEND_DIR = process.env.BACKEND_DIR;
const MODE = process.env.MODE;

const contractPath = path.join(SKILL_DIR, 'reference', 'contract.json');
const payloadPath  = path.join(SKILL_DIR, 'reference', 'payload.md');

const warnings = [];

// The backend's single contract module: facts + version live there, not here.
let contractFacts, contractVersion;
try {
  ({ contractFacts, contractVersion } = require(path.join(BACKEND_DIR, 'services', 'contract.js')));
  if (typeof contractFacts !== 'function' || typeof contractVersion !== 'function') throw new Error('contractFacts/contractVersion not exported');
} catch (e) {
  console.error('ERROR: cannot load services/contract.js from CMP_BACKEND_DIR: ' + e.message);
  process.exit(2);
}

// --- Hand-maintained maps (NOT derivable from the backend over HTTP) ---------
// TR + EN intent keywords → featuresConfig flag. Lowercase substring match.
const keywordMap = {
  network:          ['network', 'ktor', 'networking', 'api client', 'http', 'ağ', 'istek'],
  networkInspector: ['network inspector', 'inspector', 'chucker', 'http inspector', 'network monitor', 'ağ izleyici'],
  theming:          ['theming', 'theme', 'dark mode', 'light mode', 'material', 'tema', 'karanlık mod', 'koyu tema'],
  multiLang:        ['multi-language', 'multilanguage', 'multi language', 'i18n', 'l10n', 'localization', 'localisation', 'çoklu dil', 'yerelleştirme', 'dil desteği'],
  dataStore:        ['datastore', 'data store', 'preferences', 'persistence', 'local storage', 'yerel depolama', 'saklama'],
  // room: a local database / offline storage of structured data (DataStore is for preferences).
  room:             ['room database', 'sqlite', 'local database', 'offline storage', 'offline database', 'veritabanı', 'yerel veritabanı', 'çevrimdışı depolama'],
  detekt:           ['detekt', 'static analysis', 'lint', 'kod analizi', 'statik analiz'],
  // purchases/ads: explicit monetization intent ONLY. Naming a featuresConfig key switches the
  // template to blank, so ordinary app descriptions must not match: no 'premium', 'subscription',
  // 'purchases', 'satın alma', 'abonelik', 'monetization' (a "subscription tracker" or "an app that
  // tracks purchases" is not a paywall request). No bare 'ads' / 'advert' / 'reklam' either:
  // substrings of 'downloads', 'threads', 'advertise', 'reklamasyon'.
  purchases:        ['revenuecat', 'in-app purchase', 'in app purchase', 'paywall', 'uygulama içi satın alma', 'abonelik ekranı'],
  ads:              ['admob', 'banner ad', 'interstitial', 'rewarded ad', 'reklam göster', 'reklam ekle']
};
// Words that mean "give me the full example app".
const templateKeywords = {
  showcase: ['showcase', 'example app', 'full example', 'sample app', 'demo app', 'örnek uygulama', 'örnek proje', 'her şey', 'hepsi', 'dolu']
};
// --- Assemble the contract (everything except the volatile _generated block) -
function buildContract() {
  const f = contractFacts();
  return {
    contractVersion: contractVersion(),
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
      minSdkMin: f.limits.minSdkMin,
      minSdkMax: f.limits.minSdkMax,
      iosVersionMin: f.limits.iosVersionMin,
      iosVersionMax: f.limits.iosVersionMax,
      maxModules: f.limits.maxModules,
      sdkNote: 'targetSdk and compileSdk come from the template: GET {apiBase}/api/versions',
      rateLimitMax: f.limits.rateLimitMax,
      rateLimitWindowMinutes: f.limits.rateLimitWindowMinutes,
      maxBodyLimit: f.limits.maxBodyLimit
    },
    maxLengths: f.maxLengths,
    regex: f.regex,
    kotlinHardKeywords: f.kotlinHardKeywords,
    reservedModuleNames: f.reservedModuleNames,
    reservedPackagePrefix: f.reservedPackagePrefix,
    messages: f.messages,
    templateTypes: f.templateTypes,
    featuresConfigKeys: f.featuresConfigKeys,
    dependencyRules: f.dependencyRules,
    keywordMap,
    templateKeywords,
    anatomy: f.anatomy
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
- \`GET {apiBase}${c.endpoints.config}\` → \`{ minSdkMin, minSdkMax, iosVersionMin, iosVersionMax, maxModules, reservedPackagePrefix, rateLimitMax, rateLimitWindowMinutes, contractVersion }\` (LIVE limits).
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
    "detektYamlContent": null,       // optional custom detekt.yml as a string
    "purchases": true,               // RevenueCat paywall; ships a Test Store key — replace it before you ship
    "ads": true,                     // AdMob banner/interstitial/rewarded (Google test IDs) + UMP/ATT consent
    "room": false                    // Room KMP database (core/room) + a Notes demo; only for a local database / offline storage, not preferences
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
- \`purchases\` and \`ads\` are independent. With both on, an active premium entitlement hides the ads.

## Monetization (\`purchases\`, \`ads\`)
- \`purchases\` → \`core/purchases\` (RevenueCat KMP) + a paywall screen in \`feature/monetization\`.
  The project ships with a RevenueCat **Test Store** API key: replace it with your own platform keys
  before you ship to a store. A **release** build that still has the Test Store key keeps purchases
  disabled (the paywall shows a message instead of offerings).
- \`ads\` → \`core/ads\` (AdMob banner, interstitial and rewarded, with Google's test ad unit IDs) +
  an ads demo screen in \`feature/monetization\`. UMP consent (and ATT on iOS) is requested on the
  first visit to the ads screen, not at app launch; a real app should ask at launch. The EEA consent
  debug geography is applied in debug builds only.
- Either flag adds \`feature/monetization\`; \`monetization\` is therefore a reserved module name.

## Room (\`room\`)
- \`room\` → \`core/room\` (Room KMP with bundled SQLite: \`AppDatabase\`, DAOs, exported \`schemas/\`) and, in
  blank, a Notes demo screen in \`feature/notes\`. Showcase always has \`core/room\` (it stores the
  favorites) and never \`feature/notes\`. \`notes\` is therefore a reserved module name.
- Turn it on only when the user asks for a local database or offline storage of structured data.
  Preferences and settings belong in DataStore (\`dataStore\`). \`room\` is independent: it implies nothing.
- Notes is a demo: replace it or remove it. New tables go into the existing \`AppDatabase\`.

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
${Object.entries(c.anatomy.featureModules || {}).map(([m, r]) => `- \`${m}\`: ${r.requires ? 'if ' + r.requires.join(' && ') : 'if ' + r.requiresAny.join(' || ')} (${r.note})`).join('\n')}
- \`${c.anatomy.detektDir.path}\`: if ${c.anatomy.detektDir.requires.join(' && ')}
- showcase adds: ${c.anatomy.showcaseFeatures.join(', ')}
- each custom module → \`${c.anatomy.customFeaturePath}\` with layers: ${c.anatomy.customFeatureLayers.join(', ')}
`;
}

// --- Run ---------------------------------------------------------------------
let fresh;
try { fresh = buildContract(); } catch (e) {
  console.error('ERROR: contractFacts()/contractVersion() failed: ' + e.message);
  process.exit(2);
}
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
