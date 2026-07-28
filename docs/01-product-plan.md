# 01 — Ürün Planı: mectrics

## Vizyon
> Mac'inin nabzını, dikkatini dağıtmadan, menü çubuğunda ve isteğe bağlı canlı
> widget'larda gösteren; hafif, gizli ve güzel bir sistem monitörü.

**Tek cümle:** *iStat kadar derin, Stats kadar açık ruhlu, hepsinden daha hafif ve modern.*

## Hedef kullanıcılar
1. **Geliştiriciler / power-user** — build sırasında CPU/RAM/termal takibi, per-process.
2. **Yaratıcılar (video/3D)** — GPU, termal, fan, bellek baskısı.
3. **Genel MacBook kullanıcısı** — pil sağlığı, "neden yavaş?" hızlı cevabı, sade görünüm.

## Konumlandırma & farklılaşma
Bkz. `00-research.md §4`. Üç sütun: **Sparkline-first menü çubuğu**, **çift widget modu (WidgetKit + canlı floating panel)**, **radikal hafiflik + gizlilik**.

---

## Özellik listesi (modüller)

Her modül: menü çubuğu göstergesi (sayı + opsiyonel sparkline) → tıklayınca detay popover → opsiyonel floating panel / widget.

> **Karar:** Ürün **tamamen ücretsiz ve açık kaynak** (bkz. `03-roadmap.md`). Free/Pro
> ayrımı **yok** — tüm modüller herkese açık. "Katman" sütunu yalnızca uygulama sırasını
> gösterir: *Core* = MVP çekirdeği, *İleri* = donanıma bağlı/daha karmaşık (sonraki faz).

### Metrik modülleri
| Modül | Menü çubuğu | Detay / popover | Sıra |
|-------|-------------|-----------------|------|
| **CPU** | Toplam %, sparkline | Per-core barlar, user/system/idle, top 5 process | Core |
| **Bellek (RAM)** | Kullanım %, sparkline | Used/wired/compressed/cached, **memory pressure**, swap, top 5 process | Core |
| **Pil** | %, ikon, (opsiyonel süre) | Şarj/deşarj watt, health %, cycle count, sıcaklık, güç kaynağı | Core |
| **Ağ (Network)** | ↓/↑ hız | Aktif arayüz, IP, toplam gün/oturum trafiği, top process | İleri |
| **Disk** | Kullanım % veya R/W | Volume başına doluluk, read/write throughput, SMART durumu | İleri |
| **GPU** | Kullanım % | GPU utilization, VRAM (varsa), termal | İleri |
| **Sensörler / Sıcaklık** | Seçili sensör °C | Tüm SMC/thermal sensörler, CPU/GPU/SSD sıcaklıkları | İleri |
| **Fanlar** | RPM | Fan başına RPM, min/max | İleri |
| **Bluetooth** | — (popover) | Bağlı cihaz pil seviyeleri (AirPods, klavye, mouse) | İleri |
| **Saat / Zaman dilimi** | Çoklu TZ (opsiyonel) | Ek zaman dilimleri | İleri |

### Deneyim özellikleri (cross-cutting)
- **Sparkline-first**: her modülde son ~60 örneğin canlı mini grafiği.
- **Floating panel (canlı widget)**: sürüklenebilir, always-on-top opsiyonu, gerçek zamanlı — WidgetKit'in throttle sınırını aşan gerçek "canlı widget".
- **WidgetKit masaüstü/Notification Center widget'ı**: sistem-native, düşük frekanslı (small/medium/large) — Pro'da tüm boyutlar.
- **Bildirim eşikleri**: modül başına kural (CPU > %90, 30sn; pil < %20; disk < 10 GB; sıcaklık > 90°C). — Pro'da gelişmiş.
- **Klavye kısayolu**: global hotkey ile ana paneli aç/kapat.
- **Tema & accent**: açık/koyu, accent renk, sparkline stili, menü çubuğu yoğunluğu (compact/normal).
- **Onboarding**: 3 adım — profil seç (Basit / Geliştirici / Yaratıcı) → modül seç → izinler.
- **Güç-farkında örnekleme**: pilde/uykuda örnekleme frekansını düşür (hafiflik + pil dostu).
- **Gizlilik**: sıfır telemetri; hiçbir veri cihazdan çıkmaz.
- **Launch at login**, **otomatik güncelleme** (Sparkle).

---

## Monetizasyon — **Tamamen ücretsiz & açık kaynak** (karar verildi)

Fiyat kapısı, lisans anahtarı, Free/Pro ayrımı **yok**. Tüm modüller herkese açık.
- **Lisans:** açık kaynak (öneri: MIT veya GPLv3 — `03-roadmap.md`'de netleşecek).
- **Dağıtım:** GitHub Releases üzerinden imzalı + notarized **DMG**; Homebrew Cask ileride.
- **Sürdürülebilirlik (opsiyonel, baskısız):** GitHub Sponsors / "Buy me a coffee" bağlantısı — hiçbir özelliği kilitlemez.
- **Avantaj:** hızlı benimsenme, topluluk katkısı/güveni, Stats'ın kanıtladığı model. "Sıfır telemetri + açık kaynak" güçlü bir gizlilik argümanı.

---

## Başarı metrikleri (kendi ölçümümüz — kullanıcı verisi DEĞİL)
- Kendi kaynak kullanımımız: RAM < 60 MB, ortalama CPU < %1 (idle örnekleme).
- Çökme oranı ~0; enerji etkisi Activity Monitor'da "Düşük".
- Free → Pro dönüşüm (mağaza/lisans satış sayısı, anonim toplam).

## Kapsam dışı (v1'de yok)
- iOS/iPadOS companion (v2+).
- iCloud sync (v2+).
- Uzak sunucu izleme.
- Eklenti/script sistemi.

## Sürüm hedefleri (özet — detay roadmap'te)
- **v0.1 (MVP):** Menü çubuğunda CPU + RAM + Pil, sparkline, popover, ayarlar, launch-at-login.
- **v0.5:** Network, Disk, Bluetooth, floating panel, onboarding, temalar, bildirimler.
- **v1.0:** WidgetKit widget, Pro modülleri (GPU/Sensör/Fan), lisanslama, notarization + dağıtım.
