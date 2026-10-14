# MYT DirectX–Metal runtime kaynakları

MYT'nin grafik çevirisi üçüncü taraf açık kaynak koduna dayanır. Bu dosya kaynak ve
paket kimliklerini kaydeder; MYT tarafından geliştirilmiş yeni bir grafik motoru iddiası değildir.

- Wine 11.18 Staging: https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18
  Kaynak Wine: https://gitlab.winehq.org/wine/wine (LGPL).
- DXMT upstream: https://github.com/3Shain/dxmt
- Mevcut Wine 11 entegrasyonu için kullanılan fork: https://github.com/notpop/dxmt
  Kaynak commit: `924a607`; upstream v0.80 dönemine ait Wine 11 Metal view uyarlaması.
- Paket yayıncısı: https://github.com/ramiabih/play-windows-steam-on-mac/releases/tag/dxmt-fork-v1
  Paket: `dxmt-fork-macos-arm64.tar.gz`.
  SHA-256: `51043dd4cf585d52b1415c452052a0953dc01f9f9663ae0c3d6984907c25fab5`.
  Paket MANIFEST.txt: Wine hedefi 11.8, kaynak commit 924a607, derleme 20 Haziran 2026.
  MYT'de Wine 11.18 ile D3D11 donanım cihazı oluşturma testi geçti; oyun sunumu/FPS testi henüz yapılmadı.
- Ayrıca araştırma için indirilen upstream DXMT v0.80 paketi bu runtime'a kurulmadı.
  Mevcut Gcenx motoru upstream paketin beklediği `winemac` Metal view sembollerini dışa aktarmıyor.

Runtime dosyaları sürüm kontrolü dışında tutulur ve kaynak depoya dahil edilmez.
Dağıtılabilir ürün hazırlanırken kullanılan kesin kaynak sürümlerinin lisans metinleri,
telif bildirimleri ve gerekli kaynak sunumu ayrıca pakete dahil edilmelidir.

Kurulum: `scripts/setup-dxmt`. Ayrı motor: `runtime/Wine DXMT.app`.
Oyun ortamı: `bottles/megabonk`. Vulkan ortamı: `bottles/steam`.
