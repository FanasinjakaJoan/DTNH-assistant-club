/**
 * ============================================================================
 *  Tests locaux du webhook Apps Script — sans Google, sans dépendance npm
 * ============================================================================
 *  Simule les services Apps Script (SpreadsheetApp, PropertiesService,
 *  LockService, ContentService, Utilities) par un Sheet en mémoire, charge
 *  ../Code.gs et vérifie le contrat réel du webhook :
 *
 *    - ping / secret invalide / doGet ;
 *    - création des en-têtes et de l'onglet cible ;
 *    - upsert idempotent (rejeu = `duplicate`, aucune ligne ajoutée) ;
 *    - mise à jour d'une ligne existante (même ID) ;
 *    - opération `delete` ;
 *    - item invalide isolé (status `error`) sans casser le lot ;
 *    - garde-fou MAX_ITEMS + `retryable` ;
 *    - alimentation du journal `_Journal` ;
 *    - réinjection de l'ID si le client l'oublie dans `data`.
 *
 *  Usage :  node apps-script/test/webhook_test.mjs
 *  Sortie : code 0 si tout passe, 1 sinon (utilisable en CI).
 * ============================================================================
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import vm from 'node:vm';

class Range {
  constructor(sheet, row, col, numRows, numCols) {
    Object.assign(this, { sheet, row, col, numRows, numCols });
  }
  getValues() {
    const out = [];
    for (let r = 0; r < this.numRows; r++) {
      const line = [];
      for (let c = 0; c < this.numCols; c++) {
        const raw = (this.sheet.rows[this.row - 1 + r] || [])[this.col - 1 + c];
        line.push(raw === undefined ? '' : raw);
      }
      out.push(line);
    }
    return out;
  }
  setValues(values) {
    for (let r = 0; r < values.length; r++) {
      const target = this.row - 1 + r;
      while (this.sheet.rows.length <= target) this.sheet.rows.push([]);
      for (let c = 0; c < values[r].length; c++) {
        this.sheet.rows[target][this.col - 1 + c] = values[r][c];
      }
    }
    return this;
  }
  setValue(v) {
    return this.setValues([[v]]);
  }
  setFontWeight() { return this; }
  setFontSize() { return this; }
  setNumberFormat() { return this; }
  setBackground() { return this; }
  setFontColor() { return this; }
  setHorizontalAlignment() { return this; }
  setVerticalAlignment() { return this; }
}

class Sheet {
  constructor(name) {
    this.name = name;
    this.rows = [];
    this.frozen = 0;
    this.hidden = false;
  }
  getName() { return this.name; }
  getLastRow() {
    let last = 0;
    for (let r = 0; r < this.rows.length; r++) {
      const line = this.rows[r] || [];
      if (line.some((v) => v !== '' && v !== null && v !== undefined)) last = r + 1;
    }
    return last;
  }
  getMaxRows() { return Math.max(this.rows.length, 1000); }
  getMaxColumns() { return 26; }
  getRange(row, col, numRows = 1, numCols = 1) {
    return new Range(this, row, col, numRows, numCols);
  }
  appendRow(values) {
    this.rows.push([...values]);
  }
  deleteRow(row) {
    this.rows.splice(row - 1, 1);
  }
  deleteRows(row, count) {
    this.rows.splice(row - 1, count);
  }
  setFrozenRows(n) { this.frozen = n; }
  setColumnWidth() { return this; }
  hideSheet() { this.hidden = true; }
  showSheet() { this.hidden = false; }
  getDataRange() { return this.getRange(1, 1, Math.max(this.getLastRow(), 1), this.getMaxColumns()); }
}

class Spreadsheet {
  constructor() {
    this.sheets = [];
  }
  getSheetByName(name) {
    return this.sheets.find((s) => s.getName() === name) || null;
  }
  insertSheet(name) {
    const sheet = new Sheet(name || `Sheet${this.sheets.length + 1}`);
    this.sheets.push(sheet);
    return sheet;
  }
  getSheets() { return this.sheets; }
  getId() { return 'fake-sheet-id'; }
  getUrl() { return 'https://docs.google.com/spreadsheets/d/fake-sheet-id/edit'; }
}

const spreadsheet = new Spreadsheet();
const props = new Map();
const cache = new Map();
let lockHeld = false;
let lastOutput = null;

/** Faux Google `tokeninfo` : `validTokens` associe un jeton à son e-mail. */
const validTokens = new Map();
let tokenInfoCalls = 0;

function urlFetch(url) {
  const match = String(url).match(/id_token=([^&]+)/);
  const token = match ? decodeURIComponent(match[1]) : '';
  tokenInfoCalls += 1;
  const email = validTokens.get(token);
  if (!email) {
    return {
      getResponseCode: () => 400,
      getContentText: () => '{"error":"invalid_token"}',
    };
  }
  return {
    getResponseCode: () => 200,
    getContentText: () => JSON.stringify({ email: email, email_verified: 'true' }),
  };
}

const sandbox = {
  console,
  SpreadsheetApp: {
    getActiveSpreadsheet: () => spreadsheet,
    flush: () => {},
    getUi: () => {
      const err = new Error('No UI in harness');
      throw err;
    },
  },
  PropertiesService: {
    getScriptProperties: () => ({
      getProperty: (k) => (props.has(k) ? props.get(k) : null),
      setProperty: (k, v) => { props.set(k, v); },
      deleteProperty: (k) => { props.delete(k); },
      getProperties: () => Object.fromEntries(props),
      setProperties: (obj) => { Object.entries(obj).forEach(([k, v]) => props.set(k, v)); },
    }),
    getDocumentProperties: () => ({ getProperty: () => null, setProperty: () => {} }),
  },
  LockService: {
    getScriptLock: () => ({
      tryLock: () => { if (lockHeld) return false; lockHeld = true; return true; },
      waitLock: () => { lockHeld = true; },
      releaseLock: () => { lockHeld = false; },
      hasLock: () => lockHeld,
    }),
  },
  CacheService: {
    getScriptCache: () => ({
      get: (k) => (cache.has(k) ? cache.get(k) : null),
      put: (k, v) => { cache.set(k, v); },
      remove: (k) => { cache.delete(k); },
    }),
  },
  UrlFetchApp: {
    fetch: (url) => urlFetch(url),
  },
  ContentService: {
    MimeType: { JSON: 'application/json' },
    createTextOutput: (content) => ({
      content,
      mime: null,
      setMimeType(m) { this.mime = m; return this; },
      setContent(c) { this.content = c; return this; },
      getContent() { return this.content; },
    }),
  },
  Utilities: {
    DigestAlgorithm: { SHA_256: 'SHA_256' },
    computeDigest: (algorithm, value) => Array.from(
      crypto.createHash('sha256').update(String(value)).digest()
    ).map((byte) => (byte > 127 ? byte - 256 : byte)),
    getUuid: () => `uuid-${Math.random().toString(16).slice(2)}`,
    formatDate: (date, tz, fmt) => {
      const p = (n) => String(n).padStart(2, '0');
      return fmt
        .replace('yyyy', String(date.getFullYear()))
        .replace('MM', p(date.getMonth() + 1))
        .replace('dd', p(date.getDate()))
        .replace('HH', p(date.getHours()))
        .replace('mm', p(date.getMinutes()))
        .replace('ss', p(date.getSeconds()));
    },
  },
  Logger: { log: (...args) => console.log('[Logger]', ...args) },
  HtmlService: {
    createHtmlOutput: () => ({ setTitle() { return this; } }),
  },
};

const code = fs.readFileSync(new URL('../Code.gs', import.meta.url), 'utf8');
vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: 'Code.gs' });

// ---------------------------------------------------------------- helpers --
const H = { secrets: 'test-secret-123' };

function post(body, headers) {
  const res = sandbox.doPost({
    postData: { contents: JSON.stringify(body) },
    headers: headers || {},
  });
  return JSON.parse(res.content);
}

function postAs(token, body) {
  return post(body, { Authorization: 'Bearer ' + token });
}

function sheetRows(name) {
  const sheet = spreadsheet.getSheetByName(name);
  return sheet ? sheet.rows : [];
}

let failures = 0;
function check(label, condition, extra) {
  if (condition) {
    console.log(`  ok  ${label}`);
  } else {
    failures += 1;
    console.log(`  KO  ${label}`, extra === undefined ? '' : JSON.stringify(extra));
  }
}

// ------------------------------------------------------------------ tests --
console.log('1) Configuration');
props.set('SHARED_SECRET', H.secrets);

console.log('2) ping');
let r = post({ action: 'ping', secret: H.secrets, deviceId: 'dev-1' });
check('ping ok', r.ok === true, r);
check('ping renvoie serverTime', typeof r.serverTime === 'string', r.serverTime);

console.log('3) secret invalide');
r = post({ action: 'push', secret: 'mauvais', deviceId: 'dev-1', items: [] });
check('secret refusé', r.ok === false && /secret/i.test(r.message), r);

console.log('4) push présences');
const att = {
  id: 'att-0001',
  entity: 'attendance',
  sheet: 'Présences',
  operation: 'upsert',
  data: {
    id: 'att-0001',
    date: '2026-11-05',
    categorie: 'U16',
    joueur: 'Rakoto Jean',
    statut: 'Présent',
    auteur: 'Coach Naina',
    heure: '16:30',
    joueurId: 'p-1',
    sessionId: 's-1',
    numero: 7,
    note: '',
  },
};
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', batchId: 'b1', items: [att] });
check('push ok', r.ok === true, r);
check('1 résultat ok', Array.isArray(r.results) && r.results.length === 1 && r.results[0].status === 'ok', r.results);
check('ligne écrite', sheetRows('Présences').length === 2, sheetRows('Présences'));
const header = sheetRows('Présences')[0];
check('en-têtes conformes', header[0] === 'ID' && header[1] === 'Date' && header[6] === 'SyncTimestamp', header);
const row = sheetRows('Présences')[1];
check('ID en colonne 1', row[0] === 'att-0001', row[0]);
check('joueur en colonne 4', row[3] === 'Rakoto Jean', row);
check('SyncTimestamp rempli', !!row[6], row);

console.log('5) idempotence (même item renvoyé)');
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', batchId: 'b2', items: [att] });
check('duplicate reconnu', r.results[0].status === 'duplicate' || r.results[0].status === 'ok', r.results);
check('aucune ligne ajoutée', sheetRows('Présences').length === 2, sheetRows('Présences'));

console.log('6) mise à jour (même ID, statut modifié)');
const att2 = { ...att, data: { ...att.data, statut: 'En retard' } };
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', batchId: 'b3', items: [att2] });
check('statut mis à jour', sheetRows('Présences')[1][4] === 'En retard', sheetRows('Présences')[1]);
check('toujours 2 lignes', sheetRows('Présences').length === 2, sheetRows('Présences').length);

console.log('7) lot mixte + feuille inconnue');
const tx = {
  id: 'tx-0001',
  entity: 'transaction',
  sheet: 'Transactions',
  operation: 'upsert',
  data: {
    id: 'tx-0001',
    date: '2026-11-04',
    flux: 'Entrée',
    categorie: 'Écolage',
    montant: 50000,
    details: 'Écolage novembre — Rakoto Jean',
    auteur: 'Trésorier',
    modePaiement: 'MVola',
    joueur: 'Rakoto Jean',
    staff: '',
    evenement: '',
    mois: '2026-11',
  },
};
const bad = { id: 'x-1', entity: 'inconnu', sheet: 'FeuilleInconnue', operation: 'upsert', data: {} };
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', batchId: 'b4', items: [tx, bad] });
check('2 résultats', r.results.length === 2, r.results);
check('transaction ok', r.results[0].status === 'ok', r.results[0]);
check('feuille inconnue en erreur', r.results[1].status === 'error', r.results[1]);
const txRow = sheetRows('Transactions')[1];
check('montant numérique', txRow[4] === 50000, txRow);
check('mode de paiement', txRow[8] === 'MVola', txRow);

console.log('8) suppression logique');
const del = { ...tx, operation: 'delete', data: { date: '2026-11-04' } };
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', batchId: 'b5', items: [del] });
check('delete ok', r.results[0].status === 'ok', r.results[0]);

console.log('9) lot trop gros');
const many = Array.from({ length: 3 }, (_, i) => ({ ...att, id: `att-1${i}00` }));
const huge = Array.from({ length: 201 }, (_, i) => ({ ...att, id: 'big-' + i }));
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', items: huge });
check('lot refusé', r.ok === false && /trop volumineux/i.test(r.message), r);
check('retryable signalé', r.retryable === true, r);
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', items: many });
check('petit lot accepté', r.ok === true, r);

console.log('10) journal');
const journal = sheetRows('_Journal');
check('journal alimenté', journal.length > 3, journal.length);
const jHead = journal[0];
check('en-têtes journal', jHead[0] === 'Reçu le' && jHead[2] === 'Lot', jHead);
const jLast = journal[journal.length - 1];
check('statut journal OK', jLast[7] === 'OK' || jLast[7] === 'PARTIEL', jLast);

console.log('11) réinjection de l\'ID (client ancien sans data.id)');
const legacy = { ...att, id: 'legacy-1', data: { ...att.data } };
delete legacy.data.id;
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', items: [legacy] });
const legacyRow = sheetRows('Présences').find((line) => line[0] === 'legacy-1');
check('ID écrit malgré data.id absent', !!legacyRow, sheetRows('Présences').slice(-2));

console.log('12) doGet');
const get = JSON.parse(sandbox.doGet({ parameter: { secret: H.secrets } }).content);
check('doGet ok', get.ok === true, get);

console.log('13) joueur avec date de naissance');
const player = {
  id: 'p-0001',
  entity: 'player',
  sheet: 'Joueurs',
  operation: 'upsert',
  data: {
    id: 'p-0001',
    nom: 'Rakoto Jean',
    categorie: 'U16',
    dateNaissance: '2010-04-17',
    numero: 7,
    telephone: '0340000000',
    actif: true,
  },
};
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', batchId: 'b6', items: [player] });
check('joueur ok', r.ok === true && r.results[0].status === 'ok', r.results);
const playerHeader = sheetRows('Joueurs')[0];
check(
  'en-tête date de naissance',
  playerHeader[3] === 'Date de naissance',
  playerHeader,
);
const playerRow = sheetRows('Joueurs')[1];
check('date de naissance écrite', playerRow[3] === '2010-04-17', playerRow);
check('numéro après la date', playerRow[4] === 7, playerRow);

console.log('14) joueur sans date de naissance (fiche ancienne)');
const playerNoBirth = {
  ...player,
  id: 'p-0002',
  data: { ...player.data, id: 'p-0002', dateNaissance: null },
};
r = post({ action: 'push', secret: H.secrets, deviceId: 'dev-1', batchId: 'b7', items: [playerNoBirth] });
const noBirthRow = sheetRows('Joueurs').find((line) => line[0] === 'p-0002');
check('ligne écrite sans date', !!noBirthRow, sheetRows('Joueurs'));
check('cellule date vide', noBirthRow[3] === '', noBirthRow);

console.log('15) identité Google (aucun secret à saisir)');
validTokens.set('jeton-coach', 'coach@dtnh.mg');
props.set('ALLOWED_EMAILS', 'coach@dtnh.mg, tresorier@dtnh.mg');

r = postAs('jeton-coach', { action: 'ping' });
check('ping par identité Google', r.ok === true && r.identity === 'google', r);
check('email renvoyé', r.email === 'coach@dtnh.mg', r.email);

// Un lot sans `secret` mais avec un jeton Google valide doit passer.
const googleAtt = { ...att, id: 'att-google-1', data: { ...att.data, id: 'att-google-1' } };
r = postAs('jeton-coach', {
  action: 'push',
  deviceId: 'dev-google',
  batchId: 'b-google',
  items: [googleAtt],
});
check('push sans secret via Google', r.ok === true && r.results[0].status === 'ok', r);
check(
  'ligne écrite',
  !!sheetRows('Présences').find((line) => line[0] === 'att-google-1'),
  sheetRows('Présences').slice(-2),
);

// Jeton inconnu : refus explicite (pas de repli silencieux sur le secret).
r = postAs('jeton-inconnu', { action: 'push', secret: H.secrets, items: [att] });
check('jeton invalide refusé', r.ok === false && /invalide|expiré/i.test(r.message), r);

// Compte Google valide mais hors liste d'accès.
validTokens.set('jeton-intrus', 'inconnu@gmail.com');
r = postAs('jeton-intrus', { action: 'ping' });
check('compte non autorisé refusé', r.ok === false && /autoris/i.test(r.message), r);

// Le cache évite un appel `tokeninfo` par requête.
const callsBefore = tokenInfoCalls;
r = postAs('jeton-coach', { action: 'ping' });
check(
  'jeton déjà vérifié mis en cache',
  r.ok === true && tokenInfoCalls === callsBefore,
  { tokenInfoCalls, callsBefore },
);

// Sans liste d'accès, un compte Google vérifié est accepté (rétro-compatible).
props.delete('ALLOWED_EMAILS');
validTokens.set('jeton-coach2', 'autre@dtnh.mg');
r = postAs('jeton-coach2', { action: 'ping' });
check('sans ALLOWED_EMAILS, Google suffit', r.ok === true && r.identity === 'google', r);

// Le secret partagé reste un chemin valide (appareils non connectés).
r = post({ action: 'ping', secret: H.secrets });
check('secret historique toujours accepté', r.ok === true && r.identity === 'secret', r);

console.log('16) publication de la configuration (action config côté Supabase)');
sandbox.ScriptApp = { getService: () => ({ getUrl: () => 'https://script.google.com/macros/s/FAKE/exec' }) };
const publishedSecret = sandbox.setup();
const published = JSON.parse(props.get('CLUB_CONFIG'));
check('setup publie la configuration', !!published && published.sheetId === 'fake-sheet-id', published);
check('URL /exec publiée', /\/exec$/.test(published.webhookUrl), published.webhookUrl);
check('secret cohérent avec setup()', published.webhookSecret === publishedSecret, publishedSecret);

console.log('');
console.log(failures === 0 ? 'TOUS LES TESTS PASSENT' : `${failures} ÉCHEC(S)`);
process.exit(failures === 0 ? 0 : 1);
