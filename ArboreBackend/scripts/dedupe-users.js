// Audit #338 constat 1 — dédoublonnage de la collection `users`.
//
// `createUser` faisait un `InsertOne` inconditionnel : un document de plus à
// chaque appel. Combiné à un `deleteUser` en `DeleteOne`, l'effacement d'un
// compte laissait des données personnelles derrière lui alors que l'identité
// Firebase était supprimée — l'utilisateur ne pouvait donc plus jamais demander
// leur effacement (RGPD Art. 17).
//
// Exécution :
//   DRY-RUN (défaut, n'écrit RIEN) :
//     mongosh "<uri>" --file scripts/dedupe-users.js
//   APPLICATION réelle :
//     mongosh "<uri>" --eval 'const APPLY = true' --file scripts/dedupe-users.js
//
// ⚠️ Prendre un `mongodump` avant l'exécution réelle. `deploy.sh` en fait un
//    automatiquement, mais ce script se lance hors déploiement.
//
// ── Règle de fusion ────────────────────────────────────────────────
//
// Le document survivant est celui au `_id` le plus ancien, mis à jour avec les
// champs fusionnés ; les autres sont supprimés.
//
//   - champ absent/vide d'un côté  → la valeur non vide gagne
//   - deux valeurs non vides qui diffèrent → la plus RÉCENTE gagne
//   - `createdAt` → on garde la PLUS ANCIENNE (vraie date de création)
//   - `banned`    → `true` si N'IMPORTE QUELLE copie est bannie (fail-safe)
//
// Pourquoi pas simplement « garder la copie la plus récente » : mesuré sur la
// production, 2 des 7 comptes dupliqués ne portaient leur
// `appleRefreshTokenEncrypted` que sur leur copie la PLUS ANCIENNE. Les perdre
// aurait rendu la révocation du compte Apple impossible à la suppression
// (Guideline 5.1.1(v), cf. #210).
//
// Rien ne référence le `_id` d'un user : `gardens` et `consents` sont indexés
// sur `uid`. Supprimer des doublons n'orpheline donc aucune donnée.

const APPLY = typeof globalThis.APPLY !== "undefined" && globalThis.APPLY === true;
const mode = APPLY ? "APPLICATION" : "DRY-RUN";

print(`[dedupe-users] mode: ${mode}${APPLY ? "" : "  (aucune écriture — relancer avec --eval 'const APPLY = true' pour appliquer)"}`);
print("");

const groups = db.users
    .aggregate([
        { $group: { _id: "$uid", n: { $sum: 1 }, docs: { $push: "$$ROOT" } } },
        { $match: { n: { $gt: 1 } } },
    ])
    .toArray();

if (groups.length === 0) {
    print("[dedupe-users] aucun doublon — rien à faire.");
    quit(0);
}

const totalDocs = groups.reduce((acc, g) => acc + g.n, 0);
print(`[dedupe-users] ${groups.length} uid dupliqué(s), ${totalDocs} document(s), ${totalDocs - groups.length} à supprimer`);
print("");

// Champs fusionnés. `_id` est exclu : le survivant garde le sien.
const MERGED_FIELDS = [
    "uid",
    "email",
    "name",
    "photoData",
    "photoContentType",
    "appleRefreshTokenEncrypted",
];

const isEmpty = (v) =>
    v === undefined || v === null || v === "" || (Array.isArray(v) && v.length === 0);

// Ordre chronologique : `_id` ObjectId est monotone, et sert de départage
// quand `createdAt` est absent ou identique.
const byAge = (a, b) => {
    const ta = a.createdAt ? String(a.createdAt) : "";
    const tb = b.createdAt ? String(b.createdAt) : "";
    if (ta !== tb) return ta < tb ? -1 : 1;
    return String(a._id) < String(b._id) ? -1 : 1;
};

let deletedTotal = 0;
let updatedTotal = 0;
const conflicts = [];

groups.forEach((group, index) => {
    const docs = group.docs.slice().sort(byAge);
    const survivor = docs[0];
    const doomed = docs.slice(1);

    const merged = {};
    MERGED_FIELDS.forEach((field) => {
        // Du plus ancien au plus récent : une valeur non vide plus récente
        // écrase une valeur non vide plus ancienne, mais jamais l'inverse.
        let chosen = undefined;
        let chosenFrom = null;
        docs.forEach((doc) => {
            if (!isEmpty(doc[field])) {
                if (!isEmpty(chosen) && JSON.stringify(chosen) !== JSON.stringify(doc[field])) {
                    conflicts.push({
                        uid: group._id,
                        field,
                        ancien: chosen,
                        retenu: doc[field],
                    });
                }
                chosen = doc[field];
                chosenFrom = doc._id;
            }
        });
        if (!isEmpty(chosen)) merged[field] = chosen;
        if (field === "appleRefreshTokenEncrypted" && !isEmpty(chosen) && String(chosenFrom) !== String(survivor._id)) {
            print(`    ↳ token Apple récupéré depuis la copie ${String(chosenFrom).slice(-6)} (aurait été perdu en gardant la plus récente)`);
        }
    });

    // createdAt : la plus ancienne valeur non vide.
    const createdAts = docs.map((d) => d.createdAt).filter((v) => !isEmpty(v)).sort();
    if (createdAts.length > 0) merged.createdAt = createdAts[0];

    // banned : fail-safe, un seul `true` suffit.
    merged.banned = docs.some((d) => d.banned === true);

    const mask = (e) => (!e ? "(vide)" : String(e).slice(0, 2) + "***@" + (String(e).split("@")[1] || "?"));
    print(`[${index + 1}/${groups.length}] uid ${String(group._id).slice(0, 10)}…  ${group.n} copies → 1`);
    print(`    survivant : _id=${String(survivor._id).slice(-6)}`);
    print(`    fusionné  : nom="${merged.name ?? ""}"  email=${mask(merged.email)}  créé=${merged.createdAt ?? "?"}`);
    print(`                photo=${isEmpty(merged.photoData) ? "non" : "OUI"}  appleToken=${isEmpty(merged.appleRefreshTokenEncrypted) ? "non" : "OUI"}  banned=${merged.banned}`);
    print(`    supprimés : ${doomed.map((d) => String(d._id).slice(-6)).join(", ")}`);

    if (APPLY) {
        const updateResult = db.users.updateOne({ _id: survivor._id }, { $set: merged });
        const deleteResult = db.users.deleteMany({ _id: { $in: doomed.map((d) => d._id) } });
        updatedTotal += updateResult.modifiedCount;
        deletedTotal += deleteResult.deletedCount;
        print(`    → appliqué : ${updateResult.modifiedCount} mis à jour, ${deleteResult.deletedCount} supprimé(s)`);
    }
    print("");
});

if (conflicts.length > 0) {
    print("── Conflits résolus (deux valeurs non vides différentes, la plus récente l'emporte) ──");
    conflicts.forEach((c) => {
        const show = (v) => (c.field === "appleRefreshTokenEncrypted" || c.field === "photoData" ? "<binaire>" : JSON.stringify(v));
        print(`   uid ${String(c.uid).slice(0, 10)}…  ${c.field} : ${show(c.ancien)} → ${show(c.retenu)}`);
    });
    print("");
}

print("── Résumé ──");
print(`   mode              : ${mode}`);
print(`   uid dupliqués     : ${groups.length}`);
print(`   documents avant   : ${totalDocs}`);
print(`   documents après   : ${groups.length}`);
if (APPLY) {
    print(`   survivants mis à jour : ${updatedTotal}`);
    print(`   documents supprimés   : ${deletedTotal}`);

    const remaining = db.users
        .aggregate([{ $group: { _id: "$uid", n: { $sum: 1 } } }, { $match: { n: { $gt: 1 } } }])
        .toArray().length;
    print(`   doublons restants     : ${remaining}`);
    if (remaining === 0) {
        print("   ✅ `users.uid` peut désormais recevoir un index UNIQUE.");
    } else {
        print("   ❌ des doublons subsistent — ne pas créer l'index unique.");
    }
} else {
    print("   (aucune écriture effectuée)");
}
