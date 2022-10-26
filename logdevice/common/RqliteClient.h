#pragma once

#include <functional>
#include <gason.h>
#include <string>
#include <vector>

namespace facebook { namespace logdevice {
class RqliteClient {
 public:
  explicit RqliteClient(std::string url);

  struct ExecuteResults {
    struct Result {
      std::string error;
      int last_insert_id;
      int rows_affected = 0;
      double time;
    };

    std::vector<Result> results;
    double time;
  };

  struct QueryResults {
    struct Result {
      std::string error;
      std::vector<std::string> columns;
      std::vector<std::string> types;
      std::vector<std::vector<JsonValue>> values;
      double time;
    };

    std::vector<Result> results;
    double time;
  };

  typedef std::function<void(ExecuteResults)> execute_callback_t;

  typedef std::function<void(QueryResults)> query_callback_t;

  ExecuteResults executeSync(std::vector<std::string> stmts,
                             bool enable_tx = false);

  void execute(std::vector<std::string> stmts,
               execute_callback_t callback,
               bool enable_tx = false);

  QueryResults querySync(std::vector<std::string> stmt);

  void query(std::vector<std::string> stmts, query_callback_t callback);

  void close();

  std::string getUrl() {
    return url_;
  }

  RqliteClient(const RqliteClient&) = delete;
  RqliteClient(RqliteClient&&) = delete;
  RqliteClient& operator=(const RqliteClient&) = delete;
  RqliteClient& operator=(RqliteClient&&) = delete;

 private:
  static const std::string execute_path_;
  static const std::string query_path_;
  static const std::string pretty_param_;
  static const std::string timing_param_;
  static const std::string tx_param_;

  std::string url_;

  std::string serializeStmts(std::vector<std::string> stmts);

  static int deserializeExecuteResults(std::string value,
                                       ExecuteResults& ExecuteResults);
  static int extractExecuteResults(JsonValue o, ExecuteResults& results);

  static int deserializeQueryResults(std::string value,
                                     QueryResults& queryResults);
  static int extractQueryResults(JsonValue o, QueryResults& results);
};

}} // namespace facebook::logdevice
