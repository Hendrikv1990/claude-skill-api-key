#!/usr/bin/env node
// Shares a key through a password-protected Bitwarden Send, without the key, the link or the password
// ever reaching stdout, argv, a shell variable or a file. Secrets live only in this process and in pipes.
//
//   share.mjs <prefix>            generate a new <prefix>_<32 chars> key and share it
//   share.mjs --clipboard         share whatever is on the clipboard now
//   share.mjs --next              move the next queued item (link, then password) to the clipboard
//   share.mjs --revoke <sendId>   delete a Send early
// Options: --hours N (default 24), --opens N (default 3), --to <email> (email verification instead of password)
//
// The Bitwarden session comes from the macOS keychain (stored by unlock.sh), never from the environment of the caller.
import { spawn, spawnSync } from 'node:child_process';
import { randomInt } from 'node:crypto';

const PB = process.env.APIKEY_PASTEBOARD || '';            // '' = system clipboard; tests use a private one
const QUEUE_PB = process.env.APIKEY_QUEUE_PASTEBOARD || 'apikey-share-queue';
const TTL = Number(process.env.APIKEY_TTL || 60);           // seconds an item stays on the clipboard
const QUEUE_TTL = Number(process.env.APIKEY_QUEUE_TTL || 900);
const BW = process.env.APIKEY_BW || 'bw';
const KEYCHAIN_SERVICE = process.env.APIKEY_KEYCHAIN_SERVICE || 'apikey-bw-session';
const PREFIX_RE = /^[a-z][a-z0-9]*(_[a-z0-9]+)*$/;
const ALNUM = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

const die = (msg, code = 1) => { console.error(`error: ${msg}`); process.exit(code); };
const rand = (n) => Array.from({ length: n }, () => ALNUM[randomInt(ALNUM.length)]).join('');

// --- pasteboard (JXA via osascript; secrets travel on stdin) -----------------------------------------
const OPEN_PB = 'ObjC.import("AppKit"); const openPb = n => n ? $.NSPasteboard.pasteboardWithName(n) : $.NSPasteboard.generalPasteboard;';
const READ_STDIN = 'const d=$.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile; const s=$.NSString.alloc.initWithDataEncoding(d,$.NSUTF8StringEncoding);';

function jxa(script, args = [], input = '') {
  const r = spawnSync('osascript', ['-l', 'JavaScript', '-e', script, ...args], { input, encoding: 'utf8' });
  if (r.status !== 0) die('could not access the clipboard');
  return r.stdout.trim();
}

// Concealed + transient for clipboard managers, current-host only (no Universal Clipboard). Returns changeCount.
const copy = (text, name = PB) => jxa(`${OPEN_PB} function run(a){ ${READ_STDIN}
  const pb=openPb(a[0]); pb.prepareForNewContentsWithOptions(1);
  pb.setStringForType(s,"public.utf8-plain-text");
  pb.setStringForType("","org.nspasteboard.ConcealedType"); pb.setStringForType("","org.nspasteboard.TransientType");
  return String(pb.changeCount); }`, [name], text);

const read = (name = PB) => jxa(`${OPEN_PB} function run(a){ const s=openPb(a[0]).stringForType("public.utf8-plain-text"); return s.isNil()?"":s.js; }`, [name]);
const clear = (name) => jxa(`${OPEN_PB} function run(a){ openPb(a[0]).clearContents; return ""; }`, [name]);

// Clears later, only if nothing else was copied since. Holds no secret.
function wipeLater(count, ttl, name = PB) {
  spawn('osascript', ['-l', 'JavaScript', '-e', `${OPEN_PB} function run(a){ delay(Number(a[0]));
    const pb=openPb(a[2]); if (String(pb.changeCount)===a[1]) pb.clearContents; }`, String(ttl), String(count), name],
  { detached: true, stdio: 'ignore' }).unref();
}

function putOnClipboard(text) { wipeLater(copy(text), TTL); }

// The queue is a private named pasteboard holding a JSON array of {label, value}.
function setQueue(items) {
  if (!items.length) { clear(QUEUE_PB); return; }
  wipeLater(copy(JSON.stringify(items), QUEUE_PB), QUEUE_TTL, QUEUE_PB);
}
function getQueue() { try { return JSON.parse(read(QUEUE_PB) || '[]'); } catch { return []; } }

// --- bitwarden ---------------------------------------------------------------------------------------
function session() {
  const r = spawnSync('security', ['find-generic-password', '-s', KEYCHAIN_SERVICE, '-w'], { encoding: 'utf8' });
  if (r.status !== 0 || !r.stdout.trim()) die('Bitwarden is locked. In your own terminal run: bash ~/.claude/skills/api-key/unlock.sh');
  return r.stdout.trim();
}

function bw(args, input) {
  const r = spawnSync(BW, args, { input, encoding: 'utf8', env: { ...process.env, BW_SESSION: session(), BW_NOINTERACTION: 'true' } });
  if (r.error?.code === 'ENOENT') die('Bitwarden CLI not found. Install: brew install bitwarden-cli');
  return r;
}

function requireUnlocked() {
  const r = bw(['status']);
  let status = 'unknown';
  try { status = JSON.parse(r.stdout).status; } catch {}
  if (status !== 'unlocked') die(`Bitwarden is ${status}. In your own terminal run: bash ~/.claude/skills/api-key/unlock.sh`);
}

// --- commands ----------------------------------------------------------------------------------------
function parse(argv) {
  const o = { hours: 24, opens: 3, to: null, mode: null, prefix: null, id: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--hours') o.hours = Number(argv[++i]);
    else if (a === '--opens') o.opens = Number(argv[++i]);
    else if (a === '--to') o.to = argv[++i];
    else if (a === '--clipboard') o.mode = 'clipboard';
    else if (a === '--next') o.mode = 'next';
    else if (a === '--revoke') { o.mode = 'revoke'; o.id = argv[++i]; }
    else if (!a.startsWith('-') && !o.prefix) { o.mode = 'generate'; o.prefix = a; }
    else die(`unknown argument: ${a}`, 2);
  }
  if (!o.mode) die('usage: share.mjs <prefix> | --clipboard | --next | --revoke <id> [--hours N] [--opens N] [--to email]', 2);
  if (o.mode === 'generate' && !PREFIX_RE.test(o.prefix)) die('prefix must be lowercase letters/digits separated by single underscores, e.g. myapp_webhook', 2);
  if (!(Number.isInteger(o.hours) && o.hours >= 1 && o.hours <= 24 * 30)) die('--hours must be 1-720', 2);
  if (!(Number.isInteger(o.opens) && o.opens >= 1 && o.opens <= 100)) die('--opens must be 1-100', 2);
  if (o.to && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(o.to)) die('--to must be an email address', 2);
  if (o.mode === 'revoke' && !/^[0-9a-f-]{36}$/i.test(o.id || '')) die('--revoke needs a Send id', 2);
  return o;
}

function next() {
  const [item, ...rest] = getQueue();
  if (!item) { console.log('Nothing queued.'); return; }
  putOnClipboard(item.value);
  setQueue(rest);
  const after = rest.length ? ` Next: ${rest[0].label} (say "next").` : ' Queue empty.';
  console.log(`Copied to clipboard: ${item.label}, clears in ${TTL}s.${after}`);
}

function revoke(id) {
  requireUnlocked();
  const r = bw(['send', 'delete', id]);
  if (r.status !== 0) die('could not delete the Send (wrong id, or already gone)');
  console.log(`Send ${id} deleted. The link no longer works.`);
}

function share(o) {
  requireUnlocked();
  let secret;
  if (o.mode === 'generate') secret = `${o.prefix}_${rand(32)}`;
  else {
    secret = read();
    if (!secret) die('the clipboard is empty');
    if (secret.length > 1000) die('the clipboard holds more than 1000 characters; copy only the key');
    clear(PB); // the copy the user made is now in the Send; do not leave it lying around
  }

  const password = o.to ? null : rand(24);
  const expires = new Date(Date.now() + o.hours * 3600 * 1000).toISOString();
  const req = {
    object: 'send', type: 0,
    name: o.prefix ? `${o.prefix} key` : 'Shared key',
    notes: null,
    text: { text: secret, hidden: true },
    file: null,
    maxAccessCount: o.opens,
    expirationDate: expires,
    deletionDate: expires,
    password,
    emails: o.to ? [o.to] : null,
    disabled: false,
    hideEmail: true,
  };
  const r = bw(['send', 'create'], Buffer.from(JSON.stringify(req)).toString('base64'));
  let res = null;
  try { res = JSON.parse(r.stdout); } catch {}
  if (r.status !== 0 || !res?.accessUrl) die(`Bitwarden refused the Send${o.to ? ' (email verification may need a paid plan; try without --to)' : ''}`);

  const items = [];
  if (o.mode === 'generate') items.push({ label: 'the key, for your own config', value: secret });
  items.push({ label: 'the Send link (paste into the email)', value: res.accessUrl });
  if (password) items.push({ label: 'the Send password (send it by Signal or SMS, not email)', value: password });

  const [first, ...rest] = items;
  putOnClipboard(first.value);
  setQueue(rest);

  const access = o.to ? `only ${o.to} after an emailed code` : 'password-protected';
  console.log(`Send created: id ${res.id}, ${access}, ${o.opens} opens max, expires ${expires.slice(0, 16).replace('T', ' ')} UTC.`);
  console.log(`Copied to clipboard: ${first.label}, clears in ${TTL}s. Next: ${rest[0].label} (say "next").`);
}

const o = parse(process.argv.slice(2));
if (o.mode === 'next') next();
else if (o.mode === 'revoke') revoke(o.id);
else share(o);
