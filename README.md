# Metabase Ocient Driver

💥*Note:* This project is under active development

## Installation
There are a few options to installing a Metabase community driver. The simplest is to copy the JAR file into the plugins directory in your Metabase directory (the directory where you run the Metabase JAR). Additionally, you can change the location of the plugins directory by setting the environment variable `MB_PLUGINS_DIR`.

### Docker
Use the [`Dockerfile`](./Dockerfile) to build the Ocient diver and run the most recent supported version of Metabase:
```shell
git clone git@github.com:Xeograph/metabase-ocient-driver.git
cd metabase-ocient-driver
make run
```

### Use custom Metabase JAR
If you already have a Metabase binary release (see [Metabase distribution page](https://metabase.com/start/jar.html)):

1. Download the Ocient driver jar from this repository's ["Releases"](https://github.com/dacort/metabase-ocient-driver/releases) page.
2. Create a directory and copy the `metabase.jar` to it.
3. In that directory create a sub-directory called `plugins` and copy the Ocient driver jar into it.
4. From the directory created in step 2, run `java -jar metabase.jar`.

## Contributing

### Prerequisites

- java >= 8
- [Leiningen](https://leiningen.org/)
- [Install metabase-core](https://github.com/metabase/metabase/wiki/Writing-a-Driver:-Packaging-a-Driver-&-Metabase-Plugin-Basics#installing-metabase-core-locally)

### Build from source

The entire Metabase JAR, including the Ocient driver, can be built using the provided [`Dockerfile`](./Dockerfile).

Build the image and copy the jar from the export stage.

```shell
# Outputs jar to `target/ocient.metabase-driver.jar` 
make driver
```
