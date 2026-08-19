# Spaceship API — gotchas

Everything here was verified against the live API, not just read in the docs.

## 1. DNSSEC is not in the API at all

There is no endpoint. Verified 404 on `/dnssec`, `/ds-records`, `/dnssec-records`,
`/ds`, `/securedns`, and "dnssec" does not appear in the OpenAPI spec.

This matters more than it sounds. **Moving a domain's nameservers away from
Spaceship while a DS record is still published at the registry takes the domain
dark for every validating resolver** — not degraded, gone. If someone asks you to
repoint nameservers, check for a DS record first:

```sh
dig +short example.com DS
# or, without dig:
curl -sS "https://dns.google/resolve?name=example.com&type=DS"
```

If anything comes back, stop and tell the user to disable DNSSEC in the Spaceship
dashboard (Domain → Advanced DNS → DNSSEC), wait for it to clear the registry,
and only then repoint. You cannot do this step for them through the API, so say
so plainly rather than attempting a workaround.

## 2. `take` and `skip` are both required

Collections do not default their pagination. `GET /domains?take=1` returns 422:

```json
{"detail":"The request is invalid.","data":[{"field":"skip","details":"The skip field is required."}]}
```

`scripts/ss` adds `take=100&skip=0` automatically for `/domains` and
`/dns/records/*` when you do not supply them.

## 3. Rate limits are per-endpoint and tight

The one that bites is **domain info: 5 requests per domain per 300 seconds**.
It is easy to burn through that while exploring, and the 429 body is specific:

```json
{"detail":"Request rate limit exceeded.",
 "data":{"rateLimitRule":"The limit for obtaining info for a domain is 5 requests per domain, within 300 seconds.",
         "limit":5,"windowInSeconds":300}}
```

**Workaround worth knowing:** `GET /domains?take=100&skip=0` returns the *same*
full objects — including `nameservers.hosts`, `expirationDate`, `eppStatuses`,
`privacyProtection` — under a much looser limit (300 per user per 300s). When you
need domain details and might loop, list once and filter locally rather than
calling domain-info per domain.

**Nameserver updates are 5 per domain per 300 seconds.** You effectively get one
clean attempt; assemble the full host list and verify it before sending.

## 4. Distinguish a 429 from a credential failure

A rate-limited call and a bad key both look like "it didn't work". They are not
the same problem and send you in opposite directions. Always read `detail`.
Error bodies are consistently `{"detail": string, "data"?: object|array}`:

| Status | Meaning |
| --- | --- |
| 401 | `{"detail":"The user's request was not properly authorized."}` — bad key/secret |
| 403 | Key is valid but lacks the scope (`domains:read/write`, `dnsrecords:read/write`) |
| 404 | Not on this account — includes the user id, e.g. `Domain 'x.org' not found for User 'ihb...'` |
| 422 | Validation; `data[]` names the offending field |
| 429 | Rate limit; `data.rateLimitRule` states the exact window, and the `X-RateLimit-Reset` / `Retry-After` headers say when to try again |

The spec documents 400 for validation, but the live API returns **422** — trust
the observed behaviour.

## 5. DNS writes are inert while the domain is on custom nameservers

`nameservers.provider` tells you which mode the domain is in:

- `"basic"` — Spaceship's own DNS. Records under `/dns/records/{domain}` are live.
- `"custom"` — someone else's nameservers (Cloudflare, Route 53…). You can still
  write records to Spaceship and get a 200, but **nothing resolves from them**,
  because the world is asking the other nameservers.

So before editing records, check the provider. If it is `custom`, editing
Spaceship's zone is almost certainly not what the user wants — tell them where
DNS actually lives.

## 6. Records you did not create

Spaceship injects its own records, tagged with `group`:

```json
{"value":"eb854efb-...","name":"tbolt","type":"TXT","ttl":300,"group":{"type":"product"}}
```

`group.type` is one of `custom` (the user's), `product` (Spaceship's), or
`personalNs` (vanity-nameserver glue). Only `custom` is yours to manage.

The zone-wipe you might fear is not the risk here — `PUT` is upsert, not
replace-all. The real risk is the opposite: because PUT cannot edit a value in
place, "changing" a record by PUTting the new value leaves **both** the old and
new records live. Delete the old one first. See `dns.md`.

Two more that cost time:

- **TTL is capped at 3600** (min 60). A perfectly ordinary `86400` is rejected.
- **TXT matching is case-sensitive**; every other type is case-insensitive. A TXT
  delete with the wrong casing matches nothing and still returns 204, so read
  records back rather than trusting the status.

## 7. Async operations

Register, transfer, and renew return **202** with the operation id in the
`spaceship-async-operationid` response header, not in the body. Poll
`GET /async-operations/{id}`. A 202 means "accepted", never "done" — do not
report success to the user off the back of one.

## 8. `DELETE /v1/domains/{domain}` returns 501

Unimplemented. Domains cannot be deleted through the API.

## 9. Namecheap credentials do not work here

Spaceship is Namecheap-owned but separately accredited, with its own account
system and API. `api.namecheap.com` cannot see or manage Spaceship domains, and
moving a domain between them is a full ICANN registrar transfer. If a machine has
`NAMECHEAP_API_KEY` set, that is not a substitute for Spaceship credentials.

## 10. Endpoints that do not exist

Verified 404, despite being plausible guesses: `/users/me`, `/contacts`,
`/domains/{d}/contacts`, `/domains/{d}/privacy-protection`,
`/domains/{d}/transfer-lock`, `/domains/{d}/auth-code`.

Contact and privacy data come back **inside the domain object** instead — read
`contacts` and `privacyProtection` from `GET /domains/{domain}`. Confirm a path
exists before building a plan around it.
