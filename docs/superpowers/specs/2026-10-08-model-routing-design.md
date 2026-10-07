# Model yönlendirme: işe göre Opus / Sonnet / Haiku — tasarım

Tarih: 2026-10-08 · Durum: onay bekliyor

## Amaç

Token kullanımını düşürmek: her işi Opus 5.5 yapmasın. Mekanik işler (gate koşmak, log okumak,
test ve Maestro flow yazmak, commit, arama) daha ucuz modele gitsin; kod yazmak Opus'ta kalsın.

Kapsam iki taraf:

- **Repodaki skiller** — özellikle `compass-kit` ile üretilen her projeye giden `cmp-*` skilleri
  (cmpose.dev kullanıcılarını da etkiler).
- **Kerem'in kendi kullanımı** — global `~/.claude/CLAUDE.md`, superpowers subagent'ları,
  `account-delegate`.

Başarı ölçütleri:

1. Gate koşuları sırasında ana oturumun context'ine Gradle/detekt logu girmez; yalnız kısa rapor gelir.
2. Uygulama kodunu yazan her adım (feature, design-to-code, mantık gerektiren build düzeltmesi) Opus'ta
   (oturum modelinde) kalır.
3. Mevcut testler (`account-delegate/tests`, `compass-kit/hooks/test_secrets_guard.sh`) ve yeni
   `scripts/check-skills.sh` yeşil.

## Alınan kararlar

| Konu | Karar |
|---|---|
| Kapsam | Hem repo skilleri hem Kerem'in kendi akışları |
| Kod yazma | Opus (oturum modeli); `cmp-feature`, `cmp-design-to-code`, `cmp-code-rules` dokunulmaz |
| Mekanizma | Mekanik skiller `context: fork` + `model:` ile ayrı subagent'ta; inline `model:` yalnız kendi turu olan skillerde |
| Gate düzeltmesi | `cmp-gates` (Sonnet) yalnız `cmp-verify/references/failures.md`'de tarifi olan mekanik hataları düzeltir; gerisini raporlar |
| Haiku | Yalnız arama/keşif; build düzeltme bile Kotlin akıl yürütmesi istediği için Sonnet |
| Kerem'in subagent'ları | Global CLAUDE.md kuralı + Agent tool `model` parametresi; `CLAUDE_CODE_SUBAGENT_MODEL` kullanılmaz |

Elenenler:

- **Her skill'e inline `model:` (yaklaşım B):** SKILL.md'deki `model:` çağrıldığı turun geri kalanını o
  modele geçirir. Opus feature yazarken `cmp-verify` (sonnet) çağrılırsa turun kalanı — kod dahil —
  Sonnet'e kayar.
- **`CLAUDE_CODE_SUBAGENT_MODEL=sonnet` (yaklaşım C):** `opus` vermeyi unutan her kod-yazan subagent
  sessizce Sonnet'e düşer; compass-kit kullanıcılarına da ulaşmaz.
- **`opusplan` aliası:** yürütmeyi Sonnet'e geçirir, "kod Opus'ta" kararıyla çelişir.
- **`cmp-verify`'ı bütünüyle fork'a almak:** `cmp-feature`, `cmp-design-to-code` ve `cmp-code-rules`
  ondaki "ne zaman build" (bölüm 2) ve hata tariflerine başvuruyor; fork olunca her okuma bir subagent
  açar.

## Dayanılan Claude Code davranışı (2026-10-08 itibarıyla dokümanlardan)

- SKILL.md `model:` — alias (`opus`, `sonnet`, `haiku`, `fable`), tam ID ya da `inherit`. Inline
  skill'de turun kalanı için geçerli, sonraki prompt'ta oturum modeline döner. Org `availableModels`
  izin vermezse yok sayılır (oturum modeli kullanılır).
- `context: fork` — skill bir subagent'ta çalışır, skill metni görev prompt'u olur, konuşma geçmişini
  görmez. Varsayılan arka planda çalışır; `background: false` ile beklenir. `model:` subagent'ın
  modelini belirler.
- Fork'lanmış subagent başka subagent açamaz → fork'taki bir skill diğer skilleri `Skill` ile fork
  olarak çağıramaz; ihtiyaç duyduğu SKILL.md / reference dosyalarını `Read` ile okur.
- Agent tool model önceliği: çağrıdaki `model` > agent tanımındaki `model:` >
  `CLAUDE_CODE_SUBAGENT_MODEL` > ana oturum modeli.
- `claude -p --model <alias|id>` headless oturumun modelini belirler.

## Bileşenler

### 1. Kit skilleri

| Skill | Değişiklik | Model |
|---|---|---|
| `cmp-code-rules` | yok | oturum |
| `cmp-feature` | yok (yalnız `cmp-verify` atıflarının gate kısmı `cmp-gates`'e döner, bkz. §3) | oturum |
| `cmp-design-to-code` | aynı | oturum |
| `cmp-verify` | inline, başvuru skill'i olarak kalır: ne zaman build, çıktıyı okuma, hata tarifleri. "Gate'leri koş" adımı `cmp-gates`'i çağırmaya döner | oturum |
| `cmp-gates` (yeni) | `context: fork`, `background: false` | `sonnet`, `effort: medium` |
| `cmp-detekt` | `context: fork`, `background: false` | `sonnet` |
| `cmp-testing` | `context: fork`, `background: false`, `argument-hint` | `sonnet` |
| `cmp-maestro` | `context: fork`, `background: false`, `argument-hint` | `sonnet` |
| `cmp-commit` | inline `model: sonnet` (yalnız `/cmp-commit` ile çağrılır, tur bütünüyle commit) | `sonnet` |

#### `cmp-gates` (yeni skill)

- **Ne yapar:** `CLAUDE.md` → *Definition of done* altındaki gate'leri sırayla, yazıldığı gibi koşar.
  Argüman verilirse yalnız o gate'ler (ör. `android`, `ios`, `detekt`, `tests`) — `cmp-verify` bölüm 2
  ara build'leri için.
- **Okuma kuralları:** `cmp-verify/SKILL.md` bölüm 3'ü uygular (başarı = çalışan task satırları; test
  gate'i `TEST-*.xml` `tests="N"` sayısıyla; sıfır test = kırmızı; host-only testler sayılmaz).
- **Düzeltme:** Kırmızı gate'te hatayı `cmp-verify/references/failures.md` tablosuyla eşler. Eşleşen
  (eksik import, `Res` paketi, `Dispatchers.IO` importu, KSP/Koin annotation, detekt auto-correct ve
  `cmp-detekt`'teki tarifli bulgular) → düzeltir, gate'i yeniden koşar. Bir gate için en fazla 3 tur.
  Eşleşmeyen ya da davranış/mantık değiştirmesi gereken → dokunmaz, raporlar. Test başarısızlığında
  testi ya da kodu değiştirmez; raporlar.
- **Yasaklar:** suppress, baseline, detekt config değişikliği, test silme/atlama (mevcut `cmp-detekt` /
  `cmp-testing` kuralları).
- **Rapor (ana oturuma dönen tek çıktı):**

  ```
  Gates: Android ✅ · iOS ✅ · detekt ❌ · Tests ✅ (42 test)
  Düzeltilen (mekanik): feature/x/data/.../Repo.kt:12 — eksik import kotlinx.coroutines.IO
  Açık kalan:
  - detekt LongMethod — feature/x/presentation/XContent.kt:88 — fonksiyonu bölmek gerekiyor (mantık)
  ```

  Ham log yok; açık kalan her madde dosya:satır + tek satır özet + neden düzeltilmediği.

#### `cmp-detekt`, `cmp-testing`, `cmp-maestro` (fork'a geçenler)

- Frontmatter'a `context: fork`, `background: false`, `model: sonnet` eklenir.
- Fork konuşma geçmişini görmediği için skill metninin başına bir "Girdi" bölümü: çağıran ne verir
  (`cmp-testing`: test edilecek sınıf/modül veya kırmızı test gate'inin çıktısı; `cmp-maestro`:
  flow adı, ekranlar), skill neyi kendisi okur (`CLAUDE.md`, ilgili kaynak dosyalar, gerekiyorsa
  `cmp-code-rules/SKILL.md`).
- Sonunda kısa rapor: değişen dosyalar, koşulan gate ve sonucu, açık kalanlar.
- İçerdikleri diğer-skill atıfları (`cmp-testing` → `cmp-verify`, vb.) "dosyayı oku" şeklinde kalır.

#### `cmp-commit`

- Frontmatter'a `model: sonnet` eklenir. Gate adımı `cmp-gates`'i çağırır.

### 2. Kit yönlendirmesi

- `compass-kit/kit.json` `skills` listesine `cmp-gates` eklenir.
- `compass-kit/CLAUDE.md` "Which skill when":
  - `Before saying you are done, or to run any gate: cmp-gates`
  - `Build failure you are fixing yourself: cmp-verify (failure recipes)`
- Kit'i üreten backend `kit.json`'u okuyor; yeni skill'in projeye kopyalandığı `cmp-matrix-test` ile
  bir varyantta doğrulanır.

### 3. Atıfların güncellenmesi

`cmp-code-rules` (§ son kontrol), `cmp-feature` (§ bitiş), `cmp-design-to-code` (§ gate adımı),
`cmp-verify` (§1) içindeki "gate'leri koş" anlamındaki `cmp-verify` atıfları `cmp-gates` olur;
"ne zaman build" ve hata tarifleri atıfları `cmp-verify`'da kalır. README tablosuna `cmp-gates`
satırı ve her skill'in modelini gösteren kısa bir not eklenir.

### 4. `account-delegate`

- `scripts/delegate.sh`: yeni `--model <alias|id>` bayrağı; `DELEGATE_MODEL` env'i bayrak yoksa
  kullanılır. Doğrulama: `[A-Za-z0-9._\[\]-]+`, `-` ile başlayamaz; aksi halde `die`. Verilmişse
  `claude -p`'ye `--model` olarak iletilir; verilmemişse hiç iletilmez (hesabın varsayılanı).
  Plan modunda (`--plan`) model `plan.json`'a yazılır, sonraki görevler aynı modeli kullanır.
- `SKILL.md` varsayılanları: `--mode ro` (analiz, araştırma, inceleme) → `sonnet`; `--mode write` ve
  plan yürütme → `opus`. Teklif cümlesi modeli söyler ("şirket hesabında Sonnet ile çalıştırayım mı?").
  Kullanıcı başka model derse o kullanılır.
- Testler: `tests/fake-claude.sh` aldığı argümanları bir dosyaya yazar. Yeni testler: `--model sonnet`
  iletilir; bayraksız çağrıda `--model` geçmez; `DELEGATE_MODEL` kullanılır; geçersiz değer
  (`-x`, `a b`, `x;y`) reddedilir; plan modunda ikinci görev aynı modeli alır.

### 5. Global `~/.claude/CLAUDE.md` (repo dışı)

Kerem'in genel tercihlerine tarihli bir madde:

> **Model yönlendirme:** Ana oturum Opus. Subagent açarken Agent tool'a `model` ver:
> implementer (kod yazan) → verme/`inherit` (Opus); görev başına spec-uyum reviewer'ı → `sonnet`;
> kod kalitesi reviewer'ı ve son genel review → `opus`; dosya arama/keşif (Explore) → `haiku`;
> doküman/web araştırması, log/transcript özeti → `sonnet`. (8 Ekim 2026)

## Test ve doğrulama

1. `account-delegate/tests/*.sh` — mevcutlar + §4'teki yeni testler yeşil.
2. Yeni `scripts/check-skills.sh` (repoda henüz yapı kontrolü yok): her `*/SKILL.md` frontmatter'ı
   ayrıştırılır; `name` klasör adıyla aynı; `model` varsa `opus|sonnet|haiku|fable|inherit`;
   `context: fork` olan her skill'de `background: false`; `kit.json`'daki her skill'in klasörü var.
3. Elle doğrulama (tek üretilmiş projede): Opus oturumunda küçük bir değişiklikten sonra `cmp-gates`
   çağrılır → subagent Sonnet'te çalışır (transcript'te model), ana oturuma yalnız rapor gelir; bilerek
   eklenen eksik import Sonnet tarafından düzeltilir; bilerek eklenen mantık hatası raporlanır,
   düzeltilmez.
4. `cmp-matrix-test` bir varyantta: üretilen projede `.claude/skills/cmp-gates` var.

## Kapsam dışı

- Token kullanımını ölçen bir panel/raporlama (account-delegate'in `usage.sh`'i yeterli).
- `cmp-new-project` ve `cmp-matrix-test` (zaten `sonnet`).
- Fable modeli için atama.
