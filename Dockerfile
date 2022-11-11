ARG METABASE_VERSION=v0.44.4
ARG METABASE_OCIENT_VERSION=v0.1.0-rc.2
ARG MB_OCIENT_TEST_HOST=172.17.0.1
ARG MB_OCIENT_TEST_PORT=4050


#################
# Metabase repo #
#################
FROM clojure:openjdk-11-tools-deps-slim-buster AS stg_base

# Reequirements for building the driver
RUN apt-get update && \
    apt-get install -y \
    curl \
    make \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set our base workdir
WORKDIR /build

# We need to retrieve metabase source
# Due to how ARG and FROM interact, we need to re-use the same ARG
# Ref: https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact
ARG METABASE_VERSION
RUN curl -Lo - https://github.com/metabase/metabase/archive/refs/tags/${METABASE_VERSION}.tar.gz | tar -xz \
    && mv metabase-* metabase

WORKDIR /build/metabase

######################################
# Base stage with Ocient driver deps #
######################################
FROM stg_base as stg_driver

# Copy our project assets over
COPY deps.edn /build/metabase/modules/drivers/ocient/
COPY src/ /build/metabase/modules/drivers/ocient/src
COPY resources/ /build/metabase/modules/drivers/ocient/resources

# Link any Ocient deps required to build or test the driver
COPY patches/ocient-driver.patch /build/
RUN git apply /build/ocient-driver.patch

# Then prep our Metabase dependencies
# We need to build java deps
# Ref: https://github.com/metabase/metabase/wiki/Migrating-from-Leiningen-to-tools.deps#preparing-dependencies
RUN --mount=type=cache,target=/root/.m2/repository \
    clojure -X:deps prep


###########################
# Build the Ocient driver #
###########################
FROM stg_driver as stg_driver_build

RUN --mount=type=cache,target=/root/.m2/repository \
    bin/build-driver.sh ocient


###########################
# Test the Ocient driver #
###########################
FROM stg_driver as stg_driver_test

ARG MB_OCIENT_TEST_HOST
ARG MB_OCIENT_TEST_PORT
COPY test/ /build/metabase/modules/drivers/ocient/test
COPY --from=stg_driver_build /build/metabase/resources/modules/ocient.metabase-driver.jar /build/metabase/plugins/
RUN clojure -X:test:deps prep
# Some dependencies still get downloaded when the command below is run, but I'm not sure why

ENV MB_OCIENT_TEST_HOST=${MB_OCIENT_TEST_HOST}
ENV MB_OCIENT_TEST_PORT=${MB_OCIENT_TEST_PORT}
ENV DRIVERS=ocient
CMD ["clojure", "-X:dev:drivers:drivers-dev:test", ":only", "metabase.driver.ocient-unit-test"]


############################
# Export the Ocient driver #
############################
FROM scratch as stg_driver_export
COPY --from=stg_driver_build /build/metabase/resources/modules/ocient.metabase-driver.jar /


######################
# Test tarball stage #
######################
FROM stg_base as stg_test_tarball

COPY test/ /build/metabase/modules/drivers/ocient/test
COPY patches/test-tarball.patch /build/
RUN git apply /build/test-tarball.patch

# Build the uberjar
RUN --mount=type=cache,target=/root/.m2/repository \ 
    clojure -T:dev:build uberjar

WORKDIR /build

# Place uberjar and remaining deps in a tarball
RUN mv metabase/target/uberjar/metabase.jar metabase/ \
    && mv metabase metabase_test \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/metabase.jar \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/test_modules/drivers/secret-test-driver/resources/metabase-plugin.yaml \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/test_modules/drivers/driver-deprecation-test-new/resources/metabase-plugin.yaml \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/test_modules/drivers/driver-deprecation-test-legacy/resources/metabase-plugin.yaml \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/README.md \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/frontend/test/__runner__/test_db_fixture.db.mv.db \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/frontend/test/__runner__/empty.db.mv.db \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/test_resources/* \
    && tar rvf metabase_test/target/metabase_test.tar metabase_test/test/metabase/test/data/dataset_definitions/*.edn \
    && gzip metabase_test/target/metabase_test.tar


#############################
# Test Tarball Export stage #
#############################
FROM scratch as stg_test_tarball_export
COPY --from=stg_test_tarball /build/metabase_test/target/metabase_test.tar.gz /


################
# Run Metabase #
################
FROM metabase/metabase:${METABASE_VERSION} AS stg_runner

# A metabase user/group is manually added in https://github.com/metabase/metabase/blob/master/bin/docker/run_metabase.sh
# Make the UID and GID match
COPY --chown=2000:2000 --from=stg_driver_build \
    /build/metabase/resources/modules/ocient.metabase-driver.jar \
    /plugins/ocient.metabase-driver.jar