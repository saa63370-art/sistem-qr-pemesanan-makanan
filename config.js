// ====== KONFIGURASI SUPABASE (isi dengan milik proyek kamu) ======
// Supabase Dashboard > Project Settings > API
const SUPABASE_URL = 'https://XXXXXXXX.supabase.co';
const SUPABASE_ANON_KEY = 'ISI_ANON_PUBLIC_KEY_DI_SINI';

const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ====== Helper umum ======
const rp = (n) => 'Rp ' + Number(n || 0).toLocaleString('id-ID');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));

// Placeholder gambar jika menu belum punya foto
const FOTO_KOSONG =
  'data:image/svg+xml;utf8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><rect width="200" height="200" fill="#e5e7eb"/>' +
    '<text x="100" y="108" font-size="40" text-anchor="middle">🍽️</text></svg>'
  );

// Label stok: dipakai halaman pembeli & pengaturan
function labelStok(stok) {
  if (stok <= 0) return { teks: 'HABIS', kelas: 'bg-red-100 text-red-700' };
  if (stok <= 2) return { teks: `SISA ${stok} PORSI`, kelas: 'bg-yellow-100 text-yellow-800 animate-pulse font-bold' };
  return { teks: 'Tersedia', kelas: 'bg-green-100 text-green-700' };
}

// ====== Gerbang login untuk halaman penjual (kasir & pengaturan) ======
async function requireLogin() {
  const { data: { session } } = await db.auth.getSession();
  if (session) return session;

  return new Promise((resolve) => {
    const ov = document.createElement('div');
    ov.className = 'fixed inset-0 z-50 flex items-center justify-center bg-slate-900/80 p-4';
    ov.innerHTML = `
      <form class="w-full max-w-sm space-y-3 rounded-2xl bg-white p-6 shadow-xl">
        <h2 class="text-xl font-bold">Login Penjual</h2>
        <input name="email" type="email" required placeholder="Email" class="w-full rounded-lg border p-2" />
        <input name="password" type="password" required placeholder="Password" class="w-full rounded-lg border p-2" />
        <p class="err hidden text-sm text-red-600"></p>
        <button class="w-full rounded-lg bg-emerald-600 py-2 font-semibold text-white">Masuk</button>
      </form>`;
    document.body.appendChild(ov);
    const form = ov.querySelector('form');
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const { data, error } = await db.auth.signInWithPassword({
        email: form.email.value, password: form.password.value,
      });
      if (error) {
        const p = form.querySelector('.err');
        p.textContent = 'Login gagal: ' + error.message;
        p.classList.remove('hidden');
        return;
      }
      ov.remove();
      resolve(data.session);
    });
  });
}

async function logout() {
  await db.auth.signOut();
  location.reload();
}
