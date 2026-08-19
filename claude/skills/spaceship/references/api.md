# Spaceship API — endpoint reference

OpenAPI 3.0.0, `info.version` 1.0.0, title "Spaceship.com".
Base URL `https://spaceship.dev/api`, so paths below are e.g.
`https://spaceship.dev/api/v1/domains`.

Auth headers on every request: `X-Api-Key`, `X-Api-Secret`.
Scopes: `domains:read|write|transfer|billing`, `contacts:read|write`,
`dnsrecords:read|write`, `asyncoperations:read`.

DNS record payloads are the fiddly part and live in `dns.md`.

## Contents
- [Domains](#domains)
- [Nameservers](#nameservers)
- [Transfer and EPP](#transfer-and-epp)
- [Contacts](#contacts)
- [Async operations](#async-operations)
- [Not in the spec](#not-in-the-spec)

## Domains

| Method | Path | Purpose | Rate limit |
| --- | --- | --- | --- |
| GET | `/v1/domains` | List. `take` 1–100 **and** `skip` both required; optional `orderBy` (array, max 1 item) of `name`, `-name`, `registrationDate`, `-registrationDate`, `expirationDate`, `-expirationDate` | 300/user/300s |
| GET | `/v1/domains/{domain}` | Full domain object | **5/domain/300s** |
| POST | `/v1/domains/{domain}` | Register → 202 | 30/user/30s |
| POST | `/v1/domains/{domain}/renew` | Renew → 202. `years` 1–10, `currentExpirationDate` | 30/user/30s |
| POST | `/v1/domains/{domain}/restore` | Restore from redemption → 202 | 30/user/30s |
| DELETE | `/v1/domains/{domain}` | **501, unimplemented** | — |
| PUT | `/v1/domains/{domain}/autorenew` | `{"isEnabled": bool}` | 5/domain/300s |
| POST | `/v1/domains/available` | Bulk availability, `domains` 1–20 | 30/user/30s |
| GET | `/v1/domains/{domain}/available` | Single availability | 5/domain/300s |
| PUT | `/v1/domains/{domain}/contacts` | `registrant` required; `admin`, `tech`, `billing`, `attributes` (≤5) | 5/domain/300s |
| PUT | `/v1/domains/{domain}/privacy/preference` | `{"privacyLevel":"public"\|"high","userConsent":bool}` | 5/domain/300s |
| PUT | `/v1/domains/{domain}/privacy/email-protection-preference` | `{"contactForm": bool}` | 5/domain/300s |

Register body: `autoRenew` bool, `years` 1–10,
`privacyProtection{level:"public"|"high", userConsent:bool}`,
`contacts{registrant, admin, tech, billing, attributes[]}` — contact **ids**, only
`registrant` is required. `userConsent` must be sent explicitly.

The domain object returned by both list and info carries everything useful:
`name`, `unicodeName`, `isPremium`, `autoRenew`, `registrationDate`,
`expirationDate`, `lifecycleStatus`, `verificationStatus`, `eppStatuses[]`,
`suspensions[]`, `privacyProtection{}`, `nameservers{provider, hosts[]}`,
`contacts{}`.

## Nameservers

| Method | Path | Purpose | Rate limit |
| --- | --- | --- | --- |
| PUT | `/v1/domains/{domain}/nameservers` | Replace delegation | **5/domain/300s** |
| GET | `/v1/domains/{domain}/personal-nameservers` | Vanity NS → `{records:[{host, ips[]}]}` | 5/domain/300s |
| PUT | `/v1/domains/{domain}/personal-nameservers/{currentHost}` | Create **or rename** vanity NS. `host` (label, e.g. `ns1`), `ips` 1–16 | 10/domain/300s |
| DELETE | `/v1/domains/{domain}/personal-nameservers/{currentHost}` | Remove vanity NS | 10/domain/300s |
| GET | `/v1/domains/{domain}/personal-nameservers/{currentHost}` | **501, unimplemented** | — |

There is **no GET for regular nameservers** — read `nameservers.hosts` from the
domain object instead.

```jsonc
// point at someone else's nameservers
{"provider": "custom", "hosts": ["ns1.example.net", "ns2.example.net"]}
// hand back to Spaceship's own DNS — omit hosts entirely
{"provider": "basic"}
```

`hosts` must have 2–12 entries when `custom`, and must be **absent** when `basic`.

On the vanity-NS PUT, if body `host` differs from the `{currentHost}` in the
path, that is a rename — the old host then 404s.

## Transfer and EPP

| Method | Path | Purpose | Rate limit |
| --- | --- | --- | --- |
| GET | `/v1/domains/{domain}/transfer` | `{startedAt, finishedAt, direction:"in", status: pending\|completed\|cancelled}` | 5/domain/300s |
| POST | `/v1/domains/{domain}/transfer` | Start transfer-in → 202. Optional `authCode` | 30/user/30s |
| GET | `/v1/domains/{domain}/transfer/auth-code` | `{authCode, expires}` | 5/domain/300s |
| PUT | `/v1/domains/{domain}/transfer/lock` | `{"isLocked": bool}` | 5/domain/300s |

## Contacts

| Method | Path | Purpose | Rate limit |
| --- | --- | --- | --- |
| PUT | `/v1/contacts` | Create → returns contact id | 300/user/300s |
| GET | `/v1/contacts/{contact}` | Read | 5/contact/300s |
| PUT | `/v1/contacts/attributes` | Registry extras, discriminated on `type`: `ca` or `us` | — |
| GET | `/v1/contacts/attributes/{contact}` | Read extras | — |

Required on create: `firstName`, `lastName`, `email`, `address1`, `city`,
`country` (ISO-2, uppercase), `phone`. Optional: `organization`, `address2`,
`stateProvince`, `postalCode`, `phoneExt`, `fax`, `faxExt`, `taxNumber`.

`phone` must match `+CC.NUMBER` — e.g. `+1.5551234567`. This is the field people
get wrong most often. `stateProvince` and `postalCode` requirements vary by
country and are enforced server-side.

## Async operations

`GET /v1/async-operations/{operationId}` → `{status: pending|failed|success,
type, details, createdAt, modifiedAt}`. Limit **60/user/300s**, so poll no faster
than about once every 5 seconds.

Only four endpoints return 202: register, renew, restore, and transfer-in. The
operation id arrives in the `spaceship-async-operationid` **response header**,
not the body — the body is empty.

## Not in the spec

Do not plan around these; they do not exist:

- **DNSSEC / DS records** — no endpoint anywhere. See `gotchas.md`.
- Domain search or suggestions, pricing, webhooks.
- URL forwarding, email forwarding, mailboxes.
- Any per-domain contacts/privacy *GET* — that data comes inside the domain object.

The spec also carries SellerHub (marketplace listings, checkout links, SafePay)
and Hyperlift (app hosting: build, logs, metrics, env, scale) endpoints. They are
unrelated to registrar work; read the spec directly if a task needs them.
