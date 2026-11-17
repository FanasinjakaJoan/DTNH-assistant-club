/**
 * Assertions minimales pour les tests de l'Edge Function.
 *
 * Pourquoi pas `jsr:@std/assert` ? Le sandbox d'exécution de l'agent n'a accès
 * qu'à un nombre restreint de domaines (GitHub, npm, PyPI) : `jsr.io` n'est pas
 * joignable, donc `deno test` échouait au téléchargement du manifeste. En CI
 * (GitHub Actions) le réseau est ouvert, mais un test ne doit pas dépendre
 * d'un CDN pour vérifier de la logique pure. Ces fonctions couvrent les
 * assertions utilisées par `index_test.ts` et gardent la même signature que
 * `@std/assert`.
 */

export class AssertionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AssertionError";
  }
}

function describe(value: unknown): string {
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
}

export function assert(condition: unknown, message = "Assertion échouée"): void {
  if (!condition) throw new AssertionError(message);
}

export function assertEquals(actual: unknown, expected: unknown, msg?: string): void {
  const same = JSON.stringify(actual) === JSON.stringify(expected);
  if (!same) {
    throw new AssertionError(
      msg ?? `Attendu ${describe(expected)}, obtenu ${describe(actual)}`,
    );
  }
}

export function assertExists(value: unknown, msg?: string): void {
  if (value === null || value === undefined) {
    throw new AssertionError(msg ?? "Valeur absente");
  }
}

export function assertNotEquals(actual: unknown, expected: unknown, msg?: string): void {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    throw new AssertionError(msg ?? `Valeur inattendue ${describe(actual)}`);
  }
}
