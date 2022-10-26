#pragma once

#include <chrono>
#include <memory>
#include <string>

#include <boost/noncopyable.hpp>
#include <folly/Optional.h>
#include <folly/concurrency/AtomicSharedPtr.h>
#include <folly/futures/Future.h>

#include "logdevice/common/EpochStore.h"
#include "logdevice/common/MetaDataTracer.h"
#include "logdevice/common/NodeID.h"
#include "logdevice/common/Processor.h"
#include "logdevice/common/RqliteClient.h"
#include "logdevice/common/UpdateableSharedPtr.h"
#include "logdevice/common/configuration/Configuration.h"
#include "logdevice/common/plugin/ZookeeperClientFactory.h"
#include "logdevice/common/settings/Settings.h"
#include "logdevice/common/settings/UpdateableSettings.h"
#include "logdevice/include/ConfigSubscriptionHandle.h"
#include "logdevice/server/epoch_store/EpochStoreEpochMetaDataFormat.h"
#include "logdevice/server/epoch_store/LogMetaData.h"
#include "logdevice/server/epoch_store/ZookeeperEpochStoreRequest.h"

/**
 * @file  RqliteEpochStore is an implementation of the EpochStore interface
 *        which reads (and atomically increments) epoch numbers from rqlite.
 */

namespace facebook { namespace logdevice {

class Processor;
class Configuration;

class RqliteEpochStore : public EpochStore, boost::noncopyable {
 public:
  /**
   * @param path      root directory storing one file for each log
   * @param processor parent processor for current FileEpochStore
   */
  RqliteEpochStore(std::string cluster_name,
                   RequestExecutor request_executor,
                   std::shared_ptr<RqliteClient> rqclient,
                   folly::Optional<NodeID> my_node_id,
                   std::shared_ptr<UpdateableNodesConfiguration> config);

  ~RqliteEpochStore() override;

  int getLastCleanEpoch(logid_t logid, EpochStore::CompletionLCE cf) override;
  int setLastCleanEpoch(logid_t logid,
                        epoch_t lce,
                        const TailRecord& tail_record,
                        EpochStore::CompletionLCE cf) override;
  int createOrUpdateMetaData(
      logid_t logid,
      std::shared_ptr<EpochMetaData::Updater> updater,
      CompletionMetaData cf,
      MetaDataTracer tracer,
      WriteNodeID write_node_id = WriteNodeID::NO) override;

  std::string identify() const override;

  /**
   * Returns the path to the root znode for the logdevice cluster that this
   * EpochStore is for (`cluster_name_`)
   */
  std::string tablePrefix() const {
    return "logdevice_" + cluster_name_ + "_logs_";
  }

 private:
  RequestExecutor request_executor_;

  std::shared_ptr<RqliteClient> rqclient_;

  folly::Optional<NodeID> my_node_id_;

  std::string cluster_name_;

  // Cluster config, used to figure out NodeID
  std::shared_ptr<UpdateableNodesConfiguration> nodes_config_;

  // This bit changes when the epoch store is being destroyed. This is needed
  // to control whether the EpochStore is being destroyed in callbacks that get
  // a ZCLOSING status - even if they run after the ZookeperEpochStore instance
  // had been destroyed
  std::atomic<bool> shutting_down_;

  struct RqliteReadResult {
    std::string error;
    Status st;
    std::string value;
    uint64_t version;
  };

  struct RequestContext {
    std::shared_ptr<ZookeeperEpochStoreRequest> zrq;
    LogMetaData log_metadata;
  };

  /**
   * Run a zoo_aget() on a znode, optionally followed by a modify and a
   * version-conditional zoo_aset() of a new value into the same znode.
   *
   * @param  zrq   controls the path to znode, znode value (de)serialization,
   *               and whether a new value must be written back.
   *
   * @return 0 if the request was successfully submitted to Zookeeper, -1
   *         on failure. Sets err to INTERNAL, NOTCONN, ACCESS, SYSLIMIT as
   *         defined for EpochStore::nextEpoch().
   */
  int runRequest(std::shared_ptr<ZookeeperEpochStoreRequest> zrq);

  /**
   * Schedules a request on the Processor after a Zookeeper modification
   * completes.
   */
  void postRequestCompletion(Status st, RequestContext&& context);

  /**
   * The callback executed when then info has been fetched.
   */
  void onReadTableComplete(RequestContext&& context, RqliteReadResult reuslt);

  /**
   * Provisions znodes for a log that a particular zrq runs on. Executes
   * a zookeeper multiOp.
   */
  void provisionLogRows(RequestContext&& context, std::string value);

  /**
*  每个 log 会在 zk 里分配四个 znode:

/logdevice/logdevice/logs/{logid}

/logdevice/logdevice/logs/{logid}/metadatalog_lce

/logdevice/logdevice/logs/{logid}/sequencer

存储的数据内容见：EpochStoreEpochMetaDataFormat.cpp

/logdevice/logdevice/logs/{logid}/lce

存储的数据内容见：EpochStoreLastCleanEpochFormat.cpp
*
*
* table: (logid, sequencer, metadatalog_lce, lce)
*
* table: (logid, sequencer, version)
* table: (logid, metadatalog_lce, version)
* table: (logid, lce, version)
*
*/

  folly::SemiFuture<RqliteReadResult> readTable(const RequestContext& context);

  void writeTable(RequestContext&& context,
                  std::string value,
                  uint64_t version);

  static std::string str2hex(const std::string& value);

  static std::string hex2str(const std::string& hex);

  static std::tuple<std::string, std::string>
  splitZnodePath(const std::string& path);
};

}} // namespace facebook::logdevice
