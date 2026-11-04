import { readFileSync } from 'node:fs';
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

// Un seul endroit pour les trois planchers de couverture — Go, web, iOS —
// pour que les relever soit une seule modification, et que la raison de leur
// existence ne soit écrite qu'une fois.
const planchers = JSON.parse(
  readFileSync(new URL('../.github/couverture-planchers.json', import.meta.url), 'utf8'),
);

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    include: ['**/*.{test,spec}.{ts,tsx}'],
    exclude: ['node_modules', '.next'],

    // `all: true`, et c'est tout l'enjeu de ce bloc. (#725)
    //
    // Par défaut v8 ne compte que les fichiers que les tests CHARGENT. Les
    // 140 fichiers qu'aucun test n'importe disparaissent du dénominateur, et
    // le rapport annonçait **91,64 %** pour une couverture réelle de
    // **30,76 %** — mesuré le 2026-11-03. Un chiffre faux dans ce sens-là est
    // pire que pas de chiffre : il dit que le travail est fait.
    //
    // Le seuil est un CLIQUET, pas un objectif : il échoue si la couverture
    // DESCEND, jamais parce qu'elle n'atteint pas un chiffre choisi d'avance.
    // Le plancher vit dans `.github/couverture-planchers.json`, avec les deux
    // autres zones et la raison. (#725 point 9)
    coverage: {
      provider: 'v8',
      all: true,
      reporter: ['text-summary', 'json-summary', 'lcov'],
      // Le code applicatif, et lui seul. Les fichiers de configuration, les
      // types et les tests eux-mêmes gonfleraient le dénominateur sans rien
      // dire de ce qui est éprouvé.
      include: ['app/**/*.{ts,tsx}', 'lib/**/*.{ts,tsx}',
                'components/**/*.{ts,tsx}', 'middleware.ts'],
      exclude: ['**/*.test.{ts,tsx}', '**/*.spec.{ts,tsx}',
                '**/*.d.ts', 'app/**/layout.tsx'],
      // Seules les INSTRUCTIONS portent un plancher. Branches et fonctions
      // sont affichées mais pas gardées : elles bougent pour des raisons qui
      // ne disent rien de l'effort de test — un `if` ajouté dans un fichier
      // déjà couvert fait baisser le taux de branches sans qu'aucun test
      // n'ait disparu.
      thresholds: { statements: planchers.web.plancher },
    },
  },
});
