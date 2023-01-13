(ns metabase.driver.ocient-unit-test
  (:require [clojure.test :refer :all]
            [metabase.driver.sql-jdbc.connection :as sql-jdbc.conn]
            [metabase.test :as mt]
            [metabase.test.data.sql.ddl :as ddl]
            [metabase.driver.ocient :as oc]
            [metabase.util.honeysql-extensions :as hx]))

(deftest connection-properties-test
  (mt/test-driver :ocient
                  (testing "Connection property details"
                  (testing " marshal additional options"
                    (is (= {:classname   "com.ocient.jdbc.JDBCDriver"
                            :subprotocol "ocient"
                            :statementPooling     "OFF"
                            :subname     "//sales-sql0:4050/metabase;loglevel=DEBUG;logfile=jdbc_trace.out"}
                           (sql-jdbc.conn/connection-details->spec :ocient {:host               "sales-sql0"
                                                                            :port               4050
                                                                            :db                 "metabase"
                                                                            :additional-options "loglevel=DEBUG;logfile=jdbc_trace.out"}))))
                  (testing " marshal Single Sign-On tokens (toggle)"
                    (is (= {:classname   "com.ocient.jdbc.JDBCDriver"
                            :subprotocol "ocient"
                            :statementPooling     "OFF"
                            :subname     "//sales-sql0:4050/metabase"
                            :handshake   "SSO"
                            :user        "access_token"
                            :password    "********"}
                           (sql-jdbc.conn/connection-details->spec :ocient {:host               "sales-sql0"
                                                                            :port               4050
                                                                            :db                 "metabase"
                                                                            :sso                true
                                                                            :token-type         "access_token"
                                                                            :token              "********"}))))
                  (testing " marshal Single Sign-On tokens (drop-down)"
                    (is (= {:classname   "com.ocient.jdbc.JDBCDriver"
                            :subprotocol "ocient"
                            :statementPooling     "OFF"
                            :subname     "//sales-sql0:4050/metabase"
                            :handshake   "SSO"
                            :user        "access_token"
                            :password    "********"}
                           (sql-jdbc.conn/connection-details->spec :ocient {:host               "sales-sql0"
                                                                            :port               4050
                                                                            :db                 "metabase"
                                                                            :authentication-method                "sso"
                                                                            :token-type         "access_token"
                                                                            :token              "********"}))))
                  (testing " strip trailing semicolon in additional options"
                    (is (= {:classname   "com.ocient.jdbc.JDBCDriver"
                            :subprotocol "ocient"
                            :statementPooling     "OFF"
                            :subname     "//sales-sql0:4050/metabase;loglevel=DEBUG"}
                           (sql-jdbc.conn/connection-details->spec :ocient {:host               "sales-sql0"
                                                                            :port               4050
                                                                            :db                 "metabase"
                                                                            :additional-options "loglevel=DEBUG;"})))))))

(deftest insert-rows-ddl-test
  (mt/test-driver :ocient
                  (testing "Make sure we're generating correct DDL for Ocient to insert all rows at once."
                    (is (= [[(str "INSERT INTO \"metabase\".\"my_table\""
                                  " SELECT ?, 1 UNION ALL"
                                  " SELECT ?, 2 UNION ALL"
                                  " SELECT ?, 3")
                             "A"
                             "B"
                             "C"]]
                           (ddl/insert-rows-ddl-statements :ocient (hx/identifier :table "my_db" "my_table") [{:col1 "A", :col2 1}
                                                                                                              {:col1 "B", :col2 2}
                                                                                                              {:col1 "C", :col2 3}]))))))

(deftest unescape-column-names-test
  (mt/test-driver :ocient
                  (testing "Make sure we unescape column names correctly "
                    (is (= {:fields (set (mapv #(hash-map :name %) ["0123"
                                                                    "\\123"
                                                                    "a(),.[]"
                                                                    "a23\\d"
                                                                    "[bc"
                                                                    "!bc"
                                                                    "b!c"
                                                                    "\\[bc"
                                                                    "abc"]))}
                            (oc/unescape-column-names {:fields (mapv #(hash-map :name %) ["\\0123"
                                                                                          "\\\\123"
                                                                                          "a\\(\\)\\,\\.\\[\\]"
                                                                                          "a23\\d"
                                                                                          "\\\\[bc"
                                                                                          "\\!bc"
                                                                                          "b!c"
                                                                                          "\\\\\\[bc"
                                                                                          "abc"])}))))))
