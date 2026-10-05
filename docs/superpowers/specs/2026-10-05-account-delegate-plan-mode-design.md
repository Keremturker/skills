# account-delegate: plan modu — tasarım

Tarih: 2026-10-05 · Durum: onay bekliyor

## Amaç

Bir implementasyon planını iki hesaba bölerek yürütmek:

- **Kerem'in hesabı (ana oturum):** planı yazar (`superpowers:writing-plans`), her görevi kontrol eder
  (spesifikasyon + kalite + test), kusur bulursa düzeltme brief'i yazar, en sonda birleştirmeyi sorar.
- **Şirket hesabı (`DELEGATE_CLAUDE_CONFIG_DIR`):** her görevin kodunu yazar; düzeltme turlarını yapar.

Başarı ölçütü: bir plan, kullanıcıdan plan başına **tek onayla** görev görev şirket hesabında kodlanır,
ana oturum her görevi kontrol eder, sonuç tek dalda tek birleştirmeyle kullanıcıya sunulur; Kerem'in
kotası olabildiğince az harcanır.

## Alınan kararlar

| Konu | Karar |
|---|---|
| Akış | Plan → görev görev şirket hesabı → her görevden sonra kontrol → düzeltme turları → sonraki görev |
| Onay | Plan başına tek onay; aşağıdaki durma koşullarında durulur |
| Kontrolü kim yapar | Ana oturum kendisi (inceleme subagent'ı yok — kota en az bu yolda harcanır) |
| Diff okuma | Önce `git diff --stat`, sonra yalnızca ilgili hunk'lar (bağlam şişmesin) |
| Mekanik | Plan boyunca tek worktree + tek dal `delegate/<plan-id>`; görev başına yeni oturum, düzeltme turları `--resume` ile aynı oturumda |
| Tur sınırı | Görev başına en fazla 3 düzeltme turu |
| Bütçe | Tavan yok; maliyet görev başına raporlanır |

Elenenler: görev başına onay / her şeye onay; görev başına inceleme subagent'ları (kota); dal zinciri
(`--base delegate/<önceki>`; dağınık, düzeltmeler bağlamsız); tüm planı tek işte yollamak (görev
bazlı kontrol kaybolur).

## Bileşenler

### `scripts/delegate.sh` — yeni bayraklar (yalnız `--mode write`)

- `--plan <PLAN_DIR>`
  - **Plan yokken** (`PLAN_DIR/plan.json` yok): `--base` zorunlu. `PLAN_DIR` oluşturulur (umask 077),
    `PLAN_DIR/worktree` worktree'si ve `delegate/<plan-id>` dalı `base_commit`'ten açılır
    (`core.hooksPath=/dev/null`). Plan kimliği `PLAN_DIR`'in son bileşenidir (`[A-Za-z0-9._-]`,
    `.` ile başlamaz). Sabitlenen değerler `plan.json`'a yazılır: `id`, `repo` (TOP), `cwd`, `prefix`,
    `branch`, `base`, `base_commit`, `start_branch`, `gitdir`, `gitfile_hex`, `created_at`.
  - **Plan varken:** `--base` verilirse exit 2. `--cwd` plan.json'daki `cwd` ile aynı olmalı, değilse
    exit 2. Worktree `wt_tampered` kontrolünden (plan.json'daki `gitfile_hex` ile) geçmezse exit 2 ve
    iş başlamaz. Mevcut worktree yeniden kullanılır.
  - Her iş kendi dizinini alır: `PLAN_DIR/jobs/<n>/` (`n` = 1, 2, …; sıradaki boş numara). İçerik
    bugünkü job dir ile aynı (`brief.md`, `events.jsonl`, `stderr.log`, `result.md`, `meta.json`, `pid`),
    böylece `watch.sh` değişmeden çalışır. İlk stdout satırı yine `JOB_DIR=<path>`.
  - `--id` ile birlikte verilemez (exit 2).
- `--resume <session_id>` — yalnız `--plan` ile (yoksa exit 2). Script, `PLAN_DIR/jobs/*/meta.json`
  içinde `session_id`'si bu değer olan bir iş arar; yoksa exit 2. Geçerliyse `claude -p --resume <id>`
  ile çalıştırılır. Oturumlar şirket hesabının config dizininde çalışma dizinine göre tutulduğu için
  plan worktree'si (aynı yol) bu çağrıyı mümkün kılar. Brief dosyası yeni kullanıcı mesajı olur.
- `--title "<görev adı>"` — commit mesajı: `delegate(<plan-id>): <title>`. Verilmezse
  `delegate(<plan-id>): job <n>`. Satır sonu içeremez, 200 karakteri aşamaz (exit 2).
- **Kilit:** `PLAN_DIR/lock` `mkdir` ile alınır; alınamazsa exit 2 ("plan'da başka bir iş çalışıyor").
  Script çıkarken (trap) bırakılır. Ölü bir kilit (`lock/pid`'deki süreç yaşamıyor) devralınır.
- `--plan` + `--mode ro` → exit 2.
- Commit toplama bugünkü write mantığıyla aynı: sabitlenen git dizini (`plan.json.gitdir`), hook'lar
  kapalı, `--no-verify`, `.git` kurcalanmışsa hiçbir şey toplanmaz (`commit_failed: true`). Her iş dala
  yeni bir commit ekler; değişiklik yoksa commit yok. Commit'ten sonra dalın ucunun yeni commit olduğu
  doğrulanır (bugünkü kontrol).
- `meta.json`'a eklenenler: `plan_id`, `plan_dir`, `job_n`, `title`, `resumed_from` (session id ya da
  null), `parent_commit` (iş başlamadan önce dalın ucu). Diğer alanlar bugünküyle aynı; `worktree`
  plan worktree'sidir ve iş sonunda **silinmez**.
- Plansız (`--plan` yok) çağrılar bugünkü gibi davranır; mevcut testler değişmeden geçer.

### `SKILL.md` — yeni "Plan modu" bölümü

**Ne zaman teklif edilir:** Bir implementasyon planı (writing-plans çıktısı) hazır, ikinci hesap
tanımlı, görevler bölüm 1'deki "self-contained" ölçütünü karşılıyor. Tek soru:

> Bu planı şirket hesabıyla yürüteyim mi? — kod şirket hesabında, kontrol bende; `<base>` dalından,
> N görev, görev başına en fazla 3 düzeltme turu. Commit'lenmemiş değişiklikler işe görünmez.

Hayır → olağan `superpowers:subagent-driven-development`.

**Kurulum:** `PLAN_DIR="$DELEGATE_CACHE_DIR/plans/<YYYYMMDD-HHMMSS>-<slug>"`. `PLAN_DIR/progress.md`
oluşturulur: plan dosyasının yolu, base, görev listesi (durum: bekliyor / sürüyor / tamam / durdu),
her görev için iş numaraları, session id, tur sayısı, maliyet.

**Görev döngüsü** (her görev için):
1. **Brief** (scratchpad'e): görev metni plandan **olduğu gibi**; kısa proje bağlamı (repo, mimari
   kararlar, dokunulmayacaklar); önceki görevlerin birer satırlık özetleri; "testleri/derlemeyi
   koşamazsan koşamadığın komutları raporla" notu. Planın kendisi base'de commit'li değilse işe
   görünmez — bu yüzden görev metni her zaman brief'tedir.
2. **İş:** `delegate.sh --mode write --plan "$PLAN_DIR" --cwd <repo/dir> --brief <dosya> --title "<Task N: …>"`
   (+ ilk görevde `--base <ref>`), `run_in_background: true`; `JOB_DIR=` gelince cmux yan paneli.
3. **Kontrol** (ana oturum, subagent yok):
   - `meta.json` hata/izin reddi durumları → aşağıdaki durma koşulları.
   - `git -C <worktree> diff --stat <parent_commit>..<commit>`; yalnız ilgili hunk'lar okunur.
   - Önce spesifikasyon uyumu (eksik/fazla iş), sonra kalite.
   - **Güvenlik kapısı:** diff build/hook/CI/script dosyalarına dokunuyorsa (`build.gradle*`,
     `settings.gradle*`, `gradle/`, `package.json`, `Makefile`, `*.sh`, `.githooks/`, `.husky/`,
     `.hooks/`, `core.hooksPath`'in dizini, `.github/workflows/`, `.gitlab-ci.yml`, …) o hunk'lar tam
     gösterilir ve test koşmadan **önce** kullanıcı onayı alınır. Plan onayı bunu kapsamaz.
   - Plandaki test/doğrulama komutları worktree içinde koşulur.
4. **Kusur varsa:** bulgular listesi düzeltme brief'i olur; aynı görevin son işinin `session_id`'si ile
   `--resume`; yeni commit; 3. adıma dönülür. Tur sayısı `progress.md`'de.
5. **Temizse:** `progress.md` güncellenir; kullanıcıya tek satır (görev, tur, maliyet); sonraki görev.

**Durma koşulları** (dur, göster, sor):
- 3 düzeltme turu sonrası hâlâ kusur → kalan bulgular; seçenekler: ana oturum bitirir / bir tur daha
  (yeni brief, yeni oturum) / plan durur.
- `permission_denials` ya da raporda "Blocked" → komutları listele, hangilerinin burada çalışacağını
  sor; yalnız onaylananlar.
- İş hatası (`is_error`, `error_max_turns`, boş rapor) → son ~20 olay satırı + `stderr.log`;
  seçenekler: yeniden dene / ana oturum yapar / plan durur.
- `.git` kurcalanmış → plan anında durur; worktree'de hiçbir git komutu yok; temizlik bugünkü kuralla
  kullanıcıya.
- `commit_failed` → worktree tek kopya; hiçbir şeye dokunma, göster, sor.
- Güvenlik kapısı (yukarıda).

**Plan sonu:** özet (görevler, toplam maliyet, toplam tur); `git -C <repo> diff --stat
<base_commit>...delegate/<plan-id>`; hook/CI/build değişiklikleri tam gösterilir; "birleştireyim mi?".
Birleştirme, worktree kaldırma ve dal silme kuralları bugünkü write moduyla aynı (`--no-ff`, dal
değiştirmek yok, `-D` yok, `--force` yok; worktree yolu `PLAN_DIR/worktree`).

**Devam etme:** oturum kesilir ya da `/clear` olursa `progress.md` okunur, kalınan görevden devam edilir.
Devir notu (handoff) istenirse `PLAN_DIR` ve `progress.md` yolu nota yazılır.

### `README.md`

Plan modu için kısa bölüm: bayraklar, `PLAN_DIR` düzeni, kilit, `--resume` kısıtı.

### Kullanıcı tercihi ile uyum

`~/.claude/CLAUDE.md`'deki "plan her zaman subagent-driven" kuralına bir cümle eklenir: ikinci hesap
tanımlıysa önce plan modu teklif edilir; hayırsa subagent-driven. (Bu dosya repo dışında; değişiklik
uygulama sırasında kullanıcıya gösterilerek yapılır.)

## Testler

`tests/` düzenine, `fake-claude.sh` ile (gerekirse `--resume` argümanını ve session id'yi
kaydedecek şekilde genişletilir) yeni `tests/test_delegate_plan.sh`:

- Plan kurulumu: dal, worktree, `plan.json` alanları; `jobs/1/` dizini; ilk satır `JOB_DIR=`.
- İki ardışık iş aynı dalda iki commit; ikinci işin `parent_commit`'i birincinin commit'i; mesajlar
  `--title`'dan.
- Değişiklik olmayan iş commit atmaz; worktree silinmez.
- `--resume`: plandaki bir session id kabul edilir ve `claude`'a `--resume <id>` iletilir; bilinmeyen id
  exit 2, `--plan`'sız `--resume` exit 2.
- Bayrak çakışmaları exit 2: plan varken `--base`; plan yokken `--base` eksik; `--plan` + ro;
  `--plan` + `--id`; farklı `--cwd`; satır sonlu `--title`.
- Görevler arasında `.git` dosyası değiştirilirse sonraki çağrı exit 2, iş başlamaz.
- Kilit: dolu kilitle exit 2; ölü pid'li kilit devralınır.
- Mevcut `test_delegate.sh`, `test_delegate_write.sh`, `test_watch.sh` değişmeden geçer.

## Kapsam dışı

- İnceleme subagent'ları, maliyet tavanı, görevlerin paralel yürütülmesi.
- Şirket hesabının ayarlarını/izinlerini değiştirmek (skill kuralı: dokunulmaz).
