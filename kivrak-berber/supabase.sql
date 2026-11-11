-- Kıvrak Berber randevu sistemi: Supabase kurulumu (v4: ustalar + gelmeyen müşteri)
-- Supabase paneli > SQL Editor > bu dosyanın tamamını yapıştır > Run
-- Dosya tekrar çalıştırılabilir (güvenli): v2/v3 kurulu bir veritabanında da çalıştırarak v4'e geçebilirsin.
-- Mevcut randevular silinmez.
--   Not: v2'de sahte kayıt (geçersiz saat, 45 günden uzak tarih) oluştuysa önce sil, yoksa saat kuralı eklenemez:
--   delete from public.randevular where slot_date > current_date + 45 or slot_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$';
-- İlk kez kuruyorsan en alttaki "v1'den geçiş" bölümüne gerek yok.

-- ============ RANDEVULAR ============
create table if not exists public.randevular (
  id          bigint generated always as identity primary key,
  grup        text   not null,                       -- bir randevunun kapattığı slotları bağlar
  iptal_kodu  text   not null check (char_length(iptal_kodu) >= 20), -- müşterinin iptal bağlantısındaki gizli kod
  slot_date   date   not null,
  slot_time   text   not null check (slot_time ~ '^[0-2][0-9]:[0-5][0-9]$'),
  ad          text   not null check (char_length(ad) between 1 and 80),
  telefon     text   not null check (char_length(telefon) between 6 and 20),
  hizmet      text   not null check (char_length(hizmet) <= 20),
  dil         text   not null default 'tr' check (dil in ('tr','fr','en','nl')),
  berber      text   not null default '',           -- usta id'si ('' = tek usta / eski kayıt)
  olusturma   timestamptz not null default now()
);

-- v4: her ustanın takvimi ayrı. Aynı usta, aynı gün, aynı saat iki kez alınamaz
-- (çift randevuyu veritabanı engeller). v3'teki "gün+saat" kuralının yerini alır.
alter table public.randevular add column if not exists berber text not null default '';
alter table public.randevular drop constraint if exists berber_uzunluk;
alter table public.randevular add constraint berber_uzunluk check (char_length(berber) <= 30);
alter table public.randevular drop constraint if exists randevular_slot_date_slot_time_key;
alter table public.randevular drop constraint if exists randevular_berber_slot_key;
alter table public.randevular add constraint randevular_berber_slot_key unique (berber, slot_date, slot_time);

alter table public.randevular enable row level security;

-- Müşteri (anon): sadece bugünden itibaren en fazla 45 gün sonrasına ekleme yapabilir,
-- OKUYAMAZ (isim/telefon gizli kalır). 45 günlük sınır, sahte kayıtların uzak tarihlere
-- yığılmasını engeller. Müşteri sitesinde CONFIG.kacGun bu değerden küçük olmalı (şu an 14).
drop policy if exists "musteri ekler" on public.randevular;
create policy "musteri ekler" on public.randevular
  for insert to anon
  with check (slot_date >= current_date and slot_date <= current_date + 45);

-- Saat gerçek bir saat olsun ("29:59" gibi değerler girilemesin)
alter table public.randevular drop constraint if exists slot_time_gecerli;
alter table public.randevular add constraint slot_time_gecerli
  check (slot_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');

-- Berber (giriş yapmış kullanıcı): okur ve siler
drop policy if exists "berber okur" on public.randevular;
create policy "berber okur" on public.randevular
  for select to authenticated using (true);

drop policy if exists "berber siler" on public.randevular;
create policy "berber siler" on public.randevular
  for delete to authenticated using (true);

-- Müşteri sitesi sadece "hangi usta, hangi saat dolu" bilgisini bu fonksiyondan alır (isim/telefon yok)
drop function if exists public.dolu_saatler(date, date);
create function public.dolu_saatler(bas date, son date)
returns table (slot_date date, slot_time text, berber text)
language sql
security definer
set search_path = public
as $$
  select r.slot_date, r.slot_time, r.berber
  from public.randevular r
  where r.slot_date between bas and son
$$;

revoke all on function public.dolu_saatler(date, date) from public;
grant execute on function public.dolu_saatler(date, date) to anon, authenticated;

-- ============ MÜŞTERİ İPTALİ ============
-- İptal kodu 36 karakterlik rastgele bir UUID'dir; tahmin edilemez.
-- Müşteri sadece kendi kodunu bilerek kendi randevusunu görebilir ve iptal edebilir.
drop function if exists public.randevu_bilgi(text);
create function public.randevu_bilgi(kod text)
returns table (slot_date date, slot_time text, hizmet text, berber text)
language sql
security definer
set search_path = public
as $$
  select r.slot_date, r.slot_time, r.hizmet, r.berber
  from public.randevular r
  where r.iptal_kodu = kod
    and char_length(kod) >= 20
    and r.slot_date >= current_date
  order by r.slot_date, r.slot_time
$$;

revoke all on function public.randevu_bilgi(text) from public;
grant execute on function public.randevu_bilgi(text) to anon, authenticated;

create or replace function public.randevu_iptal(kod text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  if kod is null or char_length(kod) < 20 then
    return 0;
  end if;
  delete from public.randevular
   where iptal_kodu = kod
     and slot_date >= current_date;
  get diagnostics n = row_count;
  return n;
end
$$;

revoke all on function public.randevu_iptal(text) from public;
grant execute on function public.randevu_iptal(text) to anon, authenticated;

-- ============ BERBER AYARLARI (çalışma saatleri, tatiller, fiyat/süre) ============
create table if not exists public.ayarlar (
  id          int primary key default 1 check (id = 1),   -- tek satır
  veri        jsonb not null default '{}'::jsonb,
  guncelleme  timestamptz not null default now()
);

alter table public.ayarlar enable row level security;

drop policy if exists "berber ayar okur" on public.ayarlar;
create policy "berber ayar okur" on public.ayarlar
  for select to authenticated using (true);

drop policy if exists "berber ayar ekler" on public.ayarlar;
create policy "berber ayar ekler" on public.ayarlar
  for insert to authenticated with check (id = 1);

drop policy if exists "berber ayar gunceller" on public.ayarlar;
create policy "berber ayar gunceller" on public.ayarlar
  for update to authenticated using (id = 1) with check (id = 1);

-- Müşteri sitesi ayarları bu fonksiyondan okur (tablo doğrudan okunamaz)
create or replace function public.ayarlar_oku()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select a.veri from public.ayarlar a where a.id = 1
$$;

revoke all on function public.ayarlar_oku() from public;
grant execute on function public.ayarlar_oku() to anon, authenticated;

-- ============ GELMEYEN MÜŞTERİLER (v4) ============
-- Berber panelde "Gelmedi" dediğinde buraya yazılır. Randevu 30 günde silinse de bu kayıt
-- 6 ay (180 gün) durur; aynı telefon tekrar randevu alınca panel uyarı gösterir.
-- Müşteri (anon) bu tabloya hiç erişemez. Süre gizlilik metniyle aynı olmalı.
create table if not exists public.gelmeyenler (
  id         bigint generated always as identity primary key,
  telefon    text not null check (char_length(telefon) between 6 and 20),  -- sadece rakam, ülke kodlu
  ad         text not null default '' check (char_length(ad) <= 80),
  slot_date  date not null,
  slot_time  text not null check (slot_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  berber     text not null default '' check (char_length(berber) <= 30),
  olusturma  timestamptz not null default now(),
  unique (telefon, slot_date, slot_time)
);

revoke all on public.gelmeyenler from anon;
grant select, insert, delete on public.gelmeyenler to authenticated;
grant all on public.gelmeyenler to service_role;

alter table public.gelmeyenler enable row level security;

drop policy if exists "berber gelmeyen okur" on public.gelmeyenler;
create policy "berber gelmeyen okur" on public.gelmeyenler
  for select to authenticated using (true);

drop policy if exists "berber gelmeyen ekler" on public.gelmeyenler;
create policy "berber gelmeyen ekler" on public.gelmeyenler
  for insert to authenticated with check (true);

drop policy if exists "berber gelmeyen siler" on public.gelmeyenler;
create policy "berber gelmeyen siler" on public.gelmeyenler
  for delete to authenticated using (true);

-- ============ SAKLAMA SÜRESİ ============
-- Randevu tarihinden 30 gün, gelmeyen kaydı 180 gün sonra silinir (gizlilik metniyle aynı olmalı)
create or replace function public.eski_randevulari_sil()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.randevular where slot_date < current_date - 30;
  delete from public.gelmeyenler where slot_date < current_date - 180;
$$;
revoke all on function public.eski_randevulari_sil() from public, anon, authenticated;

-- OTOMATİK SİLME (eklenti gerektirmez): her yeni randevu kaydında 30 günden eski kayıtlar silinir.
-- Gizlilik metnindeki "30 gün sonra silinir" sözü böylece pg_cron kurulmasa da tutulur
-- (en geç, bir sonraki randevu alındığında). Hiç randevu alınmayan dönemlerde eski kayıtlar
-- o zamana kadar durur; bunu da kapatmak için aşağıdaki isteğe bağlı pg_cron satırını kullan.
create or replace function public.temizlik_tetik()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.randevular where slot_date < current_date - 30;
  delete from public.gelmeyenler where slot_date < current_date - 180;
  return null;
end
$$;
revoke all on function public.temizlik_tetik() from public, anon, authenticated;

drop trigger if exists temizlik_tg on public.randevular;
create trigger temizlik_tg
  after insert on public.randevular
  for each statement execute function public.temizlik_tetik();

-- İSTEĞE BAĞLI (her gece, randevu alınmasa da çalışır): Database > Extensions > pg_cron'u aç, sonra:
-- select cron.schedule('eski-randevular', '15 3 * * *', $$select public.eski_randevulari_sil()$$);

-- ============ BERBER HESABI ============
-- Authentication > Users > "Add user" ile e-posta + şifre oluştur.
-- Auth > Providers > Email > "Allow new users to sign up" KAPALI olsun
-- (yoksa herkes hesap açıp müşteri isim/telefonlarını okur).

-- ============ v1'den geçiş (sadece eski sürümü çalıştırdıysan) ============
-- alter table public.randevular add column if not exists iptal_kodu text;
-- update public.randevular set iptal_kodu = gen_random_uuid()::text where iptal_kodu is null;
-- alter table public.randevular alter column iptal_kodu set not null;
-- alter table public.randevular add constraint iptal_kodu_uzunluk check (char_length(iptal_kodu) >= 20);
