/* Klipin: adapter Supabase. Menyediakan database, pengguna, dan penyimpanan untuk index.html. */
(function () {
  'use strict';
  var C = window.KLIPIN || {};
  var url = String(C.url || '').trim().replace(/\/(rest|auth|storage|realtime|functions)\/v1.*$/i, '').replace(/\/+$/, ''), key = String(C.key || '').trim();
  if (!window.supabase || !window.supabase.createClient) { window.KLIPIN_ERR = 'Library Supabase gagal dimuat. Pastikan file supabase.js ikut diunggah, satu tempat dengan index.html.'; return; }
  if (!/^https?:\/\/\S+$/.test(url) || !key || /XXXX|ISI_/.test(url + key)) { window.KLIPIN_ERR = 'Isi url dan key Supabase di config.js dulu.'; return; }

  var sb = window.supabase.createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } });
  window.KLIPIN_SB = sb;
  window.KLIPIN_MEDIA = url + '/storage/v1/object/public/media/';

  function mapErr(e) {
    e = e || {};
    var m = String(e.message || e.error_description || e.error || ''), c = String(e.code || e.statusCode || e.status || '');
    if (/exceeded the maximum|too large|payload too large/i.test(m) || c === '413') return { code: 'server_too_large', message: m };
    if (/mime type|invalid_mime/i.test(m + ' ' + c)) return { code: 'unsupported_type', message: m };
    if (/row-level security|permission denied|not authorized|unauthorized|jwt/i.test(m) || /^(401|403|42501)$/.test(c)) return { code: 'permission_denied', message: m };
    if (/failed to fetch|networkerror|load failed|fetch failed|timeout/i.test(m)) return { code: 'unavailable', message: m };
    return { code: 'unknown', message: m };
  }
  function session() {
    return sb.auth.getSession().then(function (r) { return (r && r.data && r.data.session) || null; }, function () { return null; });
  }
  function uid() { return session().then(function (s) { return s && s.user ? s.user.id : null; }); }
  function hex32() {
    var a = new Uint8Array(16); crypto.getRandomValues(a);
    return Array.prototype.map.call(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }

  // Muat ulang halaman kalau sesi berubah di tab lain (masuk atau keluar).
  var first;
  sb.auth.onAuthStateChange(function (ev, s) {
    var u = s && s.user ? s.user.id : null;
    if (first === undefined) { first = u; return; }
    if (u !== first) setTimeout(function () { location.reload(); }, 300); // ditunda, supaya reload dari halaman sendiri tidak dobel
  });

  function snapDoc(id, row) {
    var d = row ? Object.assign({}, row) : null;
    if (d) delete d.id;
    return { id: id, exists: !!row, data: function () { return d || undefined; }, metadata: { fromCache: false, hasPendingWrites: false } };
  }

  function docT(table, id) {
    return {
      id: id,
      get: function () {
        var q = table === 'posts' ? sb.rpc('get_post', { p_id: id }) : sb.from(table).select('*').eq('id', id).limit(1);
        return q.then(function (r) { if (r.error) throw mapErr(r.error); return snapDoc(id, (r.data || [])[0]); });
      },
      set: function (d) {
        var row = Object.assign({ id: id }, d);
        var q = table === 'posts' ? sb.from(table).insert(row) : sb.from(table).upsert(row);
        return q.then(function (r) { if (r.error) throw mapErr(r.error); });
      },
      delete: function () {
        return sb.from(table).delete().eq('id', id).select('id').then(function (r) {
          if (r.error) throw mapErr(r.error);
          if (!r.data || !r.data.length) throw { code: 'permission_denied' };
        });
      },
      onSnapshot: function (next, onErr) {
        var dead = false;
        sb.from(table).select('*').eq('id', id).limit(1).then(function (r) {
          if (dead) return;
          if (r.error) { if (onErr) onErr(mapErr(r.error)); return; }
          next(snapDoc(id, (r.data || [])[0]));
        });
        return function () { dead = true; };
      }
    };
  }

  function coll(table, o) {
    o = o || {};
    return {
      orderBy: function (k, d) { return coll(table, Object.assign({}, o, { k: k, d: d === 'desc' ? 'desc' : 'asc' })); },
      limit: function (n) { return coll(table, Object.assign({}, o, { n: n })); },
      doc: function (id) { return docT(table, id); },
      onSnapshot: function (next, onErr) {
        var rows = new Map(), dead = false, subbed = false, seq = 0;
        function list() {
          var a = Array.from(rows.values());
          if (o.k) a.sort(function (x, y) { var p = x[o.k], q = y[o.k]; return (p > q ? 1 : p < q ? -1 : 0) * (o.d === 'desc' ? -1 : 1); });
          return o.n ? a.slice(0, o.n) : a;
        }
        function emit() {
          var a = list();
          next({ docs: a.map(function (r) { return snapDoc(r.id, r); }), size: a.length, empty: !a.length, docChanges: function () { return []; }, metadata: { fromCache: !subbed, hasPendingWrites: false } });
        }
        function load() {
          var my = ++seq, q = sb.from(table).select('*');
          if (o.k) q = q.order(o.k, { ascending: o.d !== 'desc' });
          return q.limit(o.n || 1000).then(function (r) {
            if (dead || my !== seq) return;
            if (r.error) { if (onErr) onErr(mapErr(r.error)); return; }
            rows = new Map(r.data.map(function (x) { return [x.id, x]; }));
            emit();
          });
        }
        var ch = sb.channel('klipin-' + table + '-' + hex32().slice(0, 8))
          .on('postgres_changes', { event: '*', schema: 'public', table: table }, function (p) {
            if (dead) return;
            if (p.eventType === 'DELETE') { if (p.old && p.old.id != null) rows.delete(p.old.id); }
            else if (p.new && p.new.id != null) rows.set(p.new.id, p.new);
            emit();
          })
          .subscribe(function (st) {
            if (dead) return;
            if (st === 'SUBSCRIBED') { subbed = true; load(); }
            else if (st === 'CHANNEL_ERROR' || st === 'TIMED_OUT' || st === 'CLOSED') subbed = false;
          });
        load();
        return function () { dead = true; sb.removeChannel(ch); };
      }
    };
  }

  var DB = {
    collection: function (name) {
      if (name !== 'posts' && name !== 'profiles') throw new TypeError('koleksi tidak dikenal: ' + name);
      return coll(name);
    },
    doc: function (path) {
      var m = /^data\/users\/([0-9a-f-]{36})\/me$/.exec(path);
      if (!m) throw new TypeError('path tidak dikenal: ' + path);
      return docT('user_settings', m[1]);
    }
  };

  var USER = {
    id: uid,
    can: function () { return uid().then(function (u) { return !!u; }); },
    canEdit: function () {
      return uid().then(function (u) {
        if (!u) return false;
        return sb.from('admins').select('id').eq('id', u).limit(1).then(function (r) { return !r.error && !!(r.data && r.data.length); });
      });
    },
    me: function () {
      return session().then(function (s) {
        var u = s && s.user;
        if (!u) return null;
        var nm = String(u.email || '').split('@')[0].slice(0, 40);
        sb.from('profiles').upsert({ id: u.id, name: nm }, { onConflict: 'id', ignoreDuplicates: true }).then(function () {}, function () {});
        return { id: u.id, name: nm, avatarUrl: null };
      });
    },
    profiles: function () { return Promise.resolve({}); }
  };

  var ASSETS = {
    upload: function (file, opt) {
      return uid().then(function (u) {
        if (!u) throw { code: 'permission_denied' };
        var ty = (opt && opt.type) || file.type, id = u + '/' + hex32();
        var body = file.type === ty ? file : new Blob([file], { type: ty });
        return sb.storage.from('media').upload(id, body, { contentType: ty, cacheControl: '31536000', upsert: false }).then(function (r) {
          if (r.error) throw mapErr(r.error);
          return { id: id };
        });
      });
    },
    delete: function (id) {
      return sb.storage.from('media').remove([id]).then(function (r) { if (r.error) throw mapErr(r.error); return r.data; });
    }
  };

  window.claude = { use: function (n) { return Promise.resolve(n === 'db' ? DB : n === 'user' ? USER : n === 'assets' ? ASSETS : null); } };
})();
