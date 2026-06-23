# Flux REST API: Design Sketch

> **Status: design sketch, partially implemented.** A standalone project
> (`flux-rest-server`) depending only on flux-core's public client API — it
> needs no flux-core changes. Phases 1–2 below (the per-user read-only service
> and its systemd + polkit activation) are implemented and packaged; phases
> 3–4 — guest-job access via `ssh://`, and the REST API itself — remain future
> design topics.  See [README.md](README.md) to build, install, and run.

## Key idea

Run the HTTP↔RPC translation in an **ordinary, unprivileged Flux client that
runs as the requesting user** — not a broker module. nginx authenticates the
user; the per-user client is started **as that user** (by systemd — Component
2).  From there:

- reaches the **system instance** over `local://` (guest role from
  `SO_PEERCRED`);
- reaches the **user's own jobs** over `ssh://` (login as the user, end-to-end
  encrypted, the system broker out of the data path);
- future: **signs its own job submissions** with MUNGE as the user.

Because it *is* the user, the whole thing has the **same trust as a CLI
session**: no privileged on-behalf-of component, no enterprise network
security infrastructure. This is the Open OnDemand pattern (a privileged
stager spawns a per-user web process); here even the privileged step is
delegated to systemd + polkit, so we write no setuid binary at all.

For in-cluster communication, it reuses what Flux already has — `local://`,
`ssh://` (`flux proxy ssh://…`, `flux uri --remote`), `SO_PEERCRED`
identity — and delegates TLS/auth to the site's nginx.

## Architecture

```
external client
  │  HTTPS
  ▼
nginx  (site TLS + authn; sets $remote_user)
  │  auth_request → start flux-rest-server@USER.socket   (systemd does setuid;
  │                                                        polkit authorizes)
  ▼  proxy_pass → /run/flux-rest-server/USER.sock
per-user flux-rest-server   ── runs AS the user, unprivileged ──
  │   parses HTTP/SSE, translates ↔ Flux RPC, signs as the user
  ├─ local://                  → system instance (guest role; SO_PEERCRED)
  └─ ssh://node/…/local        → the user's job  (owner; e2e, broker not in path)
```

## Components

### 1. Per-user flux-rest-server (unprivileged, runs as the user)

A small HTTP server, an ordinary libflux client, run as a socket-activated
per-user systemd service (`flux-rest-server@USER.service`, `User=%i`):

- Parses HTTP/REST (incl. SSE/chunked for streaming). The whole parser is
  **unprivileged** — an exploit is confined to that one user's session.
- Opens `local://` for the system instance (guest role, automatic from
  `SO_PEERCRED`), and `ssh://` for the user's jobs (resolved via
  `flux uri --remote`).
- Must persist for a connection's lifetime (and idle-time-out across them) to
  serve streaming/keep-alive; a per-request spawn cannot.

Today this is read-only over `local://` (the endpoints below); SSE, `ssh://`
jobs, and submission are later phases.

### 2. Per-user activation (systemd + polkit — no custom privileged binary)

systemd performs the privileged `setuid` via a templated `User=%i` service;
**polkit** authorizes nginx to trigger it. (polkit is Linux's authorization
broker: systemd asks it whether a subject may perform an action; a narrow rule
grants exactly one.) So we ship only declarative config plus a tiny *unprivileged*
trigger:

- a `flux-rest-server@.socket` (per-user `/run/flux-rest-server/%i.sock`,
  `0660` group-restricted to the web-server account — `www-data` on Debian, set
  at build time via `--with-web-user`) and `@.service` (`User=%i`, inherits the
  socket, and passes `--allow-user` so the server also checks the peer's uid via
  `SO_PEERCRED`);
- a polkit rule letting the nginx user start *only* `flux-rest-server@*` units;
- an nginx `auth_request` helper that runs `systemctl start
  flux-rest-server@$remote_user.socket` (idempotent).

The privileged actor is **systemd** (already trusted); we add no setuid binary.
`$remote_user` flows into a socket path / unit name, so it **must be sanitized**
(reject `/`, `..`, non-username chars). Full unit/polkit/nginx files are in the
`systemd/`, `polkit/`, and `nginx/` directories. Alternatives if this doesn't fit:
`systemd --user` (needs
lingering), or a minimal custom `setuid` launcher (OnDemand `nginx_stage`).

### 3. Reaching the user's jobs over `ssh://`

Resolve a job to its `ssh://host/…socket` URI (as `flux proxy JOBID` does) and
open it. The `flux` broker is out of the data path; confidentiality/integrity
come from SSH host/user keys it cannot forge. Sub-instances are single-user
(owner only, no guests).

## Security

Everything we run is unprivileged and acts only as the authenticated user, so the
attack surface is essentially a CLI session's:

- **Per-user service / HTTP parser** — runs as the user, guest role; an exploit
  reaches only that user's own jobs. No cross-user reach, no escalation.
- **Connection access control** — the per-user socket is group-restricted to the
  web-server account (`0660 root:<web-user>`), and the server additionally
  verifies the peer's uid with `SO_PEERCRED` (`--allow-user`), so only the front
  end can connect even if the file mode were ever wrong. The standalone
  (non-activated) socket is owner-only.
- **Activation glue (nginx, trigger helper)** — unprivileged; polkit lets it
  start *only* `flux-rest-server@*` units. The real `setuid` is systemd's.
- **`flux` broker** — unprivileged; cannot `setuid`, read user keys, make the IMP
  launch without a user signature, or snoop/tamper `ssh://` job traffic.
- **web-user trust** — the `nginx` reverse proxy, and by extension its userid,
  is trusted to authenticate REST access to Flux.  Although this is a
  well established pattern, a compromised proxy or proxy user ID could
  be a pathway to privilege escalation in Flux.

## Site integration

```nginx
ssl_certificate     /etc/pki/tls/certs/site.crt;
ssl_certificate_key /etc/pki/tls/private/site.key;

# Site auth — pick one; must set $remote_user:
auth_gss on;                       # Kerberos
# ssl_verify_client on;            # mutual TLS
# auth_request /oauth2/auth;       # OAuth/OIDC

location /api/ {
    if ($remote_user !~ "^[a-z_][a-z0-9_-]*$") { return 403; }   # sanitize
    auth_request /_ensure;                       # start the user's socket
    set $sock /run/flux-rest-server/$remote_user.sock;
    proxy_pass http://unix:$sock:$request_uri;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
location = /_ensure {
    internal;
    proxy_pass http://unix:/run/flux-rest-server/ensure.sock;
    proxy_method GET;
    proxy_set_header X-Remote-User $remote_user;
}
```

Sites reuse their existing certs/auth/nginx; the deployment looks like Open
OnDemand.

## API endpoints

Under `/api/v1/`. Implemented today (read-only, `application/json`):

- `GET /` — instance info: `name`, `user` (the authenticated user the server
  runs as), `broker_version`, `rank`, `size`.
- `GET /health` — liveness; does not touch Flux.

Future: translation of all stable Flux RPC interfaces to REST.

## Implementation phases

1. **Per-user service** — standalone HTTP→RPC over `local://`, no privileged
   parts. (Implemented.)
2. **Per-user activation** — systemd units + polkit rule + `_ensure` helper +
   nginx. (Implemented.)
3. **Instance navigation** — resolve guest job URI, establish connection.
4. **API translation and documentation** — big design area here, completely TBD.
