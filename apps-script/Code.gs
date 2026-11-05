/**
 * ============================================================================
 *  DTNH Assistant Club — Webhook Google Apps Script
 * ============================================================================
 *  Reçoit les lots JSON envoyés par l'application Flutter et les insère dans
 *  le Google Sheet du club (upsert idempotent par ID).
 *
 *  Déploiement :
 *    1. Ouvrir le Google Sheet cible > Extensions > Apps Script.
 *    2. Coller ce fichier (remplacer le contenu de Code.gs).
 *    3. Exécuter la fonction `setup` une fois (autoriser les accès) :
 *       elle crée les onglets, les en-têtes et génère le SHARED_SECRET.
 *    4. Déployer > Nouveau déploiement > Application web
 *         - Exécuter en tant que : Moi
 *         - Qui a accès : Tout le monde
 *       puis copier l'URL qui finit par /exec.
 *    5. Dans l'app : Réglages > Webhook (URL + secret) puis « Tester ».
 *
 *  Contrat d'API :
 *    POST { action: 'ping' | 'push', secret, deviceId, batchId, items: [...] }
 *    item  = { id, entity, sheet, operation: 'upsert'|'delete', data: {...} }
 *    réponse = { ok, message, serverTime, results: [{ id, sheet, status }] }
 * ============================================================================
 */

/** Nom de la propriété de script qui contient le secret partagé. */
const SECRET_PROPERTY = 'SHARED_SECRET';

/** Onglet de journalisation technique (ne pas renommer). */
const JOURNAL_SHEET = '_Journal';

/** Garde-fou anti-abus : taille maximale d'un lot. */
const MAX_ITEMS = 200;

/** Durée max de verrouillage (ms) : évite deux écritures concurrentes. */
const LOCK_TIMEOUT_MS = 25000;

/**
 * Schéma de chaque onglet : l'ordre des `columns` définit les colonnes du Sheet,
 * `fields` donne la clé JSON correspondante (null = valeur générée par le
 * serveur, ici le SyncTimestamp).
 *
 * Les 7 premières colonnes de « Présences » et les 8 premières de
 * « Transactions » respectent exactement la structure demandée ; les colonnes
 * supplémentaires apportent la traçabilité (heure, IDs techniques, mode de
 * paiement, mois concerné...).
 */
const SCHEMAS = {
  'Présences': {
    columns: [
      'ID', 'Date', 'Catégorie', 'Joueur', 'Statut', 'Auteur', 'SyncTimestamp',
      'Heure', 'JoueurID', 'SessionID', 'Numéro', 'Note',
    ],
    fields: [
      'id', 'date', 'categorie', 'joueur', 'statut', 'auteur', null,
      'heure', 'joueurId', 'sessionId', 'numero', 'note',
    ],
  },
  'Transactions': {
    columns: [
      'ID', 'Date', 'Flux', 'Catégorie', 'Montant', 'Détails', 'Auteur',
      'SyncTimestamp', 'Mode de paiement', 'Joueur', 'Staff', 'Événement',
      'Mois',
    ],
    fields: [
      'id', 'date', 'flux', 'categorie', 'montant', 'details', 'auteur',
      null, 'modePaiement', 'joueur', 'staff', 'evenement', 'mois',
    ],
  },
  'Joueurs': {
    columns: [
      'ID', 'Nom', 'Catégorie', 'Numéro', 'Téléphone', 'Actif', 'SyncTimestamp',
    ],
    fields: ['id', 'nom', 'categorie', 'numero', 'telephone', 'actif', null],
  },
};

/** Correspondance `entity` (client) -> onglet du Sheet. */
const ENTITY_SHEETS = {
  attendance: 'Présences',
  transaction: 'Transactions',
  player: 'Joueurs',
};

// ---------------------------------------------------------------------------
//  Entrées HTTP
// ---------------------------------------------------------------------------

/**
 * GET : test de vie depuis un navigateur.
 * Exemple : .../exec?secret=XXXX&action=ping
 */
function doGet(e) {
  const expected = PropertiesService.getScriptProperties()
    .getProperty(SECRET_PROPERTY);
  const params = (e && e.parameter) || {};

  if (params.secret && expected && String(params.secret) === expected) {
    return json_({
      ok: true,
      message: 'DTNH webhook actif',
      sheets: Object.keys(SCHEMAS),
      serverTime: new Date().toISOString(),
    });
  }

  return json_({
    ok: false,
    message: 'DTNH webhook. Utilisez une requête POST signée (secret requis).',
    serverTime: new Date().toISOString(),
  });
}

/** Réception des lots de synchronisation. */
function doPost(e) {
  const receivedAt = new Date();
  let payload;

  try {
    payload = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (error) {
    return json_({ ok: false, message: 'Corps JSON invalide : ' + error });
  }

  const expected = PropertiesService.getScriptProperties()
    .getProperty(SECRET_PROPERTY);
  if (!expected) {
    return json_({
      ok: false,
      message:
        'SHARED_SECRET absent : exécutez la fonction setup() dans Apps Script.',
    });
  }
  if (String(payload.secret || '') !== expected) {
    journal_(payload, 0, 0, 0, 'REFUSÉ (secret invalide)', receivedAt);
    return json_({ ok: false, message: 'Secret invalide.' });
  }

  const action = String(payload.action || 'push');
  if (action === 'ping') {
    return json_({
      ok: true,
      message: 'DTNH webhook actif',
      serverTime: new Date().toISOString(),
    });
  }
  if (action !== 'push') {
    return json_({ ok: false, message: 'Action inconnue : ' + action });
  }

  const items = payload.items;
  if (!Array.isArray(items) || items.length === 0) {
    return json_({ ok: false, message: 'Aucun élément à traiter.' });
  }
  if (items.length > MAX_ITEMS) {
    return json_({
      ok: false,
      message: 'Lot trop volumineux (max ' + MAX_ITEMS + ' éléments).',
      retryable: true,
    });
  }

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) {
    // 409-like : le client réessaiera avec un backoff.
    return json_({
      ok: false,
      message: 'Serveur occupé (verrou actif), réessayez dans un instant.',
      retryable: true,
    });
  }

  try {
    const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    const results = [];
    const states = {};

    for (let i = 0; i < items.length; i++) {
      const item = items[i] || {};
      const sheetName = resolveSheetName_(item);

      if (!sheetName) {
        results.push({
          id: String(item.id || ''),
          sheet: String(item.sheet || ''),
          status: 'error',
          error: 'Onglet cible inconnu (entity/sheet).',
        });
        continue;
      }

      const id = String((item.data && item.data.id) || item.id || '').trim();
      if (!id) {
        results.push({
          id: String(item.id || ''),
          sheet: sheetName,
          status: 'error',
          error: 'ID manquant : la ligne ne peut pas être idempotente.',
        });
        continue;
      }

      try {
        const state = getSheetState_(spreadsheet, sheetName, states);
        const operation = String(item.operation || 'upsert').toLowerCase();

        if (operation === 'delete') {
          state.deletes.push(id);
          results.push({ id: id, sheet: sheetName, status: 'ok' });
          continue;
        }

        // L'ID doit toujours atterrir en colonne 1 : c'est la clé
        // d'idempotence. Si le client l'a omis dans `data`, on le réinjecte
        // depuis l'item (sinon la déduplication serait silencieusement cassée).
        const data = Object.assign({}, item.data || {});
        if (!data.id) data.id = id;

        const values = buildRow_(state.schema, data, receivedAt);
        const existingRow = state.index[id];

        if (existingRow) {
          state.updates.push({ row: existingRow, values: values });
          results.push({ id: id, sheet: sheetName, status: 'duplicate' });
        } else {
          state.appends.push(values);
          // Anti-doublon intra-lot : on réserve la ligne virtuellement.
          state.index[id] = -1 * (state.appends.length);
          results.push({ id: id, sheet: sheetName, status: 'ok' });
        }
      } catch (itemError) {
        results.push({
          id: id,
          sheet: sheetName,
          status: 'error',
          error: String(itemError),
        });
      }
    }

    // Écriture par onglet, en un minimum d'appels (quotas Apps Script).
    Object.keys(states).forEach(function (name) {
      flushState_(states[name]);
    });

    const okCount = results.filter(function (r) {
      return r.status === 'ok' || r.status === 'duplicate';
    }).length;
    const errorCount = results.length - okCount;

    journal_(
      payload,
      items.length,
      okCount,
      errorCount,
      errorCount > 0 ? 'PARTIEL' : 'OK',
      receivedAt
    );

    return json_({
      ok: errorCount === 0,
      message:
        errorCount === 0
          ? okCount + ' ligne(s) enregistrée(s).'
          : okCount + ' ligne(s) OK, ' + errorCount + ' en erreur.',
      serverTime: new Date().toISOString(),
      results: results,
    });
  } catch (error) {
    journal_(payload, 0, 0, 0, 'ERREUR: ' + error, receivedAt);
    return json_({
      ok: false,
      message: 'Erreur serveur : ' + error,
      retryable: true,
    });
  } finally {
    lock.releaseLock();
  }
}

// ---------------------------------------------------------------------------
//  Installation / maintenance
// ---------------------------------------------------------------------------

/**
 * À exécuter UNE FOIS depuis l'éditeur Apps Script.
 * Crée les onglets, les en-têtes, le journal et génère le secret partagé.
 */
function setup() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();

  Object.keys(SCHEMAS).forEach(function (name) {
    const schema = SCHEMAS[name];
    const sheet =
      spreadsheet.getSheetByName(name) ||
      spreadsheet.insertSheet(name);
    ensureHeaders_(sheet, schema.columns);
    styleSheet_(sheet, schema.columns.length);
  });

  ensureJournal_(spreadsheet);

  const properties = PropertiesService.getScriptProperties();
  let secret = properties.getProperty(SECRET_PROPERTY);
  if (!secret) {
    secret = Utilities.getUuid().replace(/-/g, '').substring(0, 24);
    properties.setProperty(SECRET_PROPERTY, secret);
  }

  const message =
    'Configuration terminée.\n\nSecret partagé :\n' +
    secret +
    '\n\nÀ recopier dans l\'application : Réglages > Webhook Google Apps Script.';

  try {
    SpreadsheetApp.getUi().alert(message);
  } catch (error) {
    Logger.log(message);
  }
  return secret;
}

/** Menu pratique dans le Sheet. */
function onOpen() {
  try {
    SpreadsheetApp.getUi()
      .createMenu('DTNH')
      .addItem('Initialiser les onglets', 'setup')
      .addItem('Afficher le secret', 'showSecret')
      .addItem('Purger le journal', 'clearJournal')
      .addToUi();
  } catch (error) {
    // `onOpen` peut échouer en contexte sans UI : on ignore.
  }
}

function showSecret() {
  const secret = PropertiesService.getScriptProperties()
    .getProperty(SECRET_PROPERTY);
  SpreadsheetApp.getUi().alert(
    secret
      ? 'Secret partagé :\n' + secret
      : 'Aucun secret : exécutez d\'abord setup().'
  );
}

function clearJournal() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(JOURNAL_SHEET);
  if (!sheet) return;
  const lastRow = sheet.getLastRow();
  if (lastRow > 1) sheet.deleteRows(2, lastRow - 1);
}

// ---------------------------------------------------------------------------
//  Helpers internes
// ---------------------------------------------------------------------------

function json_(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

function resolveSheetName_(item) {
  if (item.sheet && SCHEMAS[item.sheet]) return item.sheet;
  const byEntity = ENTITY_SHEETS[String(item.entity || '')];
  if (byEntity && SCHEMAS[byEntity]) return byEntity;
  return null;
}

/** État (en-têtes, index id->ligne, tampons d'écriture) d'un onglet. */
function getSheetState_(spreadsheet, sheetName, cache) {
  if (cache[sheetName]) return cache[sheetName];

  const schema = SCHEMAS[sheetName];
  const sheet =
    spreadsheet.getSheetByName(sheetName) ||
    spreadsheet.insertSheet(sheetName);

  ensureHeaders_(sheet, schema.columns);

  const index = {};
  const lastRow = sheet.getLastRow();
  if (lastRow > 1) {
    const ids = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
    for (let i = 0; i < ids.length; i++) {
      const value = String(ids[i][0]).trim();
      if (value) index[value] = i + 2;
    }
  }

  cache[sheetName] = {
    sheet: sheet,
    schema: schema,
    index: index,
    appends: [],
    updates: [],
    deletes: [],
    lastRow: lastRow,
  };
  return cache[sheetName];
}

/** Construit une ligne complète dans l'ordre des colonnes du schéma. */
function buildRow_(schema, data, receivedAt) {
  const timestamp = receivedAt.toISOString();
  return schema.fields.map(function (field) {
    if (field === null) return timestamp;
    return coerce_(data[field]);
  });
}

function coerce_(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value;
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

/** Applique les mises à jour, ajouts et suppressions d'un onglet. */
function flushState_(state) {
  const sheet = state.sheet;

  // 1. Mises à jour ligne par ligne (upsert idempotent).
  state.updates.forEach(function (update) {
    sheet
      .getRange(update.row, 1, 1, update.values.length)
      .setValues([update.values]);
  });

  // 2. Ajouts en un seul bloc (le plus gros gain de performance).
  let nextRow = Math.max(state.lastRow, sheet.getLastRow());
  if (state.appends.length > 0) {
    sheet
      .getRange(nextRow + 1, 1, state.appends.length, state.appends[0].length)
      .setValues(state.appends);
  }

  // 3. Suppressions (opération `delete`), du bas vers le haut.
  if (state.deletes.length > 0) {
    const rows = [];
    state.deletes.forEach(function (id) {
      if (state.index[id] > 0) rows.push(state.index[id]);
    });
    rows.sort(function (a, b) {
      return b - a;
    });
    rows.forEach(function (row) {
      sheet.deleteRow(row);
    });
  }

  SpreadsheetApp.flush();
}

function ensureHeaders_(sheet, columns) {
  const range = sheet.getRange(1, 1, 1, columns.length);
  const current = range.getValues()[0];
  let needsWrite = false;
  for (let i = 0; i < columns.length; i++) {
    if (String(current[i] || '') !== columns[i]) {
      needsWrite = true;
      break;
    }
  }
  if (!needsWrite) return;
  range.setValues([columns]);
  sheet.getRange(1, 1, 1, columns.length).setFontWeight('bold');
}

function styleSheet_(sheet, columnCount) {
  const header = sheet.getRange(1, 1, 1, columnCount);
  header
    .setBackground('#0F172A')
    .setFontColor('#FFFFFF')
    .setFontWeight('bold')
    .setVerticalAlignment('middle');
  sheet.setFrozenRows(1);

  const widths = [];
  for (let i = 0; i < columnCount; i++) {
    widths.push(i === 0 ? 260 : 130);
  }
  for (let i = 0; i < widths.length; i++) {
    sheet.setColumnWidth(i + 1, widths[i]);
  }

  const maxRows = sheet.getMaxRows();
  if (maxRows > 1) {
    sheet.getRange(2, 1, maxRows - 1, columnCount).setFontSize(10);
  }
}

function ensureJournal_(spreadsheet) {
  let sheet = spreadsheet.getSheetByName(JOURNAL_SHEET);
  if (!sheet) {
    sheet = spreadsheet.insertSheet(JOURNAL_SHEET);
  }
  const headers = [
    'Reçu le',
    'Appareil',
    'Lot',
    'Action',
    'Éléments',
    'OK',
    'Erreurs',
    'Statut',
  ];
  const range = sheet.getRange(1, 1, 1, headers.length);
  range.setValues([headers]);
  range.setFontWeight('bold').setBackground('#334155').setFontColor('#FFFFFF');
  sheet.setFrozenRows(1);
  sheet.hideSheet();
  return sheet;
}

/** Journalisation best-effort : ne doit jamais faire échouer une requête. */
function journal_(payload, total, ok, errors, status, receivedAt) {
  try {
    const sheet = ensureJournal_(SpreadsheetApp.getActiveSpreadsheet());
    sheet.appendRow([
      receivedAt ? receivedAt.toISOString() : new Date().toISOString(),
      String((payload && payload.deviceId) || '—'),
      String((payload && payload.batchId) || '—'),
      String((payload && payload.action) || 'push'),
      total,
      ok,
      errors,
      status,
    ]);
  } catch (error) {
    Logger.log('Journal indisponible : ' + error);
  }
}
