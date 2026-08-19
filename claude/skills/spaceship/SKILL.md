---
name: spaceship
description: Manage domains registered at Spaceship (spaceship.com) through their REST API — read domain info, change nameservers, edit DNS records, register/renew/transfer domains, manage contacts and vanity nameservers. Use this whenever a domain registered at Spaceship comes up, whenever the user mentions spaceship.dev, SPACESHIP_API_KEY, or an X-Api-Key/X-Api-Secret pair, and whenever someone wants to point a domain at Cloudflare/Vercel/Netlify/Route 53, add or change A/CNAME/MX/TXT records, set up SPF/DKIM/DMARC, verify a domain, or check who a domain is delegated to — even if they never say the word "Spaceship". Also use it before touching DNSSEC on a Spaceship domain, since that step cannot be automated and getting the order wrong takes the domain offline.
---

# Spaceship

Spaceship is a domain registrar with a straightforward REST API at
`https://spaceship.dev/api/v1`. This skill covers registrar work: domains,
nameservers, DNS records, contacts, transfers.

Most tasks are one or two calls. The parts that reliably go wrong are DNS record
payload shapes, tight per-endpoint rate limits, and DNSSEC — which has no API at
all and will take a domain offline if handled in the wrong order.

## Credentials

Both headers are required on every request:

```
X-Api-Key: <key>
X-Api-Secret: <secret>
```

Keys come from the Spaceship dashboard → API Manager
(https://www.spaceship.com/application/api-manager/). Look for
`SPACESHIP_API_KEY` / `SPACESHIP_API_SECRET` in the environment or in
`~/.config/agents/secrets.env` before asking the user for them.

Note that **Namecheap credentials do not work here.** Spaceship is Namecheap-owned
but separately accredited with its own account system; `api.namecheap.com` cannot
see Spaceship domains.

## Use the bundled helper

`scripts/ss` wraps curl: it loads credentials, adds the mandatory pagination
params, pretty-prints JSON, and turns HTTP status codes into a readable
diagnosis instead of a bare number.

Your working directory is the user's project, not this skill, so invoke it by its
full path. Set a shell variable once:

```sh
ss=~/.claude/skills/spaceship/scripts/ss

$ss GET /domains
$ss GET /domains/example.com
$ss GET /dns/records/example.com
$ss PUT /domains/example.com/nameservers '{"provider":"custom","hosts":["a.ns.example","b.ns.example"]}'
$ss DELETE /dns/records/example.com '[{"type":"A","name":"@","address":"1.2.3.4"}]'
```

Plain curl is fine too — the helper just removes the paper cuts.

## Before you change anything

Two checks take one call and prevent the two worst outcomes.

**Read the domain first.** `GET /v1/domains/{domain}` returns everything:
`nameservers{provider, hosts[]}`, `expirationDate`, `eppStatuses`,
`privacyProtection`, `contacts`, `autoRenew`.

**Check `nameservers.provider`.** It is either `basic` (Spaceship's own DNS — the
records at `/v1/dns/records/{domain}` are live) or `custom` (delegated elsewhere).
If it is `custom`, editing Spaceship's DNS records returns 200 and changes
nothing that resolves, because the world is asking different nameservers. Tell
the user where their DNS actually lives instead of writing records into a zone
nobody reads.

## DNSSEC: the one thing that can break a domain

**Spaceship exposes no DNSSEC endpoint.** Verified: `/dnssec`, `/ds-records`,
`/ds` and friends all 404, and the string does not appear in the OpenAPI spec.

This matters because of ordering. If a DS record is published at the registry and
you move the nameservers away from Spaceship, the new nameservers cannot produce
signatures matching that DS record, and **every validating resolver stops
resolving the domain**. Not slower — offline, for most of the internet.

So before repointing nameservers, check:

```sh
dig +short example.com DS
# no dig available?
curl -sS "https://dns.google/resolve?name=example.com&type=DS"
```

If anything comes back, stop. Tell the user to disable DNSSEC in the Spaceship
dashboard (Domain → Advanced DNS → DNSSEC), wait for the DS record to clear the
registry, and only then repoint. You cannot do this step through the API, and
there is no workaround — say so plainly rather than improvising.

## Common tasks

### Point a domain at Cloudflare, Vercel, or another host

1. `GET /v1/domains/{domain}` — note `nameservers.provider` and `hosts`.
2. Check for a DS record (above). Stop if one exists.
3. Get the target nameservers from the host (Cloudflare assigns a pair per zone).
4. ```sh
   scripts/ss PUT /domains/example.com/nameservers \
     '{"provider":"custom","hosts":["lana.ns.cloudflare.com","martin.ns.cloudflare.com"]}'
   ```
   `hosts` needs 2–12 entries. To hand DNS back to Spaceship, send
   `{"provider":"basic"}` with **no** `hosts` key.
5. Verify with `dig NS example.com`. Registry propagation takes minutes to hours,
   so a stale answer immediately afterwards is expected, not a failure.

**This call is limited to 5 updates per domain per 300 seconds.** Assemble the
complete host list and check it before sending — you get one clean attempt.

### Add or change DNS records

Read `references/dns.md` before writing. The payload shape differs across the
three verbs, and per-type field names (`address`, `cname`, `exchange`,
`nameserver`, `value`…) are easy to guess wrong.

**You cannot point the apex at a hostname.** The advertised `ALIAS` type is
silently stored as a plain apex `CNAME`, which Spaceship's nameservers will not
serve — the write returns 204, the record reads back fine, and the apex resolves
to nothing. If a task needs `example.com` (not just `www`) pointing at a Pages or
Vercel hostname, Spaceship DNS cannot do it; the zone has to be delegated
somewhere that flattens. `references/dns.md` has the detail and the options.

The one behaviour worth knowing up front: **PUT is upsert, not replace.** It will
not wipe the zone, but it also cannot edit a value in place — "changing" a record
by PUTting a new value leaves both old and new live. Delete first, then write.

### Register, renew, or transfer

These return **202** with an empty body. The operation id is in the
`spaceship-async-operationid` response header. Poll
`GET /v1/async-operations/{id}` (limit 60/user/300s, so roughly once every 5
seconds) until `status` is `success` or `failed`.

A 202 means accepted. Do not report success to the user off the back of one.

Registration needs a contact id, not inline contact details — create one with
`PUT /v1/contacts` first. Its `phone` field must look like `+1.5551234567`.

## Rate limits will bite you

They are per-endpoint and tighter than you expect. The two that matter:

- **Domain info: 5 per domain per 300 seconds.** Easy to exhaust while exploring.
- **Nameserver update: 5 per domain per 300 seconds.**

A useful workaround: `GET /v1/domains?take=100&skip=0` returns the *same* full
objects under a much looser limit (300/user/300s). When you need details for
several domains, or might loop, list once and filter locally.

`take` **and** `skip` are both required on every collection — omitting `skip` is a
422, not a default.

When a call fails, read `detail` before concluding anything. A 429 and a bad key
both look like "it didn't work" but point in opposite directions:

| Status | Means |
| --- | --- |
| 401 | Bad or missing key/secret |
| 403 | Valid key, missing scope |
| 404 | Not on this account (the message names the user id) |
| 422 | Validation — `data[]` names the offending field |
| 429 | Rate limited — `data.rateLimitRule` states the window |

## Reference files

Load these as needed rather than up front. They live alongside this file in
`~/.claude/skills/spaceship/`:

- `references/dns.md` — record payloads for all three verbs, per-type fields,
  worked examples. **Read before any DNS write.**
- `references/api.md` — every endpoint, params, and per-endpoint rate limits.
  Read when a task goes beyond the common cases above.
- `references/gotchas.md` — the verified sharp edges: DNSSEC, pagination, rate
  limits, TTL caps, TXT case sensitivity, endpoints that look plausible but 404.

## Things that simply do not exist

Do not build a plan around these — confirm before promising them:

- **DNSSEC / DS management** — dashboard only.
- `DELETE /v1/domains/{domain}` — returns 501.
- Domain search or suggestions, pricing, webhooks.
- URL forwarding, email forwarding, mailboxes.
- `/users/me`, `/contacts` (as a list), `/domains/{d}/contacts`,
  `/domains/{d}/privacy-protection`, `/domains/{d}/transfer-lock` — all 404.
  Contact and privacy data come back inside the domain object.
