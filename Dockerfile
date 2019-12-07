FROM cpantesters/schema
# Load some modules that will always be required, to cut down on docker
# rebuild time
RUN cpanm -v \
    Minion::Backend::mysql \
    Beam::Minion \
    Mojolicious \
    Mojolicious::Plugin::OAuth2 \
    Mojolicious::Plugin::Yancy
# Load last version's modules, to again cut down on rebuild time
COPY ./cpanfile ./cpanfile
RUN cpanm --installdeps .

COPY ./ ./
RUN dzil authordeps --missing | cpanm -v --notest
RUN dzil listdeps --missing | cpanm -v --notest
RUN ls .git
RUN dzil install --install-command "cpanm -v ."

COPY ./etc/docker/api/my.cnf ./.cpanstats.cnf
COPY ./etc/docker/api/api.development.conf ./
ENV MOJO_HOME=./
CMD [ "cpantesters-api", "daemon", "-l", "http://*:4000" ]
EXPOSE 4000
