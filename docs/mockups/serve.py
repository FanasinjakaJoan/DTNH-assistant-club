#!/usr/bin/env python3
"""Serveur statique minimal pour les maquettes DTNH.

Sert `index.html` (et les fichiers voisins) sur le port 8080, en écoutant sur
toutes les interfaces pour fonctionner derrière un proxy de prévisualisation.

   python3 docs/mockups/serve.py           # http://localhost:8080
   python3 docs/mockups/serve.py 9000      # autre port

Différences volontaires avec `python3 -m http.server` :

- `Cache-Control: no-store` : une maquette modifiée s'affiche immédiatement
  après un simple rafraîchissement (pas de version fantôme dans le navigateur) ;
- `HTTP/1.1` + `ThreadingHTTPServer` : le navigateur ouvre plusieurs
  connexions en parallèle (iframe de prévisualisation) sans blocage ;
- aucune dépendance : uniquement la bibliothèque standard.
"""

from __future__ import annotations

import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_PORT = 8080
ROOT = os.path.dirname(os.path.abspath(__file__))


class NoCacheHandler(SimpleHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self) -> None:
        self.send_header('Cache-Control', 'no-store, max-age=0')
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write('%s - %s\n' % (self.address_string(), fmt % args))


def main() -> int:
    port = DEFAULT_PORT
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f'Port invalide : {sys.argv[1]}', file=sys.stderr)
            return 2

    server = ThreadingHTTPServer(('0.0.0.0', port), NoCacheHandler)
    print(f'Maquettes DTNH servies depuis {ROOT}')
    print(f'  local   : http://127.0.0.1:{port}/')
    print(f'  réseau  : http://0.0.0.0:{port}/ (proxy / prévisualisation)')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nArrêt.')
    finally:
        server.server_close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
