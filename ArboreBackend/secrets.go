package main

import (
	"os"
	"strings"
)

// secretFromFileOrEnv lit un secret depuis un fichier monté quand c'est
// possible, et retombe sur la variable d'environnement sinon. (audit #338,
// constat 4)
//
// Pour un secret nommé `X`, la source préférée est le chemin donné par
// `X_PATH`. Sans lui, la valeur est lue dans `X`.
//
// # Pourquoi le fichier est préféré
//
// Une variable d'environnement est lisible par `docker inspect` et dans
// `/proc/<pid>/environ` : quiconque peut interroger le démon Docker lit tous les
// secrets du conteneur, sans y entrer. Un fichier monté en lecture seule
// n'apparaît dans aucun des deux.
//
// Le raisonnement vient de la clé Apple `.p8`, montée en fichier depuis
// l'origine, puis appliqué à la clé maître (`MASTER_ENCRYPTION_KEY_PATH`) —
// laquelle déchiffre les refresh tokens Apple et était donc moins bien protégée
// que ce qu'elle protège. Cette fonction étend le même traitement aux secrets
// restants.
//
// # Pourquoi le repli sur l'environnement subsiste
//
// Pour que la bascule soit progressive et réversible, machine par machine. Une
// installation qui n'a pas encore de fichier monté doit continuer de démarrer,
// pas échouer — c'est la même règle que pour le déchiffrement SOPS au
// déploiement, où l'absence de clé privée laisse la configuration en place.
//
// # Ce que cette fonction ne fait pas
//
// Elle ne valide pas le contenu et ne distingue pas un fichier absent d'un
// fichier vide : l'appelant garde la responsabilité de juger ce qu'il a reçu,
// parce que « vide » ne veut pas dire la même chose pour une clé d'API que pour
// une URI de base de données.
func secretFromFileOrEnv(name string) string {
	if path := strings.TrimSpace(os.Getenv(name + "_PATH")); path != "" {
		// nolint:gosec // G304 : chemin fourni par l'opérateur via une variable
		// d'environnement de confiance, jamais par un utilisateur.
		if raw, err := os.ReadFile(path); err == nil {
			if v := strings.TrimSpace(string(raw)); v != "" {
				return v
			}
		}
		// Un fichier illisible ou vide ne doit pas masquer une variable
		// correctement posée : on retombe, plutôt que de refuser de démarrer
		// pour une erreur de montage.
	}
	return strings.TrimSpace(os.Getenv(name))
}
