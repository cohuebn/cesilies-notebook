FROM liquibase/liquibase

ARG cockroachVersion
ARG changelogPath

# Install the cockroach CLI
USER root
RUN wget -qO- https://binaries.cockroachdb.com/cockroach-v${cockroachVersion}.linux-amd64.tgz | tar xvz
RUN cp -i cockroach-v${cockroachVersion}.linux-amd64/cockroach /usr/bin/
RUN mkdir /liquibase/certs
RUN chown -R liquibase /liquibase/certs

USER liquibase