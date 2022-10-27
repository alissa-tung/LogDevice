#include "RqliteClient.h"

#include <string.h>

#include <cpr/cpr.h>

namespace facebook { namespace logdevice {

const std::string RqliteClient::execute_path_ = "/db/execute";
const std::string RqliteClient::query_path_ = "/db/query?pretty&timings";
const std::string RqliteClient::pretty_param_ = "pretty";
const std::string RqliteClient::timing_param_ = "timings";
const std::string RqliteClient::tx_param_ = "transaction";

RqliteClient::RqliteClient(std::string url) : url_(url) {}

RqliteClient::ExecuteResults
RqliteClient::executeSync(std::vector<std::string> stmts, bool enable_tx) {
  std::promise<RqliteClient::ExecuteResults> p;
  auto fut = p.get_future();
  this->execute(
      stmts,
      [&p](RqliteClient::ExecuteResults r) mutable { p.set_value(r); },
      enable_tx);
  return fut.get();
}

void RqliteClient::execute(std::vector<std::string> stmts,
                           execute_callback_t callback,
                           bool enable_tx) {
  auto _ = cpr::PostCallback(
      [callback = std::move(callback)](cpr::Response r) {
        ExecuteResults executeResults;
        if (r.status_code == 200) {
          deserializeExecuteResults(r.text.append(1, '\0'), executeResults);
        } else {
          ExecuteResults::Result new_r;
          new_r.error = "connection error";
          executeResults.results.push_back(std::move(new_r));
        }
        callback(std::move(executeResults));
      },

      cpr::Url{url_, execute_path_},
      cpr::Body{serializeStmts(stmts)},
      (enable_tx ? cpr::Parameters{{pretty_param_, ""},
                                   {timing_param_, ""},
                                   {tx_param_, ""}}
                 : cpr::Parameters{{pretty_param_, ""}, {timing_param_, ""}}),
      cpr::Header{{"Content-Type", "text/json"}});
}

void RqliteClient::query(std::vector<std::string> stmts,
                         query_callback_t callback) {
  auto _ = cpr::PostCallback(
      [callback = std::move(callback)](cpr::Response r) {
        QueryResults queryResults;
        if (r.status_code == 200) {
          deserializeQueryResults(r.text.append(1, '\0'), queryResults);
        } else {
          QueryResults::Result new_r;
          new_r.error = "connection error";
          queryResults.results.push_back(std::move(new_r));
        }
        callback(std::move(queryResults));
      },

      cpr::Url{url_, query_path_},
      cpr::Body{serializeStmts(stmts)},
      cpr::Header{{"Content-Type", "text/json"}});
}

RqliteClient::QueryResults
RqliteClient::querySync(std::vector<std::string> stmts) {
  std::promise<RqliteClient::QueryResults> p;
  auto fut = p.get_future();
  this->query(
      stmts, [&p](RqliteClient::QueryResults r) mutable { p.set_value(r); });
  return fut.get();
}

std::string RqliteClient::serializeStmts(std::vector<std::string> stmts) {
  std::stringstream ss;
  ss << "[";
  bool isFirst = true;
  for (auto& stmt : stmts) {
    if (!isFirst) {
      ss << ",";
    } else {
      isFirst = false;
    }
    ss << R"(")" << stmt << R"(")";
  }
  ss << "]";

  return ss.str();
}

int RqliteClient::deserializeExecuteResults(std::string resp,
                                            ExecuteResults& executeResults) {
  // do not forget terminate source string with 0
  char* source = const_cast<char*>(resp.c_str());
  char* endptr;
  JsonValue value;
  JsonAllocator allocator;
  int status = jsonParse(source, &endptr, &value, allocator);
  if (status != JSON_OK) {
    return -1;
  }

  return extractExecuteResults(value, executeResults);
}

int RqliteClient::extractExecuteResults(JsonValue o, ExecuteResults& results) {
  assert(o.getTag() == JSON_OBJECT);
  for (auto i : o) {
    if (strcmp(i->key, "time") == 0) {
      results.time = i->value.toNumber();
    } else if (strcmp(i->key, "results") == 0) {
      for (auto r : i->value) {
        ExecuteResults::Result new_r;
        for (auto v : r->value) {
          if (strcmp(v->key, "error") == 0) {
            new_r.error = std::string(v->value.toString());
          } else if (strcmp(v->key, "last_insert_id") == 0) {
            new_r.last_insert_id = v->value.toNumber();
          } else if (strcmp(v->key, "rows_affected") == 0) {
            new_r.rows_affected = v->value.toNumber();
          } else if (strcmp(v->key, "time") == 0) {
            new_r.time = v->value.toNumber();
          } else {
            return -1;
          }
        }

        results.results.push_back(std::move(new_r));
      }
    }
  }

  return 0;
}

int RqliteClient::deserializeQueryResults(std::string resp,
                                          QueryResults& queryResults) {
  // do not forget terminate source string with 0
  char* source = const_cast<char*>(resp.c_str());
  char* endptr;
  JsonValue value;
  JsonAllocator allocator;
  int status = jsonParse(source, &endptr, &value, allocator);
  if (status != JSON_OK) {
    return -1;
  }

  return extractQueryResults(value, queryResults);
}

int RqliteClient::extractQueryResults(JsonValue o, QueryResults& results) {
  assert(o.getTag() == JSON_OBJECT);
  for (auto i : o) {
    if (strcmp(i->key, "time") == 0) {
      results.time = i->value.toNumber();
    } else if (strcmp(i->key, "results") == 0) {
      for (auto r : i->value) {
        QueryResults::Result new_r;
        for (auto v : r->value) {
          if (strcmp(v->key, "error") == 0) {
            new_r.error = std::string(v->value.toString());
          } else if (strcmp(v->key, "columns") == 0) {
            std::vector<std::string> columns;
            for (auto c : v->value) {
              columns.push_back(c->value.toString());
            }
            new_r.columns = std::move(columns);
          } else if (strcmp(v->key, "types") == 0) {
            std::vector<std::string> types;
            for (auto t : v->value) {
              types.push_back(t->value.toString());
            }
            new_r.types = std::move(types);
          } else if (strcmp(v->key, "values") == 0) {
            std::vector<std::vector<JsonValue>> values;
            for (auto rs : v->value) {
              std::vector<JsonValue> row;
              for (auto s : rs->value) {
                row.push_back(s->value);
              }
              values.push_back(std::move(row));
            }
            new_r.values = std::move(values);
          } else if (strcmp(v->key, "time") == 0) {
            new_r.time = v->value.toNumber();
          } else {
            return -1;
          }
        }
        results.results.push_back(std::move(new_r));
      }
    }
  }

  return 0;
}

void RqliteClient::close() {}

}} // namespace facebook::logdevice
