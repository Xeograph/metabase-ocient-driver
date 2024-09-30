.SILENT: install driver-version test-tarball-version metabase-version

# Latest commit hash
GIT_SHA=$(shell git rev-parse HEAD)
GIT_DIRTY=$(shell (git diff -s --exit-code && echo 0) || echo 1)
GIT_USER_EMAIL=$(shell git config user.email)
GIT_USER_NAME=$(shell git config user.name)

METABASE_VERSION=$(shell echo `cd metabase; git describe --tags;`)

# Extract the driver version from the plugin manifest
METABASE_OCIENT_VERSION=$(shell grep -o "version: .*" resources/metabase-plugin.yaml | cut -c 10-)

# Extract the tarball version from the .txt file
METABASE_TEST_TARBALL_VERSION=$(shell cat metabase_test_tarball_version.txt)

install:
	git submodule update --init

# Builds the Metabase Ocient driver. A single JAR executable
build:
	cd metabase && clojure \
		-Sdeps "{:aliases {:ocient {:extra-deps {com.metabase/ocient-driver {:local/root \"$(shell pwd)\"} javax.activation/javax.activation-api {:mvn/version \"1.2.0\"}}}}}" \
		-X:build:ocient \
		build-drivers.build-driver/build-driver! \
		"{:driver :ocient, :project-dir \"$(shell pwd)\", :target-dir \"$(shell pwd)/metabase/plugins\", :extra-paths [\"src\" \"resources\"]}"

# Run Metabase
run:
	cd metabase && clojure -M:run > $(shell pwd)/metabase.log 2>&1 &

# Run Ocient unit tests
run-unit-test:
	cd metabase && DRIVERS=ocient clojure -Sdeps "{:deps {com.metabase/ocient-driver {:local/root \"$(shell pwd)\"} ocient/ocient-driver-tests {:local/root \"$(shell pwd)/test\"}}}" \
	-X:dev:drivers:drivers-dev:test :only metabase.driver.ocient-unit-test

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

# Build the Metabase container
docker-build:
	DOCKER_BUILDKIT=1 docker build \
		-t metabase_ocient:$(METABASE_VERSION) \
		.

# Output the Ocient driver version
driver-version:
	echo $(METABASE_OCIENT_VERSION)

# Output the test archive
test-tarball-version:
	echo $(METABASE_TEST_TARBALL_VERSION)

# Output Metabase version
metabase-version:
	echo $(METABASE_VERSION)