.SILENT: driver-version test-tarball-version metabase-version

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

# Build the Metabase container
build:
	DOCKER_BUILDKIT=1 docker build \
		-t metabase_ocient:$(METABASE_VERSION) \
		.

# Create and start the Metabase container
run: build
	DOCKER_BUILDKIT=1 docker run \
		--name metabase_ocient_$(METABASE_VERSION) \
		-d \
		-p 3000:3000 \
		metabase_ocient:$(METABASE_VERSION)

# Start the Metabase container
start:
	docker start metabase_ocient_$(METABASE_VERSION)

# Stop the Metabase container
stop:
	docker stop metabase_ocient_$(METABASE_VERSION)

# Delete the Metabase container
rm:
	docker rm metabase_ocient_$(METABASE_VERSION)

clean:
	rm -rf target
	docker stop metabase_ocient_$(METABASE_VERSION) || true
	docker rm metabase_ocient_$(METABASE_VERSION) || true

# Rebuild the driver and update the running metabase instance
update: driver
	docker cp target/ocient.metabase-driver.jar metabase_ocient_$(METABASE_VERSION):/plugins/
	docker restart metabase_ocient_$(METABASE_VERSION)
	docker restart metabase_ocient_$(METABASE_VERSION)

# Output the Ocient driver version
driver-version:
	echo $(METABASE_OCIENT_VERSION)

# Output the test archive
test-tarball-version:
	echo $(METABASE_TEST_TARBALL_VERSION)

# Output Metabase version
metabase-version:
	echo $(METABASE_VERSION)