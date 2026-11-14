# Klipin (versi Supabase)

Website untuk meng-upload video dan foto, lalu membagikannya lewat link. Ada tab Beranda, Upload, Unggahan, Tersimpan, Profil, dan Pengaturan. Unggahan baru muncul realtime di semua orang yang sedang membuka web.

Siapa pun bisa menonton tanpa akun. Mengunggah, menyimpan ke akun, dan mengubah profil butuh akun (email dan kata sandi).

## Isi folder (semua file di satu tingkat, tanpa subfolder)
- index.html : halaman aplikasi
- adapter.js : penghubung ke Supabase
- config.js : URL dan key proyek Supabase (di ZIP ini sudah terisi dengan proyek kamu)
- supabase.js : library supabase-js 2.118.0 (lisensi MIT, lihat LICENSE-supabase-js.txt)
- supabase.sql : dipakai sekali di SQL Editor Supabase, tidak perlu diunggah ke hosting

Unggah index.html, adapter.js, config.js, dan supabase.js ke hosting. Kalau supabase.js terlewat, web otomatis mencoba mengambil library yang sama dari CDN selama ada internet.

## Pemasangan (sekitar 5 menit)
1. Buat proyek di https://supabase.com
2. Buka SQL Editor, New query, tempel seluruh isi supabase.sql, klik Run. Aman dijalankan berulang.
3. Buka dashboard proyekmu, klik tombol Connect di bagian atas. Salin Project URL dan publishable key (diawali sb_publishable_) ke config.js. Key juga ada di Project Settings, API Keys, dan key anon lama masih bisa dipakai. Jangan pernah memasukkan secret key atau service_role key. Tulis URL tanpa /rest/v1/ di belakangnya (adapter juga membuangnya otomatis kalau terlanjur tertulis).
4. Buka Authentication, Providers, Email.
   - Matikan "Confirm email" kalau ingin daftar langsung masuk.
   - Kalau dibiarkan menyala, pengguna harus klik link di email dulu, dan Authentication, URL Configuration, Site URL harus diisi alamat webmu.
5. Taruh file di hosting statis (GitHub Pages, Netlify, Vercel, Cloudflare Pages). Untuk coba di komputer: jalankan `python3 -m http.server 8080` di folder ini lalu buka http://localhost:8080
   - GitHub Pages: unggah file ke repo, lalu Settings, Pages, Deploy from a branch, pilih main dan folder (root). Tunggu 1 sampai 2 menit.
6. Daftar akun pertama lewat tab Profil.

## Kalau muncul pesan galat
- "Library Supabase gagal dimuat": file supabase.js belum terunggah. Cek dengan membuka alamat webmu ditambah /supabase.js, harus tampil kode, bukan halaman 404.
- "Isi url dan key Supabase di config.js dulu": config.js belum diisi atau belum terunggah.
- Status tetap "Belum terhubung": biasanya realtime belum aktif. Jalankan ulang supabase.sql.

## Jadi admin (opsional)
Admin bisa menghapus unggahan siapa pun. Setelah mendaftar, salin User UID kamu dari Authentication, Users, lalu jalankan di SQL Editor:

    insert into public.admins (id) values ('UID-KAMU');

Muat ulang halaman, tombol Hapus akan muncul di unggahan orang lain.

## Cara kerja link
- Setiap unggahan punya link: alamat webmu + #v-kode. Siapa pun yang membuka link langsung masuk ke videonya.
- Unggahan "Hanya lewat link" tidak tampil di beranda orang lain, tapi bisa dibuka siapa pun yang punya link-nya.
- File disimpan di bucket publik bernama media, di folder berisi ID pemiliknya.

## Batas
- Batas di web ini 5000 MB per file. Format: MP4, WebM, JPG, PNG, GIF, WebP.
- Paket gratis Supabase hanya mengizinkan 50 MB per file. File lebih besar baru bisa diunggah setelah paket diupgrade dan Storage > Settings > Global file size limit dinaikkan.
- Untuk mengubah batas, samakan tiga tempat: Global file size limit di Supabase, file_size_limit di supabase.sql, dan maxMB di config.js.
- Upload dikirim sekali jalan. Untuk file sangat besar dan sinyal tidak stabil, upload resumable lebih andal (belum ada di versi ini).
- Jumlah unggahan tidak dibatasi aplikasi. Kuota penyimpanan mengikuti paket Supabase kamu.
- Beranda memuat 1000 unggahan terbaru. Unggahan yang lebih lama tetap bisa dibuka lewat link.
