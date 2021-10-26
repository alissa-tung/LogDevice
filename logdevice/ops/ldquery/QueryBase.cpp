#include "logdevice/ops/ldquery/QueryBase.h"

#include <cctype>
#include <chrono>

#include "logdevice/common/debug.h"
#include "logdevice/ops/ldquery/Context.h"
#include "logdevice/ops/ldquery/Errors.h"
#include "logdevice/ops/ldquery/Table.h"
#include "logdevice/ops/ldquery/TableRegistry.h"
#include "logdevice/ops/ldquery/VirtualTable.h"

namespace facebook { namespace logdevice { namespace ldquery {

bool QueryBase::QueryResult::operator==(
    const QueryBase::QueryResult& other) const {
  return headers == other.headers && rows == other.rows;
}

static void getCacheTTLStatic(sqlite3_context* context,
                              int argc,
                              sqlite3_value** argv) {
  ld_check(0 == argc);
  (void)(argc);
  (void)(argv);
  const QueryBase* ldquery = (QueryBase*)sqlite3_user_data(context);
  sqlite3_result_int(context, ldquery->getCacheTTL().count());
}

static void setCacheTTLStatic(sqlite3_context* context,
                              int argc,
                              sqlite3_value** argv) {
  if (argc == 1) {
    const int new_ttl = sqlite3_value_int(argv[0]);
    QueryBase* ldquery = (QueryBase*)sqlite3_user_data(context);
    ldquery->setCacheTTL(std::chrono::seconds(new_ttl));
    sqlite3_result_int(context, new_ttl);
  } else {
    sqlite3_result_null(context);
  }
}

QueryBase::QueryBase() {
  const int rc = sqlite3_open(":memory:", &db_);

  if (rc != 0) {
    ld_error("Can't open database: %s\n", sqlite3_errmsg(db_));
    throw ConstructorFailed();
  }

  // A function for retrieving the current ttl configured for table cache.
  sqlite3_create_function(db_,
                          "get_cache_ttl",
                          0,
                          SQLITE_UTF8,
                          (void*)this,
                          getCacheTTLStatic,
                          0,
                          0);
  // A function for changing the ttl configured for table cache.
  sqlite3_create_function(db_,
                          "set_cache_ttl",
                          1,
                          SQLITE_UTF8,
                          (void*)this,
                          setCacheTTLStatic,
                          0,
                          0);
}

QueryBase::~QueryBase() {
  if (db_) {
    sqlite3_close(db_);
  }
}

QueryBase::QueryResult QueryBase::executeNextStmt(sqlite3_stmt* pStmt) {
  QueryResult res;
  resetActiveQuery();

  const int ncols = sqlite3_column_count(pStmt);
  for (int i = 0; i < ncols; ++i) {
    res.headers.push_back(std::string(sqlite3_column_name(pStmt, i)));
    res.cols_max_size.push_back(res.headers.back().size());
  }

  while (sqlite3_step(pStmt) == SQLITE_ROW) {
    Row row;
    for (int i = 0; i < ncols; ++i) {
      char* v = (char*)sqlite3_column_text(pStmt, i);
      if (v) {
        row.emplace_back(v);
        res.cols_max_size[i] =
            std::max(res.cols_max_size[i], row.back().size());
      } else {
        // TODO(#7646110): Row should be
        // std::vector<folly::Optional<std::string>> in order to not confuse
        // empty string and null values. Python bindings would then convert
        // null values to None.
        row.push_back("");
      }
    }
    res.rows.push_back(std::move(row));
  }

  return res;
}

QueryBase::QueryResults QueryBase::query(const std::string& query) {
  QueryResults results;

  sqlite3_stmt* pStmt = nullptr;
  const char* leftover = query.c_str();

  // This tells each virtual table that the next time we fetch data from them
  // they should refill their cache depending on their ttl.
  table_registry_.notifyNewQuery();

  while (leftover[0]) {
    int rc = sqlite3_prepare_v2(db_, leftover, -1, &pStmt, &leftover);
    if (rc != SQLITE_OK) {
      ld_error("Error in statement %s", sqlite3_errmsg(db_));
      throw StatementError(sqlite3_errmsg(db_));
    }

    if (!pStmt) {
      // This happens for a comment or a whitespace.
      while (isspace(leftover[0])) {
        ++leftover;
      }
      continue;
    }

    std::chrono::steady_clock::time_point tstart =
        std::chrono::steady_clock::now();
    QueryResult res = executeNextStmt(pStmt);
    std::chrono::steady_clock::time_point tend =
        std::chrono::steady_clock::now();
    res.metadata = getActiveQuery();
    sqlite3_finalize(pStmt);
    auto duration =
        std::chrono::duration_cast<std::chrono::milliseconds>(tend - tstart)
            .count();
    res.metadata.latency = duration;
    results.push_back(std::move(res));
  }

  return results;
}

std::vector<TableMetadata> QueryBase::getTables() const {
  auto tables = table_registry_.getTables();
  return tables;
}

void QueryBase::setCacheTTL(std::chrono::seconds ttl) {
  cache_ttl_ = ttl;
  table_registry_.setCacheTTL(ttl);
}

void QueryBase::enableServerSideFiltering(bool val) {
  server_side_filtering_enabled_ = val;
  table_registry_.enableServerSideFiltering(val);
}

bool QueryBase::serverSideFilteringEnabled() const {
  return server_side_filtering_enabled_;
}

}}} // namespace facebook::logdevice::ldquery
