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
# Outputs jar to `plugins/ocient.metabase-driver.jar` 
make build
```

### Run a local Metabase instance
To run a local instance of Metabase, run:

```shell
make run
```

### Run unit tests
To run the unit tests against the Ocient driver, run:

```shell
make run-unit-test
```
