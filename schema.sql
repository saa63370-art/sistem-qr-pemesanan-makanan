-- =====================================================
-- SKEMA SUPABASE: Kantin Rusunawa UINAM (QR Meja)
-- Jalankan di Supabase Dashboard > SQL Editor
-- =====================================================

-- ---------- TABEL ----------
create table if not exists public.mejas (
  id uuid primary key default gen_random_uuid(),
  nomor_meja text not null unique,
  qr_code_url text
);

create table if not exists public.menus (
  id uuid primary key default gen_random_uuid(),
  nama_makanan text not null,
  harga integer not null check (harga >= 0),
  stok integer not null default 0 check (stok >= 0),
  foto_url text,
  status text not null default 'aman' check (status in ('aman','menipis','habis'))
);

create table if not exists public.toko (
  id uuid primary key default gen_random_uuid(),
  nama_warung text not null,
  qris_image_url text
);

create table if not exists public.pesanans (
  id uuid primary key default gen_random_uuid(),
  meja_id uuid not null references public.mejas(id),
  daftar_menu jsonb not null,
  total_harga integer not null default 0,
  metode_bayar text not null check (metode_bayar in ('qris','cash')),
  status_bayar text not null check (status_bayar in ('menunggu_konfirmasi','belum_bayar_dikasir','lunas')),
  status_pesanan text not null default 'menunggu_bayar'
    check (status_pesanan in ('menunggu_bayar','antri_masak','dimasak','siap_antar','selesai')),
  bukti_bayar_url text,
  created_at timestamptz not null default now()
);

create index if not exists pesanans_created_idx on public.pesanans (created_at desc);

-- ---------- TRIGGER: status menu otomatis dari stok ----------
-- stok = 0 -> habis, stok <= 2 -> menipis, selain itu aman
create or replace function public.set_status_menu()
returns trigger language plpgsql as $$
begin
  new.stok := greatest(new.stok, 0);
  new.status := case
    when new.stok = 0 then 'habis'
    when new.stok <= 2 then 'menipis'
    else 'aman' end;
  return new;
end $$;

drop trigger if exists trg_set_status_menu on public.menus;
create trigger trg_set_status_menu
before insert or update of stok on public.menus
for each row execute function public.set_status_menu();

-- ---------- TRIGGER: proses pesanan baru ----------
-- Hitung ulang total dari harga di database (tidak percaya angka dari browser),
-- cek stok, lalu kurangi stok.
create or replace function public.proses_pesanan()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  item jsonb; m public.menus%rowtype; qty int; total int := 0; hasil jsonb := '[]'::jsonb;
begin
  if new.daftar_menu is null or jsonb_typeof(new.daftar_menu) <> 'array'
     or jsonb_array_length(new.daftar_menu) = 0 then
    raise exception 'Keranjang kosong';
  end if;

  for item in select value from jsonb_array_elements(new.daftar_menu) loop
    qty := (item->>'jumlah')::int;
    if qty is null or qty < 1 then raise exception 'Jumlah tidak valid'; end if;

    select * into m from public.menus where id = (item->>'id')::uuid for update;
    if not found then raise exception 'Menu tidak ditemukan'; end if;
    if m.stok < qty then raise exception 'Stok % tidak cukup', m.nama_makanan; end if;

    update public.menus set stok = stok - qty where id = m.id;
    total := total + m.harga * qty;
    hasil := hasil || jsonb_build_object(
      'id', m.id, 'nama', m.nama_makanan, 'harga', m.harga, 'jumlah', qty);
  end loop;

  new.daftar_menu := hasil;
  new.total_harga := total;
  return new;
end $$;

drop trigger if exists trg_proses_pesanan on public.pesanans;
create trigger trg_proses_pesanan
before insert on public.pesanans
for each row execute function public.proses_pesanan();

-- ---------- STORAGE BUCKET (public agar URL gambar bisa dibuka) ----------
insert into storage.buckets (id, name, public) values
  ('menu-images','menu-images', true),
  ('qris-images','qris-images', true),
  ('bukti-bayar','bukti-bayar', true)
on conflict (id) do nothing;

-- ---------- ROW LEVEL SECURITY ----------
alter table public.mejas    enable row level security;
alter table public.menus    enable row level security;
alter table public.toko     enable row level security;
alter table public.pesanans enable row level security;

-- Pembeli (anon): hanya baca meja/menu/toko, dan buat pesanan
create policy "anon baca mejas" on public.mejas for select to anon, authenticated using (true);
create policy "anon baca menus" on public.menus for select to anon, authenticated using (true);
create policy "anon baca toko"  on public.toko  for select to anon, authenticated using (true);

create policy "anon buat pesanan" on public.pesanans for insert to anon
with check (
  status_pesanan = 'menunggu_bayar'
  and (
    (metode_bayar = 'qris' and status_bayar = 'menunggu_konfirmasi')
    or (metode_bayar = 'cash' and status_bayar = 'belum_bayar_dikasir')
  )
);

-- Penjual/kasir (login Supabase Auth): akses penuh
create policy "kasir kelola mejas"    on public.mejas    for all to authenticated using (true) with check (true);
create policy "kasir kelola menus"    on public.menus    for all to authenticated using (true) with check (true);
create policy "kasir kelola toko"     on public.toko     for all to authenticated using (true) with check (true);
create policy "kasir kelola pesanans" on public.pesanans for all to authenticated using (true) with check (true);

-- Storage policies
create policy "baca gambar publik" on storage.objects for select to anon, authenticated
using (bucket_id in ('menu-images','qris-images','bukti-bayar'));

create policy "pembeli upload bukti bayar" on storage.objects for insert to anon, authenticated
with check (bucket_id = 'bukti-bayar');

create policy "kasir upload menu dan qris" on storage.objects for insert to authenticated
with check (bucket_id in ('menu-images','qris-images'));

create policy "kasir ubah gambar" on storage.objects for update to authenticated
using (bucket_id in ('menu-images','qris-images'));

create policy "kasir hapus gambar" on storage.objects for delete to authenticated
using (bucket_id in ('menu-images','qris-images','bukti-bayar'));

-- ---------- REALTIME ----------
alter publication supabase_realtime add table public.pesanans;
alter publication supabase_realtime add table public.menus;  -- agar label stok pembeli ikut berubah langsung

-- ---------- DATA AWAL ----------
insert into public.toko (nama_warung) select 'Kantin Rusunawa UINAM'
where not exists (select 1 from public.toko);

-- Meja 01 - 20 (ubah jumlahnya sesuai kebutuhan)
insert into public.mejas (nomor_meja)
select lpad(g::text, 2, '0') from generate_series(1, 20) g
on conflict (nomor_meja) do nothing;

-- Langkah manual: Authentication > Users > Add user (email + password untuk penjual/kasir)
