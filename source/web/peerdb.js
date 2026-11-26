/* Direct phone-to-phone game state for the web version (PeerJS).
   The manager's phone holds every document of its game and is the hub:
   players connect to it with the game code, send their own writes
   (joining the lobby, votes), and it sends the whole game back to everyone.
   It offers the same small API the game uses on claude.ai (doc / collection /
   set / delete / onSnapshot), so the game code is the same in both places. */
(function () {
  window.IS_WEB = true;
  if (typeof window.Peer !== 'function') return;
  const PREFIX = 'mitchaze-impostor-v1-';
  const RTC = { config: { iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:global.stun.twilio.com:3478' },
  ] } };
  const CLIENT_PATH = /^games\/\d{4}\/(players|votes)\/[A-Za-z0-9_-]{1,64}$/;
  const rooms = {};
  const hostCodes = new Set();
  const codeOf = path => { const m = /^games\/(\d{4})/.exec(path); return m ? m[1] : null; };
  const lsGet = k => { try { return JSON.parse(localStorage.getItem(k)); } catch (e) { return null; } };
  const lsSet = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} };
  const clone = o => JSON.parse(JSON.stringify(o));

  function makeRoom(code, asHost) {
    const r = { docs: asHost ? (lsGet('peerdb:' + code) || {}) : {}, ready: asHost, subs: new Set(), queue: [], conns: new Map(), hostConn: null, closed: false, peer: null, retryT: null };
    const notify = () => r.subs.forEach(f => { try { f(); } catch (e) { console.error(e); } });
    const broadcast = () => { const msg = { t: 'state', docs: r.docs }; r.conns.forEach(c => { if (c.open) { try { c.send(msg); } catch (e) {} } }); };
    const apply = op => { if (op.t === 'set') r.docs[op.path] = op.data; else if (op.t === 'del') delete r.docs[op.path]; };
    r.write = op => {
      apply(op); notify();
      if (asHost) { lsSet('peerdb:' + code, r.docs); broadcast(); return; }
      if (r.hostConn && r.hostConn.open) { try { r.hostConn.send(op); return; } catch (e) {} }
      r.queue.push(op);
    };
    const retry = () => { if (r.closed || r.retryT) return; r.retryT = setTimeout(() => { r.retryT = null; asHost ? start() : connectHost(); }, 3000); };

    function connectHost() {
      const peer = r.peer;
      if (r.closed || !peer || peer.destroyed) return;
      if (peer.disconnected) { try { peer.reconnect(); } catch (e) {} return retry(); }
      let c;
      try { c = peer.connect(PREFIX + code, { reliable: true }); } catch (e) { return retry(); }
      let opened = false;
      const to = setTimeout(() => { if (!opened) { try { c.close(); } catch (e) {} retry(); } }, 10000);
      c.on('open', () => {
        opened = true; clearTimeout(to); r.hostConn = c;
        r.queue.splice(0).forEach(op => { try { c.send(op); } catch (e) {} });
      });
      c.on('data', d => {
        if (d && d.t === 'state' && d.docs && typeof d.docs === 'object') { r.docs = d.docs; r.ready = true; notify(); }
      });
      c.on('close', () => { clearTimeout(to); if (r.hostConn === c) r.hostConn = null; retry(); });
      c.on('error', () => {});
    }

    function start() {
      if (r.closed) return;
      const peer = asHost ? new Peer(PREFIX + code, RTC) : new Peer(RTC);
      r.peer = peer;
      peer.on('open', () => { if (!asHost) connectHost(); });
      peer.on('error', err => {
        const t = err && err.type;
        if (!asHost && t === 'peer-unavailable') { r.hostConn = null; return retry(); }
        // The code's address can stay taken for a few seconds after a reload: try again.
        if (asHost && t === 'unavailable-id') { try { peer.destroy(); } catch (e) {} return retry(); }
        if (t === 'network' || t === 'server-error' || t === 'socket-error' || t === 'socket-closed') {
          if (peer.destroyed) retry();
        }
      });
      peer.on('disconnected', () => { if (!r.closed) setTimeout(() => { if (!r.closed && !peer.destroyed) { try { peer.reconnect(); } catch (e) {} } }, 2000); });
      if (asHost) {
        peer.on('connection', c => {
          c.on('open', () => { r.conns.set(c.peer, c); try { c.send({ t: 'state', docs: r.docs }); } catch (e) {} });
          c.on('data', d => {
            if (!d || typeof d.path !== 'string' || !CLIENT_PATH.test(d.path) || codeOf(d.path) !== code) return;
            if (d.t === 'set') {
              if (!d.data || typeof d.data !== 'object' || JSON.stringify(d.data).length > 4000) return;
              r.write({ t: 'set', path: d.path, data: clone(d.data) });
            } else if (d.t === 'del') r.write({ t: 'del', path: d.path });
          });
          c.on('close', () => r.conns.delete(c.peer));
          c.on('error', () => {});
        });
      }
    }
    r.close = () => { r.closed = true; clearTimeout(r.retryT); try { r.peer && r.peer.destroy(); } catch (e) {} };
    start();
    return r;
  }
  const room = code => rooms[code] || (rooms[code] = makeRoom(code, hostCodes.has(code)));

  const snap = (r, path) => ({ id: path.split('/').pop(), exists: path in r.docs, data: () => r.docs[path], metadata: { fromCache: !r.ready, hasPendingWrites: false } });
  function docRef(path) {
    const code = codeOf(path);
    return {
      path, id: path.split('/').pop(),
      get: async () => snap(room(code), path),
      set: async d => { room(code).write({ t: 'set', path, data: clone(d) }); },
      update: async d => { const r = room(code); r.write({ t: 'set', path, data: Object.assign({}, r.docs[path] || {}, clone(d)) }); },
      delete: async () => { room(code).write({ t: 'del', path }); },
      onSnapshot(next) { const r = room(code); const f = () => { if (r.ready) next(snap(r, path)); }; r.subs.add(f); setTimeout(f, 0); return () => r.subs.delete(f); },
      collection: p => colRef(path + '/' + p),
    };
  }
  function colRef(path) {
    const code = codeOf(path); const depth = path.split('/').length + 1;
    return {
      path, doc: id => docRef(path + '/' + id),
      onSnapshot(next) {
        const r = room(code);
        const f = () => {
          if (!r.ready) return;
          const ds = Object.keys(r.docs).filter(k => k.startsWith(path + '/') && k.split('/').length === depth).map(k => snap(r, k));
          next({ docs: ds, size: ds.length, empty: !ds.length, metadata: { fromCache: false, hasPendingWrites: false }, docChanges: () => [] });
        };
        r.subs.add(f); setTimeout(f, 0); return () => r.subs.delete(f);
      },
    };
  }
  window.PeerDb = {
    doc: docRef, collection: colRef,
    hostRoom(code) { hostCodes.add(code); },
    leave(code) {
      Object.keys(rooms).forEach(k => { if (!code || k === code) { rooms[k].close(); delete rooms[k]; } });
      if (code) hostCodes.delete(code); else hostCodes.clear();
    },
  };
})();
