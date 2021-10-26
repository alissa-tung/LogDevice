/**
 * Copyright (c) 2017-present, Facebook, Inc. and its affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */
#pragma once

#include <chrono>
#include <sqlite3.h>
#include <string>
#include <vector>

#include "logdevice/ops/ldquery/QueryBase.h"
#include "logdevice/ops/ldquery/TableRegistry.h"

namespace facebook { namespace logdevice { namespace ldquery {

class Context;

class LDQuery : public QueryBase {
 public:
  /**
   * Construct an LDquery client.
   * @param config_path     Path to the LD tier's config.
   * @param command_timeout Timeout when retrieve data from a LD node through
   *                        its admin command port.
   * @param use_ssl         Indicates that ldquery should connect to admin
   *                        command port using SSL/TLS
   */
  explicit LDQuery(
      std::string config_path,
      std::chrono::milliseconds command_timeout = std::chrono::seconds{5},
      bool use_ssl = false);
  ~LDQuery();

  /**
   * @param val if true, LSNs and timestamps will be displayed in human readable
   *            format "eXnY" or "XXXX-XX-XX XX:XX:XX.XXX" instead of raw
   *            integers.
   */
  void setPrettyOutput(bool val);
  bool getPrettyOutput() const;

 private:
  void registerTables();
  ActiveQueryMetadata& getActiveQuery() const;
  void resetActiveQuery();

  std::shared_ptr<Context> ctx_;
  std::string config_path_;
  std::chrono::milliseconds command_timeout_;
  bool use_ssl_{false};
};

}}} // namespace facebook::logdevice::ldquery
