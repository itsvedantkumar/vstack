# Spaceship API — DNS records

Three operations on `/v1/dns/records/{domain}`, and each takes a differently
shaped body. Getting the shape wrong is the most common failure, so check here
rather than guessing.

## Read

```
GET /v1/dns/records/{domain}?take=500&skip=0
```

`take` (1–500) and `skip` are both **required**. Optional `orderBy`: `type`,
`-type`, `name`, `-name`.

```json
{"items": [
   {"type":"TXT","name":"tbolt","value":"eb854efb-…","ttl":300,
    "group":{"type":"product"}}
 ],
 "total": 1}
```

`group.type` tells you who owns the record:

| Value | Meaning |
| --- | --- |
| `custom` | The user's own record. Yours to manage. |
| `product` | Injected by a Spaceship product. Leave alone unless asked. |
| `personalNs` | Glue for vanity nameservers. Managed via the personal-nameservers endpoints. |

## Write

```
PUT /v1/dns/records/{domain}     →  204 No Content
```

```json
{"force": false, "items": [ /* 1–500 records */ ]}
```

**PUT is upsert/append, not replace-all.** Existing records survive; the call
adds new ones and updates the TTL of matches. That means two things:

- A naive PUT will not wipe the zone. Good.
- You **cannot change a record's value in place**. Editing `1.2.3.4` → `5.6.7.8`
  is DELETE the old record, then PUT the new one. A PUT alone leaves you with
  both, which usually breaks whatever the user was trying to fix.

Matching is case-insensitive **except for TXT**, which is case-sensitive.

`force: true` disables the conflict-resolution checker and forces the zone
update. Leave it `false` unless a conflict genuinely needs overriding — it exists
to let you write records that the checker would otherwise reject.

### Fields on every record

- `type` — the discriminator, uppercase (`A`, `MX`, …). An unknown value returns a
  confusing .NET deserialization error rather than a clean message.
- `name` — the **host label only**, no domain suffix. `@` is the apex, `*` is
  allowed. Max 253.
- `ttl` — optional, **60–3600**. Larger values are rejected, which surprises
  people used to 86400.

### Per-type fields

| Type | Fields |
| --- | --- |
| `A` | `address` (IPv4) |
| `AAAA` | `address` (IPv6) |
| `CNAME` | `cname` |
| `ALIAS` | `aliasName` — **but see the apex warning below; this does not work** |
| `NS` | `nameserver` |
| `PTR` | `pointer` |
| `MX` | `exchange`, `preference` (0–65535) |
| `TXT` | `value` (1–65535) |
| `SRV` | `service` (`_sip`), `protocol` (`_tcp`), `priority`, `weight`, `port` (1–65535), `target` |
| `CAA` | `flag` (0 or 128), `tag` (`issue`\|`issuewild`\|`iodef`), `value` (≤256) |
| `HTTPS`, `SVCB` | `svcPriority`, `targetName`, `svcParams`, plus `port`, `scheme` |
| `TLSA` | `port`, `protocol`, `usage`, `selector`, `matching`, `associationData` (hex) |

### Examples

```json
{"force": false, "items": [
  {"type":"A",     "name":"@",       "address":"203.0.113.10", "ttl":300},
  {"type":"CNAME", "name":"www",     "cname":"example.com",    "ttl":300},
  {"type":"MX",    "name":"@",       "exchange":"mx1.example.net", "preference":10},
  {"type":"TXT",   "name":"@",       "value":"v=spf1 include:_spf.example.net ~all"},
  {"type":"CAA",   "name":"@",       "flag":0, "tag":"issue", "value":"letsencrypt.org"},
  {"type":"SRV",   "name":"_sip._tcp","service":"_sip","protocol":"_tcp",
   "priority":10,"weight":5,"port":5060,"target":"sip.example.net"}
]}
```

## Delete

```
DELETE /v1/dns/records/{domain}     →  204 No Content
```

The body is a **bare JSON array** — no `items` wrapper, no `force`:

```json
[{"type":"A", "name":"@", "address":"203.0.113.10"}]
```

Deletion matches on the full record, not just name and type, so you must supply
the identifying value: `address` for A/AAAA, `cname`, `nameserver`, `value` for
TXT, `exchange` + `preference` for MX, all six fields for SRV, `flag` + `tag` +
`value` for CAA. Do **not** include `ttl`.

Because TXT matching is case-sensitive, a TXT delete whose casing differs from
what is stored silently matches nothing and still returns 204. Read the records
back to confirm rather than trusting the status code.

## You cannot point the apex at a hostname

The spec advertises an `ALIAS` type, which normally means CNAME flattening at the
zone apex. **It does not work.** Verified 2026-08-06 on a live domain:

```jsonc
// sent
{"type":"ALIAS","name":"@","aliasName":"example.pages.dev","ttl":3600}
// read back — silently coerced to a plain CNAME
{"type":"CNAME","name":"@","cname":"example.pages.dev","ttl":3600,"group":{"type":"custom"}}
```

The write returns 204 and the record appears in `GET`, but Spaceship's
nameservers **refuse to serve it** — an apex CNAME conflicts with the zone's own
SOA and NS records, and there is no flattening. `dig @launch1.spaceship.net
example.com A` returns NOERROR with no answer. A `www` CNAME written in the same
call resolves instantly, so this is specific to the apex.

This is the nastiest failure mode in the whole API: every layer reports success
and the apex simply does not resolve.

So if a task needs the apex to reach a PaaS hostname (Cloudflare Pages, Vercel,
Netlify), Spaceship DNS cannot do it. The options are:

1. **Delegate the zone** to a provider that flattens (Cloudflare, Route 53
   ALIAS). This is the real fix — but it means moving nameservers, so check
   DNSSEC first (see `gotchas.md`).
2. **Use A records** if the host publishes stable anycast IPs. Many PaaS
   providers do not, and their IPs rotate, so treat this as fragile.
3. **Serve on `www` and redirect the apex** — which still needs something
   resolvable at the apex, so it does not escape the problem on its own.

Say which of these you are doing rather than writing an ALIAS and reporting
success.

## Working safely

1. `GET` the current records first — you need exact values to delete anything,
   and you want to know which records carry a `group` you should not touch.
2. Check `nameservers.provider` on the domain. If it is `custom`, this zone is
   not what the world resolves; editing it will appear to work and change
   nothing. Say so instead of writing.
3. To change a value: DELETE the old record, PUT the new one, then GET to verify.
4. 204 means accepted, not necessarily matched. Verify by reading back.
