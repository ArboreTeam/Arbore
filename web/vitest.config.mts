import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

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
    // Aucun seuil n'est posé. On veut d'abord VOIR le chiffre bouger à chaque
    // PR ; un seuil choisi sur une mesure qu'on vient de découvrir serait
    // arbitraire, et un seuil placé trop haut ferait rouge toute la CI dès ce
    // commit.
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
    },
  },
});
