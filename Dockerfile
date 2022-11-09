ARG METABASE_VERSION=v0.44.4
ARG MB_OCIENT_TEST_HOST=172.17.0.1
ARG MB_OCIENT_TEST_PORT=4050

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

# Copy our project assets over
COPY deps.edn /build/metabase/modules/drivers/ocient/
COPY src/ /build/metabase/modules/drivers/ocient/src
COPY resources/ /build/metabase/modules/drivers/ocient/resources

WORKDIR /build/metabase
COPY ocient.patch /build/

# Link any Ocient deps required to build or test the driver
RUN git apply /build/ocient.patch

# Then prep our Metabase dependencies
# We need to build java deps
# Ref: https://github.com/metabase/metabase/wiki/Migrating-from-Leiningen-to-tools.deps#preparing-dependencies
RUN --mount=type=cache,target=/root/.m2/repository \
    clojure -X:deps prep

# Now build the driver
FROM stg_base as stg_build
RUN --mount=type=cache,target=/root/.m2/repository \
    bin/build-driver.sh ocient

# Test stage
FROM stg_build as stg_test
ARG MB_OCIENT_TEST_HOST
ARG MB_OCIENT_TEST_PORT
COPY test/ /build/metabase/modules/drivers/ocient/test
COPY --from=stg_build /build/metabase/resources/modules/ocient.metabase-driver.jar /build/metabase/plugins/
RUN clojure -X:test:deps prep
# Some dependencies still get downloaded when the command below is run, but I'm not sure why

ENV MB_OCIENT_TEST_HOST=${MB_OCIENT_TEST_HOST}
ENV MB_OCIENT_TEST_PORT=${MB_OCIENT_TEST_PORT}
ENV DRIVERS=ocient
CMD ["clojure", "-X:dev:drivers:drivers-dev:test", ":only", "metabase.driver.ocient-unit-test"]

# We create an export stage to make it easy to export the driver
FROM scratch as stg_export
COPY --from=stg_build /build/metabase/resources/modules/ocient.metabase-driver.jar /

# Now we can run Metabase with our built driver
FROM metabase/metabase:${METABASE_VERSION} AS stg_runner

# A metabase user/group is manually added in https://github.com/metabase/metabase/blob/master/bin/docker/run_metabase.sh
# Make the UID and GID match
COPY --chown=2000:2000 --from=stg_build \
    /build/metabase/resources/modules/ocient.metabase-driver.jar \
    /plugins/ocient.metabase-driver.jar