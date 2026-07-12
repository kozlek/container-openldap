#!/usr/bin/env bash
#
# Bootstrap and run OpenLDAP (slapd) on Debian.
#
# On first run (empty /etc/ldap/slapd.d) the directory is configured from
# environment variables: the suffix is derived from LDAP_DOMAIN, the admin
# account is cn=admin,<suffix>, and an optional read-only bind account is
# created. On subsequent runs slapd is started directly against the persisted
# configuration and data volumes.
#
set -euo pipefail

log() { echo "[entrypoint] $*"; }

CONFIG_DIR=/etc/ldap/slapd.d
DATA_DIR=/var/lib/ldap
RUN_DIR=/run/slapd

: "${LDAP_DOMAIN:?LDAP_DOMAIN is required (e.g. example.com)}"
: "${LDAP_ADMIN_PASSWORD:?LDAP_ADMIN_PASSWORD is required}"
LDAP_ORGANISATION="${LDAP_ORGANISATION:-${LDAP_DOMAIN}}"
# slapd log level; 256 = connection/operation stats. See slapd.conf(5) loglevel.
LDAP_LOG_LEVEL="${LDAP_LOG_LEVEL:-256}"

# Derive the base DN from the domain: example.com -> dc=example,dc=com
base_dn=""
IFS='.' read -ra _parts <<< "${LDAP_DOMAIN}"
for _p in "${_parts[@]}"; do
  base_dn="${base_dn}${base_dn:+,}dc=${_p}"
done
admin_dn="cn=admin,${base_dn}"

mkdir -p "${RUN_DIR}"
chown openldap:openldap "${RUN_DIR}"

# Start a local (ldapi:// only) slapd for bootstrap operations.
start_slapd_local() {
  slapd -h "ldapi:///" -u openldap -g openldap
  local i
  for i in $(seq 1 50); do
    if ldapsearch -Q -Y EXTERNAL -H ldapi:/// -b "" -s base >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  log "ERROR: slapd did not become ready"
  return 1
}

stop_slapd_local() {
  local pid i
  pid="$(cat "${RUN_DIR}/slapd.pid" 2>/dev/null || true)"
  if [ -n "${pid}" ]; then
    kill "${pid}" 2>/dev/null || true
  else
    pkill -x slapd 2>/dev/null || true
  fi
  for i in $(seq 1 50); do
    pgrep -x slapd >/dev/null 2>&1 || return 0
    sleep 0.2
  done
}

if [ -z "$(ls -A "${CONFIG_DIR}" 2>/dev/null || true)" ]; then
  log "First run: configuring slapd for ${base_dn} (organisation: ${LDAP_ORGANISATION})"

  mkdir -p "${CONFIG_DIR}" "${DATA_DIR}"
  chown openldap:openldap "${CONFIG_DIR}" "${DATA_DIR}"

  debconf-set-selections <<EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORGANISATION}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/backend select MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
EOF

  dpkg-reconfigure -f noninteractive slapd

  log "Starting slapd locally to apply bootstrap entries"
  start_slapd_local

  # Optional read-only bind account. It is a plain (non-admin) entry, so the
  # default ACLs already make it read-only: only cn=admin can write.
  if [ -n "${LDAP_READONLY_USER:-}" ] && [ -n "${LDAP_READONLY_PASSWORD:-}" ]; then
    log "Creating read-only bind account cn=${LDAP_READONLY_USER},${base_dn}"
    ro_hash="$(slappasswd -s "${LDAP_READONLY_PASSWORD}")"
    ldapadd -x -H ldapi:/// -D "${admin_dn}" -w "${LDAP_ADMIN_PASSWORD}" <<EOF
dn: cn=${LDAP_READONLY_USER},${base_dn}
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: ${LDAP_READONLY_USER}
description: Read-only bind account for LDAP-only clients
userPassword: ${ro_hash}
EOF
  fi

  stop_slapd_local
  log "Bootstrap complete"
else
  log "Existing configuration found; starting against persisted data"
fi

log "Starting slapd (suffix: ${base_dn}, log level: ${LDAP_LOG_LEVEL})"
exec slapd -h "ldap://0.0.0.0:389/ ldapi:///" -u openldap -g openldap -d "${LDAP_LOG_LEVEL}"
