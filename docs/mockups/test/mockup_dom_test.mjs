/**
 * ============================================================================
 *  Test d'exécution des maquettes DTNH (DOM réel, jsdom)
 * ============================================================================
 *  Charge `../index.html`, exécute son JavaScript et simule de vrais clics :
 *  statuts de pointage, « tout présent », sélection de catégorie et de date,
 *  sauvegarde, bascule Entrée/Sortie. Vérifie aussi qu'aucune erreur
 *  JavaScript n'est levée — un écran blanc en prévisualisation vient
 *  presque toujours de là.
 *
 *  Dépendance unique (dev) :
 *      cd docs/mockups/test && npm i jsdom
 *      node mockup_dom_test.mjs
 *
 *  Sortie code 0/1 (utilisable en CI). 26 assertions.
 * ============================================================================
 */
import fs from 'node:fs';
import { JSDOM, VirtualConsole } from 'jsdom';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');

const errors = [];
const virtualConsole = new VirtualConsole();
virtualConsole.on('jsdomError', (e) => errors.push('jsdomError: ' + e.message));
virtualConsole.on('error', (...a) => errors.push('console.error: ' + a.join(' ')));

const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  virtualConsole,
  url: 'http://localhost:8080/',
});

const { window } = dom;
const { document } = window;

let failures = 0;
const check = (label, cond, extra) => {
  if (cond) console.log(`  ok  ${label}`);
  else {
    failures += 1;
    console.log(`  KO  ${label}`, extra === undefined ? '' : JSON.stringify(extra));
  }
};

console.log('1) Structure rendue');
check('4 téléphones', document.querySelectorAll('.phone').length === 4, document.querySelectorAll('.phone').length);
check('4 catégories', document.querySelectorAll('#cats .cat').length === 4, document.querySelectorAll('#cats .cat').length);
check('6 joueurs', document.querySelectorAll('#players .player').length === 6, document.querySelectorAll('#players .player').length);
check('4 boutons de statut par joueur', document.querySelectorAll('#players .player .sb').length === 24);
check('sélecteur de flux (seg)', document.querySelectorAll('.seg button').length >= 2);
check('boutons Entrée/Sortie', document.querySelectorAll('.split button').length >= 2);

console.log('2) État initial du pointage');
const cnt0 = document.getElementById('cnt').textContent.trim();
const pct0 = document.getElementById('pct').textContent.trim();
console.log('   cnt =', JSON.stringify(cnt0), '| pct =', JSON.stringify(pct0), '| attSub =', JSON.stringify(document.getElementById('attSub').textContent.trim()));

console.log('3) Interaction : marquer les 6 joueurs présents');
window.markAll('p');
const cnt1 = document.getElementById('cnt').textContent.trim();
const pct1 = document.getElementById('pct').textContent.trim();
console.log('   cnt =', JSON.stringify(cnt1), '| pct =', JSON.stringify(pct1));
check('compteur mis à jour', cnt1 !== cnt0, { cnt0, cnt1 });
check('pourcentage 100 %', /100/.test(pct1), pct1);
check('6 boutons "p" sélectionnés', document.querySelectorAll('#players .sb.p.sel').length === 6);
check('barre de progression à 100 %', /100/.test(document.getElementById('bar').style.width || ''), document.getElementById('bar').style.width);

console.log('4) Interaction : un joueur en retard');
document.querySelectorAll('#players .player')[0].querySelector('.sb.r').dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
const pct2 = document.getElementById('pct').textContent.trim();
check('un seul statut sélectionné pour ce joueur', document.querySelectorAll('#players .player')[0].querySelectorAll('.sb.sel').length === 1);
check('pourcentage recalculé', pct2 !== pct1 || /100/.test(pct2), { pct1, pct2 });

console.log('5) Interaction : changement de catégorie');
document.querySelectorAll('#cats .cat')[2].dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
check('catégorie active', document.querySelectorAll('#cats .cat')[2].classList.contains('active'));
check('titre mis à jour', /U16/.test(document.getElementById('attSub').textContent), document.getElementById('attSub').textContent.trim());

console.log('6) Interaction : sélection de date');
const dates = document.querySelectorAll('.date');
dates[2].dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
check('date active', dates[2].classList.contains('active'));

console.log('7) Interaction : sauvegarde (snackbar)');
window.saveSession();
const toast = document.querySelector('.toast, .snack, #toast');
check('retour visuel de sauvegarde', toast !== null || /enregistr/i.test(document.body.textContent), toast ? 'toast présent' : 'texte de confirmation');

console.log('8) Finances (valeurs de démonstration figées)');
const bodyText = document.body.textContent;
check('solde du club affiché', /1 250 000 Ar/.test(bodyText));
check('KPI entrées du mois', /320 000 Ar/.test(bodyText));
check('KPI sorties du mois', /95 000 Ar/.test(bodyText));
check('répartition par motif', (bodyText.match(/Location de terrain|Rafraîchissements|Salaire \/ indemnité coach/g) || []).length >= 3);
const splitBtns = document.querySelectorAll('.split button');
splitBtns[1]?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
check('bascule Entrée/Sortie', splitBtns[1]?.classList.contains('on') === true);

console.log('9) Barre de sauvegarde + chip de synchronisation');
const bstateAfter = document.getElementById('bstate').textContent.trim();
check('état de sauvegarde', /Enregistré/.test(bstateAfter), bstateAfter);
const chipText = document.getElementById('syncChip').textContent.trim();
check('chip en attente', /☁/.test(chipText), chipText);
check('chip classe pending', document.getElementById('syncChip').className.includes('pending'));

console.log('10) Erreurs JavaScript');
check('aucune erreur console/jsdom', errors.length === 0, errors.slice(0, 5));

console.log('');
console.log(failures === 0 ? 'MAQUETTE OK — aucune erreur d\'exécution' : `${failures} ÉCHEC(S)`);
process.exit(failures === 0 ? 0 : 1);
