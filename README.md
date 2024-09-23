# Metabase Ocient Driver

💥*Note:* This project is under active development

## Installation
There are a few options to installing a Metabase community driver. The simplest is to copy the JAR file into the plugins directory in your Metabase directory (the directory where you run the Metabase JAR). Additionally, you can change the location of the plugins directory by setting the environment variable `MB_PLUGINS_DIR`.

### Docker
Use the [`Dockerfile`](./Dockerfile) to build an image of Metabase with the Ocient driver pre-installed:
```shell
git clone git@github.com:Xeograph/metabase-ocient-driver.git
cd metabase-ocient-driver
git submodule update --init
make docker-build
```

### Use custom Metabase JAR
If you already have a Metabase binary release (see [Metabase distribution page](https://metabase.com/start/jar.html)):

1. Download the Ocient driver jar from this repository's ["Releases"](https://github.com/Xeograph/metabase-ocient-driver/releases) page.
2. Create a directory and copy the `metabase.jar` to it.
3. In that directory create a sub-directory called `plugins` and copy the Ocient driver jar into it.
4. From the directory created in step 2, run `java -jar metabase.jar`.

## Contributing

### Prerequisites

- java >= 8
- [Leiningen](https://leiningen.org/)
- [Install metabase-core](https://github.com/metabase/metabase/wiki/Writing-a-Driver:-Packaging-a-Driver-&-Metabase-Plugin-Basics#installing-metabase-core-locally)

### Build from source

The Ocient driver, can be built using [`Clouure Tools`](https://clojure.org/releases/tools):

```shell
# Outputs jar to `plugins/ocient.metabase-driver.jar`. Should be run from the project's root directory, NOT the metabase subrepo
make build
```

^ TODO: this should go to `metabase/plugins/<whatever>`

### Run a local Metabase instance
To run a local instance of Metabase, run:

```shell
make run
```

This really should be `cd metabase` and `clojure -M:run`.
Also probably need to migrate away from Leiningen (haven't tested yet) - see dep prep in https://github.com/metabase/metabase/wiki/Migrating-from-Leiningen-to-tools.deps

I have only tested this after building the driver:
clojure -X:deps prep 
cd modules/drivers
clojure -X:deps prep
cd ../..

For the front-end, you also should use whatever node version was LTS _at the time of whatever metabase version is being used_. Right now, that is 16.16.0.

For the front-end: `yarn build-hot` (hot reloading enabled)

### Run unit tests
To run the unit tests against the Ocient driver, run:

```shell
make run-unit-test
```
