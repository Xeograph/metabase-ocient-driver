# Latest commit hash
GIT_SHA=$(shell git rev-parse HEAD)
GIT_DIRTY=$(shell (git diff -s --exit-code && echo 0) || echo 1)
GIT_USER_EMAIL=$(shell git config user.email)
GIT_USER_NAME=$(shell git config user.name)

METABASE_VERSION=$(shell cat metabase_version.txt)

# Extract the driver version from the plugin manifest
METABASE_OCIENT_VERSION=$(shell grep -o "version: .*" resources/metabase-plugin.yaml | cut -c 10-)

# Extract the tarball version from the .txt file
METABASE_TEST_TARBALL_VERSION=$(shell cat metabase_test_tarball_version.txt)

# Builds the Metabase Ocient driver. A single JAR executable
driver:
	DOCKER_BUILDKIT=1 docker build \
		--build-arg METABASE_VERSION="$(METABASE_VERSION)" \
		--output target \
		--target stg_driver_export \
		-t metabase_ocient_driver:$(METABASE_OCIENT_VERSION) \
		.

# Builds the test tarball which can be deployed in environments with JAVA installed
test-tarball:
	DOCKER_BUILDKIT=1 docker build \
		--build-arg GIT_SHA="$(GIT_SHA)" \
		--build-arg GIT_DIRTY=$(GIT_DIRTY) \
		--build-arg GIT_USER_EMAIL="$(GIT_USER_EMAIL)" \
		--build-arg GIT_USER_NAME="$(GIT_USER_NAME)" \
		--build-arg METABASE_VERSION="$(METABASE_VERSION)" \
		--build-arg METABASE_OCIENT_VERSION="$(METABASE_OCIENT_VERSION)" \
		--build-arg METABASE_TEST_TARBALL_VERSION="$(METABASE_TEST_TARBALL_VERSION)" \
		--output target \
		--target stg_test_tarball_export \
		 -t metabase_test_tarball:$(METABASE_TEST_TARBALL_VERSION) \
		.

build:
	DOCKER_BUILDKIT=1 docker build \
		-t metabase_ocient:$(METABASE_VERSION) \
		.

run: build
	DOCKER_BUILDKIT=1 docker run \
		--name metabase_ocient_$(METABASE_VERSION) \
		--rm \
		-d \
		-p 3000:3000 \
		metabase_ocient:$(METABASE_VERSION)

