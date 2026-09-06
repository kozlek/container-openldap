# container-openldap

A minimal, self-maintained [OpenLDAP](https://www.openldap.org) (`slapd`) image
built on `debian:trixie-slim`.

## Design

- Nothing environment-specific is baked into the image. The suffix, admin
  password and directory data are all supplied at **runtime**.
- On first run the entrypoint configures `slapd` from the environment (Debian's
  own `dpkg-reconfigure` generates a correct `cn=config` + `mdb` database) and
  creates an optional read-only bind account.
- On later runs it simply starts `slapd` against the persisted volumes.

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `LDAP_DOMAIN` | yes | — | DNS domain; the base DN is derived from it (`example.com` → `dc=example,dc=com`). |
| `LDAP_ADMIN_PASSWORD` | yes | — | Password for `cn=admin,<base DN>`. |
| `LDAP_ORGANISATION` | no | `LDAP_DOMAIN` | Organisation name for the base entry. |
| `LDAP_READONLY_USER` | no | — | If set (with the password), create `cn=<user>,<base DN>` as a read-only bind account. |
| `LDAP_READONLY_PASSWORD` | no | — | Password for the read-only account. |
| `LDAP_LOG_LEVEL` | no | `256` | `slapd` log level (see `slapd.conf(5)`). |

## Volumes

| Path | Purpose |
|---|---|
| `/etc/ldap/slapd.d` | `cn=config` (dynamic configuration) |
| `/var/lib/ldap` | `mdb` database (directory data) |

## Ports

`389/tcp` — plaintext LDAP, intended for a private container network.

## Example

```bash
docker run -d --name openldap \
  -e LDAP_DOMAIN=example.com \
  -e LDAP_ADMIN_PASSWORD=change-me \
  -e LDAP_READONLY_USER=readonly \
  -e LDAP_READONLY_PASSWORD=change-me-too \
  -v openldap-config:/etc/ldap/slapd.d \
  -v openldap-data:/var/lib/ldap \
  -p 389:389 \
  ghcr.io/kozlek/openldap:latest
```

## Tags

Images are published to `ghcr.io/kozlek/openldap`. The tag encodes the bundled
OpenLDAP version, and — for releases — the semver release it was cut from:

| Tag | Example | Meaning |
|---|---|---|
| `<openldap>-<release>` | `2.6.10-1.0.0` | Immutable: a specific release build. Pin this. |
| `<openldap>` | `2.6.10` | Floating: newest build of that OpenLDAP version. |
| `<major.minor>` | `2.6` | Floating: newest build of that OpenLDAP minor. |
| `latest` | — | Floating: newest build overall. |

### OpenLDAP version policy

The OpenLDAP version is **not pinned in this repo** — it is whatever `slapd`
Debian trixie ships, and the build workflow reads it back out of the image with
`dpkg-query` to compute the tags. So the `<openldap>` token tracks Debian
stable, not upstream: trixie has shipped `2.6.10+dfsg-1` since its release and
Debian only rebases OpenLDAP in a new stable (forky currently carries 2.6.14),
backporting security fixes into 2.6.10 in place if any warrant it.

A newer upstream 2.6.x therefore does *not* mean this image is behind on
security fixes. Cutting a release rebuilds against a refreshed base image and
`trixie-security`, which is what picks up patches; the `<openldap>` token only
moves when Debian moves.

## Importing existing data

To load an existing directory, export it to LDIF (entries and `userPassword`
hashes, without operational attributes) and import it into the running container
with `ldapadd`:

```bash
docker exec -i openldap \
  ldapadd -x -D "cn=admin,<base DN>" -w "<admin password>" < export.ldif
```

When importing from another OpenLDAP server, `userPassword` hashes are carried
over verbatim — no password resets.

## Status

New and not yet battle-tested — build and validate before relying on it.

## License

MIT — see [LICENSE](LICENSE).
