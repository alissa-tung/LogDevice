/**
 * Copyright (c) 2017-present, Facebook, Inc. and its affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */
#include "logdevice/ops/ldquery/LDQuery.h"

#include <cctype>
#include <chrono>

#include "logdevice/common/debug.h"
#include "logdevice/ops/ldquery/Context.h"
#include "logdevice/ops/ldquery/Errors.h"
#include "logdevice/ops/ldquery/Table.h"
#include "logdevice/ops/ldquery/TableRegistry.h"
#include "logdevice/ops/ldquery/VirtualTable.h"
#include "tables/AppendOutliers.h"
#include "tables/AppendThroughput.h"
#include "tables/CatchupQueues.h"
#include "tables/ChunkRebuildings.h"
#include "tables/ClientReadStreams.h"
#include "tables/ClusterStateTable.h"
#include "tables/EpochStore.h"
#include "tables/EventLog.h"
#include "tables/Graylist.h"
#include "tables/HistoricalMetadata.h"
#include "tables/Info.h"
#include "tables/InfoConfig.h"
#include "tables/InfoRsm.h"
#include "tables/Iterators.h"
#include "tables/LogGroups.h"
#include "tables/LogRebuildings.h"
#include "tables/LogStorageState.h"
#include "tables/LogsConfigRsm.h"
#include "tables/LogsDBDirectory.h"
#include "tables/LogsDBMetadata.h"
#include "tables/Nodes.h"
#include "tables/Partitions.h"
#include "tables/Purges.h"
#include "tables/Readers.h"
#include "tables/Record.h"
#include "tables/RecordCache.h"
#include "tables/Recoveries.h"
#include "tables/Sequencers.h"
#include "tables/Settings.h"
#include "tables/ShardAuthoritativeStatus.h"
#include "tables/ShardRebuildings.h"
#include "tables/Shards.h"
#include "tables/Sockets.h"
#include "tables/Stats.h"
#include "tables/StatsRocksdb.h"
#include "tables/StorageTasks.h"
#include "tables/StoredLogs.h"
#include "tables/SyncSequencerRequests.h"

namespace facebook { namespace logdevice { namespace ldquery {

static void lsnToStringStatic(sqlite3_context* context,
                              int argc,
                              sqlite3_value** argv) {
  if (argc == 1) {
    const int64_t lsn = sqlite3_value_int64(argv[0]);
    const std::string res = lsn_to_string(lsn_t(lsn));
    sqlite3_result_text(context, res.c_str(), res.size(), SQLITE_TRANSIENT);
  } else {
    sqlite3_result_null(context);
  }
}

static void stringToLsnStatic(sqlite3_context* context,
                              int argc,
                              sqlite3_value** argv) {
  if (argc == 1) {
    const std::string str((const char*)sqlite3_value_text(argv[0]));
    lsn_t lsn = lsn_t(-1);
    if (!string_to_lsn(str, lsn)) {
      sqlite3_result_int64(context, (int64_t)lsn);
      return;
    }
  }
  sqlite3_result_null(context);
}

static void lsnToEpochStatic(sqlite3_context* context,
                             int argc,
                             sqlite3_value** argv) {
  if (argc == 1) {
    const int64_t lsn = sqlite3_value_int64(argv[0]);
    const int64_t epoch = lsn_to_epoch(lsn).val_;
    sqlite3_result_int64(context, epoch);
  } else {
    sqlite3_result_null(context);
  }
}

static void log2Static(sqlite3_context* context,
                       int argc,
                       sqlite3_value** argv) {
  if (argc == 1) {
    sqlite3_result_double(context, log2(sqlite3_value_double(argv[0])));
  } else {
    sqlite3_result_null(context);
  }
}

void LDQuery::registerTables() {
  table_registry_.registerTable<tables::AppendOutliers>(ctx_);
  table_registry_.registerTable<tables::AppendThroughput>(ctx_);
  table_registry_.registerTable<tables::CatchupQueues>(ctx_);
  table_registry_.registerTable<tables::ChunkRebuildings>(ctx_);
  table_registry_.registerTable<tables::ClientReadStreams>(ctx_);
  table_registry_.registerTable<tables::ClusterStateTable>(ctx_);
  table_registry_.registerTable<tables::LogsDBDirectory>(ctx_);
  table_registry_.registerTable<tables::EpochStore>(ctx_);
  table_registry_.registerTable<tables::EventLog>(ctx_);
  table_registry_.registerTable<tables::Graylist>(ctx_);
  table_registry_.registerTable<tables::HistoricalMetadata>(ctx_);
  table_registry_.registerTable<tables::HistoricalMetadataLegacy>(ctx_);
  table_registry_.registerTable<tables::Info>(ctx_);
  table_registry_.registerTable<tables::InfoConfig>(ctx_);
  table_registry_.registerTable<tables::InfoRsm>(ctx_);
  table_registry_.registerTable<tables::Iterators>(ctx_);
  table_registry_.registerTable<tables::LogGroups>(ctx_);
  table_registry_.registerTable<tables::LogRebuildings>(ctx_);
  table_registry_.registerTable<tables::LogStorageState>(ctx_);
  table_registry_.registerTable<tables::LogsConfigRsm>(ctx_);
  table_registry_.registerTable<tables::LogsDBMetadata>(ctx_);
  table_registry_.registerTable<tables::Nodes>(ctx_);
  table_registry_.registerTable<tables::Partitions>(ctx_);
  table_registry_.registerTable<tables::Purges>(ctx_);
  table_registry_.registerTable<tables::Readers>(ctx_);
  table_registry_.registerTable<tables::Record<tables::RecordQueryMode::CSI>>(
      ctx_);
  table_registry_.registerTable<tables::Record<tables::RecordQueryMode::DATA>>(
      ctx_);
  table_registry_.registerTable<tables::RecordCache>(ctx_);
  table_registry_.registerTable<tables::Recoveries>(ctx_);
  table_registry_.registerTable<tables::Sequencers>(ctx_);
  table_registry_.registerTable<tables::Settings>(ctx_);
  table_registry_.registerTable<tables::ShardAuthoritativeStatus>(
      ctx_, tables::ShardAuthoritativeStatus::Verbose::NORMAL);
  table_registry_.registerTable<tables::ShardAuthoritativeStatus>(
      ctx_, tables::ShardAuthoritativeStatus::Verbose::VERBOSE);
  table_registry_.registerTable<tables::ShardAuthoritativeStatus>(
      ctx_, tables::ShardAuthoritativeStatus::Verbose::SPEW);
  table_registry_.registerTable<tables::ShardRebuildings>(ctx_);
  table_registry_.registerTable<tables::Shards>(ctx_);
  table_registry_.registerTable<tables::Sockets>(ctx_);
  table_registry_.registerTable<tables::Stats>(ctx_);
  table_registry_.registerTable<tables::StatsRocksdb>(ctx_);
  table_registry_.registerTable<tables::StorageTasks>(ctx_);
  table_registry_.registerTable<tables::StoredLogs>(ctx_);
  table_registry_.registerTable<tables::SyncSequencerRequests>(ctx_);

  if (table_registry_.attachTables(db_) != 0) {
    throw ConstructorFailed();
  }

  setCacheTTL(cache_ttl_);
}

LDQuery::LDQuery(std::string config_path,
                 std::chrono::milliseconds command_timeout,
                 bool use_ssl)
    : config_path_(std::move(config_path)),
      command_timeout_(command_timeout),
      QueryBase() {
  ctx_ = std::make_shared<Context>();

  ctx_->commandTimeout = command_timeout_;
  ctx_->config_path = config_path_;
  ctx_->use_ssl = use_ssl;

  registerTables();

  // A function for converting an integer to a human readable lsn.
  sqlite3_create_function(db_,
                          "lsn_to_string",
                          1,
                          SQLITE_UTF8,
                          (void*)this,
                          lsnToStringStatic,
                          0,
                          0);
  // A function for converting a human readable lsn to an integer.
  sqlite3_create_function(db_,
                          "string_to_lsn",
                          1,
                          SQLITE_UTF8,
                          (void*)this,
                          stringToLsnStatic,
                          0,
                          0);
  // A function for converting an lsn integer to an epoch.
  sqlite3_create_function(
      db_, "lsn_to_epoch", 1, SQLITE_UTF8, (void*)this, lsnToEpochStatic, 0, 0);
  // Logarithm in base 2.
  sqlite3_create_function(
      db_, "log2", 1, SQLITE_UTF8, (void*)this, log2Static, 0, 0);
}

LDQuery::~LDQuery() {}

void LDQuery::setPrettyOutput(bool val) {
  ctx_->pretty_output = val;
}

bool LDQuery::getPrettyOutput() const {
  return ctx_->pretty_output;
}

ActiveQueryMetadata& LDQuery::getActiveQuery() const {
  return ctx_->activeQueryMetadata;
}

void LDQuery::resetActiveQuery() {
  return ctx_->resetActiveQuery();
}

}}} // namespace facebook::logdevice::ldquery
