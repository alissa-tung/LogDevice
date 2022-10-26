#pragma once

#include <unordered_map>

#include <folly/Function.h>
#include <folly/Optional.h>
#include <folly/Synchronized.h>

#include "logdevice/common/RqliteClient.h"
#include "logdevice/common/VersionedConfigStore.h"

namespace facebook { namespace logdevice {

class RqliteVersionedConfigStore : public VersionedConfigStore {
 public:
  explicit RqliteVersionedConfigStore(extract_version_fn extract_fn,
                                      std::unique_ptr<RqliteClient> rqlite)
      : VersionedConfigStore(std::move(extract_fn)),
        rqlite_(std::move(rqlite)),
        shutdown_signaled_(false),
        shutdown_completed_(false) {
    ld_check(extract_fn_ != nullptr);
    ld_check(rqlite_ != nullptr);
  }

  // Note on destruction: while this class does not keep track of pending
  // callbacks, we take care to ensure that the callbacks in the async methods
  // do not captures state that would be otherwise invalid after the
  // RqliteVersionedConfigStore instance gets destroyed. (This is why we
  // store the extraction function and Zookeeper client as shared_ptr-s.
  ~RqliteVersionedConfigStore() override {}

  void getConfig(std::string key,
                 value_callback_t cb,
                 folly::Optional<version_t> base_version = {}) const override;

  // Does a linearizable read to zookeeper by doing a sync() call first and
  // then the actual read.
  void getLatestConfig(std::string key, value_callback_t cb) const override;

  void readModifyWriteConfig(std::string key,
                             mutation_callback_t mcb,
                             write_callback_t cb) override;

  // IMPORTANT: assumes shutdown is called from a different thread from ZK
  // client's EventBase / thread.
  void shutdown() override;
  bool shutdownSignaled() const;

 private:
  void writeModifiedValue(std::string key,
                          std::string write_value,
                          version_t new_version,
                          uint64_t row_version,
                          std::shared_ptr<write_callback_t> write_callback);

  void writeModifiedValueNew(std::string key,
                             std::string write_value,
                             version_t new_version,
                             std::shared_ptr<write_callback_t> write_callback);

  Status toStatus(const RqliteClient::QueryResults::Result& result) const;

  std::pair<std::string, uint64_t>
  getValueAndVersion(const RqliteClient::QueryResults::Result& result) const;

  bool noTable(const std::string& error) const;

  bool matchError(const std::string& error, const std::string& candidate) const;

  std::tuple<std::string, std::string> splitKey(const std::string& key) const;

  static std::string str2hex(const std::string& value);

  static std::string hex2str(const std::string& hex);

  std::unique_ptr<RqliteClient> rqlite_;

  std::atomic<bool> shutdown_signaled_;
  // Only safe to access `this` (for zk_) if tryRLock succeeds, since after
  // shutdown completes, zk_ will be set to nullptr and we assume zk_ dtor will
  // clean up all callbacks.
  folly::Synchronized<bool> shutdown_completed_;
};
}} // namespace facebook::logdevice
