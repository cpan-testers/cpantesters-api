FROM cpantesters/schema
# Load some modules that will always be required, to cut down on docker
# rebuild time
RUN --mount=type=cache,target=/root/.cpanm \
  cpanm -v --notest \
    Minion::Backend::mysql \
    Beam::Minion \
    Mojolicious \
    Mojolicious::Plugin::OAuth2 \
    Mojolicious::Plugin::Yancy
# Load last version's modules, to again cut down on rebuild time
COPY ./cpanfile /app/cpanfile
RUN --mount=type=cache,target=/root/.cpanm \
  cpanm -v --notest --installdeps .

COPY ./ /app
RUN --mount=type=cache,target=/root/.cpanm \
  dzil authordeps --missing | cpanm -v --notest && \
  dzil listdeps --missing | cpanm -v --notest && \
  dzil install --install-command "cpanm -v --notest ."

ENV MOJO_HOME=/app \
    BEAM_MINION='mysql+dsn+dbi:MariaDB:mariadb_read_default_file=/root/.cpanstats.cnf;mariadb_read_default_group=application' \
    MOJO_PUBSUB_EXPERIMENTAL=1 \
    MOJO_MAX_MESSAGE_SIZE=33554432
CMD [ "cpantesters-api", "daemon", "-l", "http://*:3000" ]
EXPOSE 3000
