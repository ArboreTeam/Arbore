// Issue #160 — cleanup batch des comptes de test laissés en base par la
// CI (pattern d'email `@arbore.test`). À exécuter via le wrapper bash
// `cleanup-test-users.sh` qui injecte la bonne URI Mongo, ou directement
// via `mongosh "<uri>" --file scripts/cleanup-test-users.js`.
//
// Comportement :
//   1. Trouve tous les users dont l'email matche `/@arbore\.test$/`.
//   2. Cascade : supprime gardens + consents liés à leurs `uid`.
//   3. Supprime les users eux-mêmes.
//   4. Imprime un résumé (counts) en JSON-ish pour parsing aval.
//
// Précautions :
//   - Le pattern est ancré strict (`$`) pour éviter de matcher un email
//     comme `user@arbore.test.example.com`.
//   - Ne touche PAS aux users dont l'email est nul/absent — c'est un cas
//     valide pour des comptes Firebase fraîchement créés sans email
//     vérifié (cf. #137 orphans).
//   - Ne touche PAS au pool Firebase Auth. La cohérence Firebase ↔ Mongo
//     se règle à part : un user Firebase sans doc Mongo peut être
//     re-créé via le signup flow.

const TEST_EMAIL_PATTERN = /@arbore\.test$/;

const candidateUids = db.users.distinct("uid", { email: TEST_EMAIL_PATTERN });
const usersFound = candidateUids.length;

print(`[cleanup-test-users] found ${usersFound} candidate users matching ${TEST_EMAIL_PATTERN}`);

if (usersFound === 0) {
    print(`[cleanup-test-users] nothing to do.`);
    quit(0);
}

const gardensResult = db.gardens.deleteMany({ uid: { $in: candidateUids } });
const consentsResult = db.consents.deleteMany({ uid: { $in: candidateUids } });
const usersResult = db.users.deleteMany({ email: TEST_EMAIL_PATTERN });

print(`[cleanup-test-users] deleted: ` + JSON.stringify({
    users: usersResult.deletedCount,
    gardens: gardensResult.deletedCount,
    consents: consentsResult.deletedCount,
    timestampUTC: new Date().toISOString(),
}));
