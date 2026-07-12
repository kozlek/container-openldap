# syntax=docker/dockerfile:1
FROM debian:trixie-slim

LABEL org.opencontainers.image.title="openldap" \
      org.opencontainers.image.description="Minimal, self-maintained OpenLDAP (slapd) on Debian trixie" \
      org.opencontainers.image.source="https://github.com/kozlek/container-openldap" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

# Prevent maintainer scripts from starting services during (re)configuration.
# In a container there is no init system; slapd is started by the entrypoint.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
 && chmod +x /usr/sbin/policy-rc.d

# Install slapd but DO NOT configure it at build time: the directory suffix,
# admin password and data are all provided at runtime via environment
# variables, so nothing sensitive or environment-specific is baked into the
# image. The pre-created config/database is removed so first-run bootstrap is
# deterministic.
RUN echo "slapd slapd/no_configuration boolean true" | debconf-set-selections \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      slapd \
      ldap-utils \
      libsasl2-modules \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# LDAP (plaintext, intended for a private container network)
EXPOSE 389

# Persist both the configuration (cn=config) and the data (mdb backend)
VOLUME ["/etc/ldap/slapd.d", "/var/lib/ldap"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["slapd"]
