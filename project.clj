(defproject metabase/ocient-driver "v0.1.0-rc.4"
  :min-lein-version "2.5.0"

  :repositories {"project" "file:repo"}

  :profiles
  {:provided
   {:dependencies
    [[metabase-core "1.0.0-SNAPSHOT"]
     [clojure.java-time "0.3.1"]]}

   :uberjar
   {:auto-clean    true
    :aot           :all
    :javac-options ["-target" "1.8", "-source" "1.8"]
    :target-path   "target/%s"
    :uberjar-name  "ocient.metabase-driver.jar"}})