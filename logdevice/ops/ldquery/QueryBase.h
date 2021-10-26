#pragma once

#include <chrono>
#include <sqlite3.h>
#include <string>
#include <vector>

#include "logdevice/ops/ldquery/TableRegistry.h"

namespace facebook { namespace logdevice { namespace ldquery {

class ContextBase;

class QueryBase {
 public:
  typedef std::vector<std::string> ColumnNames;
  typedef std::vector<std::string> Row;
  typedef std::vector<Row> Rows;

  struct QueryResult {
    ColumnNames headers;
    Rows rows;
    std::vector<size_t> cols_max_size;
    ActiveQueryMetadata metadata;
    // Required in order to have boost bindings for this struct.
    bool operator==(const QueryResult& other) const;
  };

  typedef std::vector<QueryResult> QueryResults;

  explicit QueryBase();

  ~QueryBase();

  /**
   * Execute a SQL statement. Return an array of QueryResult objects.
   */
  QueryResults query(const std::string& query);

  virtual void registerTables() = 0;
  std::vector<TableMetadata> getTables() const;

  virtual ActiveQueryMetadata& getActiveQuery() const = 0;
  virtual void resetActiveQuery() = 0;

  void setCacheTTL(std::chrono::seconds ttl);
  std::chrono::seconds getCacheTTL() const {
    return cache_ttl_;
  }

  void enableServerSideFiltering(bool val);
  bool serverSideFilteringEnabled() const;

 protected:
  // Call sqlite3_step() to extract rows from the given statement and build a
  // QueryResult object.
  QueryResult executeNextStmt(sqlite3_stmt* pStmt);

  sqlite3* db_{nullptr};
  TableRegistry table_registry_;

  bool server_side_filtering_enabled_{true};
  std::chrono::seconds cache_ttl_{60};
};

}}} // namespace facebook::logdevice::ldquery
