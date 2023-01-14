(ns metabase.driver.ocient
  "Metabase Ocient Driver."
  (:require [clojure
             [set :as set]
             [string :as str]
             [core :as core]]
            [clojure.tools.logging :as log]
            [honeysql.core :as hsql]
            [honeysql.format :as hformat]
            [java-time :as t]
            [metabase.config :as config]
            [metabase.driver :as driver]
            [metabase.driver.common :as driver.common]
            [metabase.driver.sql-jdbc
             [common :as sql-jdbc.common]
             [connection :as sql-jdbc.conn]
             [execute :as sql-jdbc.execute]
             [sync :as sql-jdbc.sync]]
            [metabase.driver.sql.query-processor :as sql.qp]
            [metabase.driver.sql.util.unprepare :as unprepare]
            [metabase.util
             [date-2 :as u.date]
             [honeysql-extensions :as hx]]
            [metabase.util :as u]
            [metabase.util.i18n :refer [deferred-tru trs tru]])

  (:import [java.sql PreparedStatement Types]
           [java.time LocalTime OffsetDateTime ZonedDateTime Instant OffsetTime ZoneId]
           [java.util Calendar TimeZone]))

; ;;; +----------------------------------------------------------------------------------------------------------------+
; ;;; |                                         metabase.driver impls                                                  |
; ;;; +----------------------------------------------------------------------------------------------------------------+

(driver/register! :ocient, :parent :sql-jdbc)

(defmethod driver/display-name :ocient [_] "Ocient")

(defmethod driver/db-default-timezone :ocient [_ _]
  ;; Ocient is always in UTC
  "UTC")

(defmethod driver/db-start-of-week :ocient
  [_]
  ;; From the Ocient user docs for WEEK()
  ;;
  ;; The ISO-8601 week number that the timestamp / day is in. 
  ;; The week starts on Monday and the first week of a year contains 
  ;; January 4 of that year. See https://en.wikipedia.org/wiki/ISO_week_date 
  ;; for more details.
  :monday)

(defmethod driver/connection-properties :ocient
  [_]
  ;; TODO 
  ;;
  ;; Metabase doesn't allow lazily loaded drivers to define connection
  ;; properties outside of the plugin manifest. This wouldn't be a problem,
  ;; but Metabase also prevents the :select property type from being used
  ;; via linter check. Is there a way around this?
  (->>
   [driver.common/default-host-details
    (assoc driver.common/default-port-details :placeholder 4050)
    driver.common/default-dbname-details
    {:name "schema-filters"
     :type :schema-filters
     :display-name "Schemas"}
    {:name "authentication-method"
     :display-name (trs "The authentication method used to connect to the database")
     :type :select
     :options [{:name "Password"
                :value "password"}
               {:name "Single Sign-On (Token)"
                :value "sso_token"}]
     :default "password"
     :placeholder "password"
     :required true}
    {:name "token-type"
     :display-name (trs "The type of the Single Sign-On token")
     :type :select
     :options [{:name "access_token"
                :value "access_token"}
               {:name "id_token"
                :value "id_token"}]
     :default "access_token"
     :placeholder "access_token"
     :required false
     :visible-if {:authentication-method "sso_token"}}
    {:name "token"
     :display-name (trs "The Single Sign-On token")
     :type :secret
     :required false
     :default ""
     :visible-if {:authentication-method "sso_token"}}
    (merge driver.common/default-user-details
           {:display-name (trs "User")
            :required false
            :default ""
            :visible-if {:authentication-method "password"}})
    (merge driver.common/default-password-details
           {:display-name (trs "Password")
            :required false
            :default ""
            :visible-if {:authentication-method "password"}})
    driver.common/advanced-options-start
    driver.common/additional-options
    driver.common/default-advanced-options]
   (map u/one-or-many)
   (apply concat)))


; ;;; +----------------------------------------------------------------------------------------------------------------+
; ;;; |                                         metabase.driver.sql-jdbc impls                                         |
; ;;; +----------------------------------------------------------------------------------------------------------------+

(defn- make-subname [host port db]
  (str "//" host ":" port "/" db))

(defn handle-ocient-properties
  "Create a Clojure JDBC database specification for the Ocient DB."
  [{:keys [host port db]
    :or   {host "localhost", port 4050, db "system"}
    :as   opts}]
  (merge
   {:classname                     "com.ocient.jdbc.JDBCDriver"
    :subprotocol                   "ocient"
    :subname                       (make-subname host port db)
    :statementPooling "OFF"}
   (dissoc opts :host :port :db)))

(defn- replace-trailing-semicolon
  [s]
  ;; (log/infof "Hello from replace-trailing-semicolon: %s" (pr-str s))
  (let [last-char (str/join "" (core/take-last 1 s))]
    (cond-> s
      (core/contains? #{";" "⅋"} last-char) (->>
                                             (drop-last)
                                             (str/join "")))))

(defn- handle-additional-properties
  "Marshal Single additional connection peroperties"
  [opts]
  (let [additional-options (:additional-options opts)
        sanitized-options (cond-> opts
                            opts (merge {:additional-options (replace-trailing-semicolon additional-options)}))]
    ;; note: seperator style is misspelled in metabase core code
    (sql-jdbc.common/handle-additional-options sanitized-options sanitized-options, :seperator-style :semicolon)))
     
(defn handle-sso-properties
  "Marshal Single Sign-On connection peroperties"
  [{:keys [sso authentication-method token-type token]
    :or {sso false, authentication-method nil, token-type "", token ""}
    :as opts}]
  (merge
   (if (some? authentication-method)
     (case (str/lower-case authentication-method)

       ;; Password authentication uses the default handshake method (GCM)
       "password"  {}

       ;; The underlying JDBC driver will open a browser window if one is 
       ;; available on the server. Otherwise, a verification URI will be
       ;; printed to stdout. A blank username and password are used to 
       ;; initiate the SSO flow.
       ;;
       ;; TODO 
       ;; Connection threads in Metabase are independent of each other and
       ;; break the Single Sign-On flow used in the JDBC driver. Every new
       ;; DB connection creates a unique session.
       ;;
       ;; "sso"       {:handshake "SSO"
       ;;              :user ""
       ;;              :password ""}

       ;; Single Sign-On using an Access or ID token
       "sso_token" {:handshake "SSO"
                    :user token-type
                    :password token})

     ;; Connection properties in the plugin manifest cannot use the :select
     ;; type and are therfore excluded from MB instances which use that to
     ;; populate the "Add Database" UI.
     (when sso {:handshake "SSO"
                :user token-type
                :password token}))

   ;; Remove unsupported JDBC connection values
   (dissoc opts :sso :token-type :token :authentication-method)))

(defmethod sql-jdbc.conn/connection-details->spec :ocient [_ {_ :ssl, :as details-map}]
  (-> details-map
      (update :port (fn [port]
                      (if (string? port)
                        (Integer/parseInt port)
                        port)))
      ;; remove keys we no longer need
      (set/rename-keys {:dbname :db})
      (handle-ocient-properties)
      (handle-sso-properties)
      (handle-additional-properties)))


;; We'll do regex pattern matching here for determining Field types because Ocient types can have optional lengths,
;; e.g. VARCHAR(255) or NUMERIDECIMAL(16,4)
(def ^:private database-type->base-type
  (sql-jdbc.sync/pattern-based-database-type->base-type
   [[#"ARRAY"     :type/Array]
    [#"TUPLE"     :type/Array]
    [#"VARBINARY" :type/*]
    [#"BINARY"    :type/*]
    [#"HASH"      :type/*]
    [#"BYTE"      :type/*]
    [#"POINT"     :type/*]
    [#"LINESTRING":type/*]
    [#"POLYGON"   :type/*]
    [#"BIGINT"    :type/BigInteger]
    [#"SMALLINT"  :type/Integer]
    [#"TINYINT"   :type/Integer]
    [#"INT"       :type/Integer]
    [#"SHORT"     :type/Integer]
    [#"VARCHAR"   :type/Text]
    [#"CHAR"      :type/Text]
    [#"REAL"      :type/Float]
    [#"DOUBLE"    :type/Float]
    [#"FLOAT"     :type/Float]
    [#"SINGLE PRECISION" :type/Float]
    [#"LONG"      :type/BigInteger]
    [#"DECIMAL"   :type/Decimal]
    [#"BOOLEAN"   :type/Boolean]
    [#"TIMESTAMP" :type/DateTime]
    [#"DATETIME"  :type/DateTime]
    [#"DATE"      :type/Date]
    [#"TIME"      :type/Time]
    [#"IPV4"      :type/IPAddress]
    [#"IP"        :type/IPAddress]
    [#"UUID"      :type/UUID]]))

(defmethod sql-jdbc.sync/database-type->base-type :ocient
  [_ database-type]
  (database-type->base-type database-type))


(doseq [[feature supported?] {;; Ocinet reports all temporal values in UTC
                              :set-timezone                    false
                              :native-parameters               true
                              :basic-aggregations              true
                              :standard-deviation-aggregations true
                              :expression-aggregations         true
                              :advanced-math-expressions       true
                              ;; DB-20497 Ocient does not support SELECT alias.* and 
                              ;; the left-join tests use this pattern
                              :left-join                       (not config/is-test?)
                              :right-join                      true
                              :inner-join                      true
                              :full-join                       true
                              :expressions                     true
                              :percentile-aggregations         true
                              :nested-queries                  false
                              :regex                           false
                              :binning                         true
                              :foreign-keys                    (not config/is-test?)}]
  (defmethod driver/supports? [:ocient feature] [_ _] supported?))

(def zone-id-utc "UTC Zone ID" (t/zone-id "UTC"))

(defmethod sql-jdbc.execute/read-column-thunk [:ocient Types/TIMESTAMP]
  [_ rs _ i]
  (fn []
    (let [d (.getTimestamp ^java.sql.ResultSet rs ^Integer i)]
      (if (nil? d)
        nil
        (.toLocalDateTime d)))))

(defmethod sql-jdbc.execute/read-column-thunk [:ocient Types/DATE]
  [_ rs _ i]
  (fn []
    (let [d (.getDate ^java.sql.ResultSet rs ^Integer i)]
      (if (nil? d)
        nil
        (.toLocalDate d)))))

(defmethod sql-jdbc.execute/read-column-thunk [:ocient Types/TIME]
  [_ rs _ i]
  ;; XGTime values are ALWAYS in UTC
  (fn []
    (let [time (.getTime ^java.sql.ResultSet rs ^Integer i)]
      (if (nil? time)
        nil
        (LocalTime/parse (.toString time))))))

(defmethod sql-jdbc.execute/read-column-thunk [:ocient Types/TIMESTAMP_WITH_TIMEZONE]
  [_ rs _ i]
  ;; XGTimestamp values are ALWAYS in UTC
  (fn []
    (let [local-date-time    (.toLocalDateTime (.getTimestamp ^java.sql.ResultSet rs ^Integer i))
          zone-id            (ZoneId/of "UTC")]
      (OffsetDateTime/of local-date-time zone-id))))

(defmethod sql-jdbc.execute/read-column-thunk [:ocient Types/TIME_WITH_TIMEZONE]
  [_ rs _ i]
  ;; XGTime values are ALWAYS in UTC
  (fn []
    (let [utc-str (.toString (.getTime ^java.sql.ResultSet rs ^Integer i))]
      (LocalTime/parse utc-str))))

(defmethod sql-jdbc.execute/set-parameter [:ocient java.time.OffsetDateTime]
  [_ ^PreparedStatement ps ^Integer i t]
  (let [cal (Calendar/getInstance (TimeZone/getTimeZone (t/zone-id t)))
        t   (t/sql-timestamp t)]
    (log/tracef "(.setTimestamp %d ^%s %s <%s Calendar>)" i (.getName (class t)) (pr-str t) (.. cal getTimeZone getID))
    (.setTimestamp ps i t cal)))

(defmethod unprepare/unprepare-value [:ocient OffsetTime]
  [_ t]
  ;; Ocient doesn't support TIME WITH TIME ZONE so convert OffsetTimes to LocalTimes in UTC.
  (format "time('%s')" (t/format "HH:mm:ss.SSS" (u.date/with-time-zone-same-instant t zone-id-utc))))

(defmethod unprepare/unprepare-value [:ocient OffsetDateTime]
  [_ t]
  ;; Ocient doesn't support TIMESTAMP WITH TIME ZONE so convert OffsetDateTimes to LocalTimestamps in UTC.
  (format "timestamp('%s')" (t/format "yyyy-MM-dd HH:mm:ss.SSS" (u.date/with-time-zone-same-instant t zone-id-utc))))

(defmethod unprepare/unprepare-value [:ocient ZonedDateTime]
  [_ t]
  ;; Ocient doesn't support TIMESTAMP WITH TIME ZONE so convert OffsetDateTimes to LocalTimestamps in UTC.
  (format "timestamp('%s')" (t/format "yyyy-MM-dd HH:mm:ss.SSS" (u.date/with-time-zone-same-instant t zone-id-utc))))

(defmethod unprepare/unprepare-value [:ocient Instant]
  [driver t]
  ;; Instant is already in UTC, convert the object to a ZonedDateTime
  (unprepare/unprepare-value driver (t/zoned-date-time t zone-id-utc)))

; ;;; +----------------------------------------------------------------------------------------------------------------+
; ;;; |                                         metabase.driver.sql impls                                              |
; ;;; +----------------------------------------------------------------------------------------------------------------+

;; Returns the date or timestamp entered, truncated to the specified precision.
(defn- date-trunc [unit expr] (hsql/call :date_trunc (hx/literal unit) (hx/->timestamp expr)))

(defmethod sql.qp/date [:ocient :date]            [_ _ expr] (hsql/call :date expr))
(defmethod sql.qp/date [:ocient :minute]          [_ _ expr] (date-trunc :minute expr))
(defmethod sql.qp/date [:ocient :minute-of-hour]  [_ _ expr] (hsql/call :minute expr))
(defmethod sql.qp/date [:ocient :hour]            [_ _ expr] (date-trunc :hour expr))
(defmethod sql.qp/date [:ocient :hour-of-day]     [_ _ expr] (hsql/call :hour expr))
(defmethod sql.qp/date [:ocient :day]             [_ _ expr] (date-trunc :day expr))
(defmethod sql.qp/date [:ocient :day-of-month]    [_ _ expr] (hsql/call :day_of_month expr))
(defmethod sql.qp/date [:ocient :day-of-year]     [_ _ expr] (hsql/call :day_of_year expr))
(defmethod sql.qp/date [:ocient :week]            [_ _ expr] (sql.qp/adjust-start-of-week :ocient (partial date-trunc :week) expr))
(defmethod sql.qp/date [:ocient :month]           [_ _ expr] (date-trunc :month expr))
(defmethod sql.qp/date [:ocient :month-of-year]   [_ _ expr] (hsql/call :month expr))
(defmethod sql.qp/date [:ocient :quarter]         [_ _ expr] (date-trunc :quarter expr))
(defmethod sql.qp/date [:ocient :quarter-of-year] [_ _ expr] (hsql/call :quarter expr))
(defmethod sql.qp/date [:ocient :year]            [_ _ expr] (date-trunc :year expr))
(defmethod sql.qp/date [:ocient :day-of-week]     [_ _ expr]
  (sql.qp/adjust-day-of-week :ocient
                              (hsql/call :isodow expr)))


;; Passthrough by default
(defmethod sql.qp/date [:ocient :default]         [_ _ expr] expr)

(defmethod sql.qp/current-datetime-honeysql-form :ocient [_] :%now)

(defmethod sql.qp/unix-timestamp->honeysql [:ocient :seconds]      [_ _ expr] (hsql/call :to_timestamp expr))
(defmethod sql.qp/unix-timestamp->honeysql [:ocient :milliseconds] [_ _ expr] (hsql/call :to_timestamp expr 3))
(defmethod sql.qp/unix-timestamp->honeysql [:ocient :microseconds] [_ _ expr] (hsql/call :to_timestamp expr 6))

(defmethod sql.qp/current-datetime-honeysql-form :ocient
  [_]
  :%current_timestamp)

(defmethod sql.qp/->honeysql [:ocient :percentile]
  [driver [_ field p]]
  ;; TODO This works but the query should really have a LIMIT 1 tacked onto the end of it...
  (hsql/raw (format "percentile(%s, %s) over (order by %s)"
                    (hformat/to-sql (sql.qp/->honeysql driver field))
                    (hformat/to-sql (sql.qp/->honeysql driver p))
                    (hformat/to-sql (sql.qp/->honeysql driver field)))))

(defmethod sql.qp/->honeysql [:ocient :median]
  [driver [_ arg]]
  ;; Ocient does not have a MEDIAN() function, use PERCENTILE()
  (sql.qp/->honeysql driver [:percentile arg 0.5]))

(defmethod sql.qp/->honeysql [:ocient :relative-datetime]
  [driver [_ amount unit]]
  (sql.qp/date driver unit (if (zero? amount)
                             (sql.qp/current-datetime-honeysql-form driver)
                             (sql.qp/add-interval-honeysql-form driver (sql.qp/current-datetime-honeysql-form driver) amount unit))))

(defmethod sql.qp/->honeysql [:ocient :concat]
  [driver [_ & args]]
  (->> args
       (map (partial sql.qp/->honeysql driver))
       (reduce (partial hsql/call :concat))))

(defmethod sql.qp/add-interval-honeysql-form :ocient
  [_ hsql-form amount unit]
  (hx/+
   (hx/->timestamp hsql-form)
   (case unit
     :second   (hsql/call :seconds amount)
     :minute   (hsql/call :minutes amount)
     :hour     (hsql/call :hours amount)
     :day      (hsql/call :days amount)
     :week     (hsql/call :weeks amount)
     :month    (hsql/call :months amount)
     :quarter  (hsql/call :months (hx/* amount (hsql/raw 3)))
     :quarters (hsql/call :months (hx/* amount (hsql/raw 3)))
     :year     (hsql/call :years amount))))

(defmethod sql.qp/unix-timestamp->honeysql [:ocient :seconds]
  [_ _ field-or-value]
  (hsql/call :to_timestamp field-or-value))

(defmethod sql.qp/unix-timestamp->honeysql [:ocient :milliseconds]
  [driver _ field-or-value]
  (sql.qp/unix-timestamp->honeysql driver :seconds (hx// field-or-value (hsql/raw 1000))))

(defmethod sql.qp/unix-timestamp->honeysql [:ocient :microseconds]
  [driver _ field-or-value]
  (sql.qp/unix-timestamp->honeysql driver :seconds (hx// field-or-value (hsql/raw 1000000))))

(defn unescape-column-names
  "Remove escape characters for column names"
  [table-description]
  (assoc table-description :fields
    (set (mapv #(update % :name (fn [name]  (-> name
                                              (clojure.string/replace #"^\\([^A-Za-z])" "$1")     ;; Non-letters are escaped at beginning of column name 
                                              (clojure.string/replace #"\\([(),.\[\]])" "$1"))))  ;; Characters (),.[] are always escaped
                       (get table-description :fields)))))

(defmethod driver/describe-table :ocient
  [driver database table]
  (unescape-column-names (sql-jdbc.sync/describe-table driver database table)))
