ARG METABASE_VERSION=v0.44.4
ARG METABASE_EDITION=oss

#################
# Metabase repo #
#################
FROM clojure:openjdk-11-tools-deps-slim-buster AS stg_base

ARG METABASE_EDITION
ARG METABASE_VERSION

# Reequirements for building the driver
RUN apt-get update \
    && apt-get install -y \
    curl \
    jq \
    make \
    npm \
    unzip \
    && curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
    && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g yarn

# Set our base workdir
WORKDIR /build

# Initialize Metabase submodule
RUN git init \
    && git submodule add https://github.com/metabase/metabase.git \
    && git submodule init

WORKDIR /build/metabase
RUN git checkout $(curl -s -H "Accept: application/vnd.github+json" https://api.github.com/repos/metabase/metabase/git/ref/tags/${METABASE_VERSION} | jq .object.sha | xargs echo)

# Then prep our Metabase dependencies
# We need to build java deps
# Ref: https://github.com/metabase/metabase/wiki/Migrating-from-Leiningen-to-tools.deps#preparing-dependencies
RUN --mount=type=cache,target=/root/.m2/repository \
    clojure -X:deps prep

WORKDIR /build/metabase/bin
RUN --mount=type=cache,target=/root/.m2/repository \
    clojure -X:deps prep


WORKDIR /build

################
# Driver stage #
################
FROM stg_base AS stg_driver

COPY deps.edn ./
COPY resources ./resources
COPY src ./src

RUN --mount=type=cache,target=/root/.m2/repository \
    clojure -X:deps prep


##############
# Test stage #
##############
FROM stg_driver as stg_unit_test

COPY test ./

# Run the unit tests
RUN --mount=type=cache,target=/root/.m2/repository \
    CI=true \
    DRIVERS=ocient \
    clojure -X:dev:unit-test \
    :project-dir "\"$(pwd)\""


###############
# Build stage #
###############
FROM stg_unit_test as stg_build

RUN --mount=type=cache,target=/root/.m2/repository \
    clojure -X:build:deps prep \
    :project-dir "\"$(pwd)\""

# Then build the driver
RUN clojure -X:build \
    :project-dir "\"$(pwd)\"" \
    :target-dir  "./target" \
    -v 100


############################
# Export the Ocient driver #
############################
FROM scratch as stg_export
COPY --from=stg_build /build/target/ocient.metabase-driver.jar /


####################
# Test build stage #
####################
FROM stg_base as stg_test_uberjar

ARG METABASE_EDITION

WORKDIR /build/metabase

COPY deps.edn /build/metabase/modules/drivers/ocient/
COPY src/ /build/metabase/modules/drivers/ocient/
COPY resources/metabase-plugin.yaml /build/metabase/modules/drivers/ocient/resources/
COPY test/ /build/metabase/modules/drivers/ocient/

# FIXME Can we get rid of the patch here and build an uberjar via clojure???
COPY patches/test-tarball.patch /build/
RUN git apply /build/test-tarball.patch

RUN --mount=type=cache,target=/root/.m2/repository \
    clojure -X:test:deps prep

ENV CI=true
ENV INTERACTIVE=false
ENV MB_EDITION=${METABASE_EDITION}

# Build frontend (needs to run for some frontend tests)
RUN --mount=type=cache,target=/root/.m2/repository \
    yarn build && \
    yarn build-static-viz

# Build the uberjar
RUN --mount=type=cache,target=/root/.m2/repository \ 
    clojure -T:dev:build uberjar


######################
# Test tarball stage #
######################
FROM stg_test_uberjar as stg_test_tarball

ARG GIT_SHA
ARG GIT_USER_NAME
ARG GIT_USER_EMAIL
ARG GIT_DIRTY
ARG METABASE_VERSION
ARG METABASE_OCIENT_VERSION
ARG METABASE_TEST_TARBALL_VERSION
ARG TARBALL_NAME=metabase_test_${METABASE_TEST_TARBALL_VERSION} 

WORKDIR /build

# Place uberjar and remaining deps in a directory named "metabase_test" and tarball it
RUN mv metabase/target/uberjar/metabase.jar metabase/ \
    && mv metabase metabase_test \
    && echo "{"\
            "\"time\": \"$(date -u +"%Y-%m-%dT%T")\""\
            ", \"git_sha\": \"${GIT_SHA}\""\
            ", \"git_user_name\": \"${GIT_USER_NAME}\""\
            ", \"git_user_email\": \"${GIT_USER_EMAIL}\""\
            ", \"git_dirty\": \"${GIT_DIRTY}\""\
            ", \"metabase_version\": \"${METABASE_VERSION}\""\
            ", \"metabase_ocient_version\": \"${METABASE_OCIENT_VERSION}\""\
            ", \"metabase_test_tarball_version\": \"${METABASE_TEST_TARBALL_VERSION}\""\
            "}" > metabase_test/build_info.json \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/build_info.json \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/metabase.jar \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/test_modules/drivers/secret-test-driver/resources/metabase-plugin.yaml \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/test_modules/drivers/driver-deprecation-test-new/resources/metabase-plugin.yaml \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/test_modules/drivers/driver-deprecation-test-legacy/resources/metabase-plugin.yaml \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/README.md \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/frontend/test/__runner__/test_db_fixture.db.mv.db \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/frontend/test/__runner__/empty.db.mv.db \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/test_resources/* \
    && tar rvf metabase_test/target/${TARBALL_NAME}.tar metabase_test/test/metabase/test/data/dataset_definitions/*.edn \
    && gzip metabase_test/target/${TARBALL_NAME}.tar


#############################
# Test Tarball Export stage #
#############################
FROM scratch as stg_test_tarball_export

ARG METABASE_TEST_TARBALL_VERSION
ARG TARBALL_NAME=metabase_test_${METABASE_TEST_TARBALL_VERSION}

COPY --from=stg_test_tarball  /build/metabase_test/target/${TARBALL_NAME}.tar.gz /


################
# Run Metabase #
################
FROM metabase/metabase:${METABASE_VERSION} AS stg_runner

COPY resources/log4j2.xml /var/log/log4j2.xml

ENV LOG4J_CONFIGURATION_FILE=/var/log/log4j2.xml

# A metabase user/group is manually added in https://github.com/metabase/metabase/blob/master/bin/docker/run_metabase.sh
# Make the UID and GID match
COPY --chown=2000:2000 --from=stg_export \
    /ocient.metabase-driver.jar \
    /plugins/ocient.metabase-driver.jar