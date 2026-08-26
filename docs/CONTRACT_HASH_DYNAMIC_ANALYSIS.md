# Analysis: Dynamic contract hash (avoid a fixed field list)

## Current state

### V1 (sign a message)
- **Message** = fixed format: `TimeFixed|start|end|appPubKey|storagePubKey|totalFee|totalFileSize` (or OpenEnded|...).
- **Problem:** Adding any new field (for example `renewalOption`, `metadata`) requires changing the message format in the App, Store, and Blocker. Easy to break.

### V2 (sign a contract hash) today
- **Canonical** = a **fixed** list of 11 fields (appPublicKey, contractId, contractType, createdAtUnix, endDateUnix?, fileIds, startDateUnix, status, storageNodePublicKey, totalFee, totalFileSize).
- **Problem:** If Store returns extra fields (for example `renewalOption`, `billingCycle`) and those fields should be part of the signed contract, they must be added to the canonical list in **all three** places (App, Store, Blocker). The code is not dynamic.

---

## Goal

- When Store sends a new field to the App, we should **not** have to patch many places (ideally not all three codebases).
- V2 should **sign the contract contents** (equivalent to the JSON Store returns), not build a message from a fixed field list like V1.

---

## Approach 1: Store is the source of truth — App only signs the hash Store sends

**Idea:** Store computes `contractHash` from the contract (using Store's own rules). Store returns `contractHash` in the response (create / get / sign). The App does **not** build a canonical form and does **not** hash locally; it only signs the `contractHash` string Store sent.

**Flow:**
1. App calls create/sign → Store returns the contract plus `contractHash`.
2. App shows the contract to the user; the user accepts.
3. App signs **exactly** the `contractHash` received from Store and sends `appSignature` (and optionally `signingVersion: 2`) back to Store.
4. Store already has the contract and `contractHash`; it verifies the App signature over `contractHash` and is done.
5. When submitting a tx to the Blocker, Store sends the contract, `contractHash`, and signatures. The Blocker only needs to verify the signature over `contractHash` (already implemented).

**When Store adds a new field:**
- Only **Store** decides whether that field is included in the canonical form used to compute `contractHash`.
- If Store uses a **dynamic canonical** (see Approach 3), it only needs to ensure the contract object has the new field before calling `ComputeContractHash`. App and Blocker **do not change code**.

**Pros:**
- One source of truth: **Store** decides what the contract is and what hash is signed.
- App / Blocker need no canonical logic and no field list.
- A new field from Store at most requires a Store change (and only if Store changes how the hash is computed).

**Cons:**
- The App must trust the hash Store sends (acceptable in practice: the App is signing the contract Store described).

---

## Approach 2: Canonical = “every field except an exclusion list”

**Idea:** Do not define canonical as an **allow-list** of fields. Instead:
- Take the whole contract object **except** a few “proof-only” keys that are not contract content.
- Exclusion list: `contractHash`, `messageToSign`, `appSignature`, `storageNodeSignature` (extend later if needed).
- Remaining keys → sort alphabetically → serialize values with a shared convention → that is the canonical JSON.

**Value conventions (so App / Store / Blocker produce the same hash):**
- `totalFee` → always string F10 (already used).
- `fileIds` → array of strings, sorted alphabetically.
- Numbers → number (integer if whole, no extra `.0`).
- Unknown “new” fields → standard JSON (string, number, bool, array, object). All three sides only need the same rules (for example “number as number, string as string”) for hashes to match.

**When Store adds a new field:**
- The new field is on the contract object → it is **automatically** in the canonical form (it is not on the exclusion list).
- App / Store / Blocker all use “all keys except X, sort, serialize” → no field-list change when adding fields.

**Pros:**
- Truly dynamic: adding a field does not require a code change (as long as serialization stays consistent).
- The Blocker can still recompute the hash from the received contract if desired.

**Cons:**
- All three sides must implement the **same** serialization rules; easy to drift on edge cases (floats, null, nested key order).

---

## Approach 3: Combined — Store computes the hash using a dynamic canonical

**Idea:**
- **Store** is the only place that builds the canonical form and computes `contractHash` (Approach 1).
- Inside Store, canonical is built with the **dynamic rule** (Approach 2): every contract field except the exclusion list, sorted keys, standard serialize.
- App only signs the `contractHash` Store returns; Blocker only verifies the signature over `contractHash` in the tx.

**Result:**
- Adding a field from Store: only ensure the Store contract object has that field before calling the dynamic canonical function. App and Blocker do not change.
- Avoids “build a message from a fixed field list” as in V1 entirely.

---

## Quick comparison

| Criterion | V1 (message) | V2 today (fixed list) | Approach 1 (Store hash) | Approach 2 (dynamic canonical) | Approach 3 (1+2) |
|-----------|--------------|------------------------|-------------------------|--------------------------------|------------------|
| New field | Change 3 places, change format | Change 3 places, add to list | Store only (if needed) | No change (auto include) | Store only (if needed) |
| App builds canonical? | No (builds message) | Yes, 11 fixed fields | **No** | Yes, “all except X” | **No** |
| Source of truth | Unclear (shared format) | Unclear (shared list) | **Store** | Shared rule on 3 sides | **Store** |
| App complexity | Medium | High (sync list with Store) | **Low** (sign hash only) | High (serial rules) | **Low** |

---

## Recommendation

- **Short term / small change:** Keep the current V2 flow but **formalize Approach 1**: the App **always** signs the `contractHash` Store returns (it does not hash its own model). Store already returns `contractHash` in the sign response; it can also add it to the create response if the App needs to sign immediately after create. The Blocker already verifies the signature over `contractHash` and does not need to recompute the hash. That is already “sign what Store sent” (the hash of the contract Store described).
- **Long term / truly dynamic:** Store moves to a **dynamic canonical** (Approach 3): `ComputeContractHash` on Store does not use a fixed 11-field list; it builds from the whole contract object minus the exclusion list, sorted keys, standard serialize. Then a new field from Store does not require App or Blocker changes; Store only needs the field on the contract object before hashing.

In short: **“Dynamic” relative to V1’s fixed message is already covered** if we apply Approach 1 (App only signs the hash Store sends). **“New Store fields do not require code changes”** is covered if Store uses a dynamic canonical (Approach 3).
