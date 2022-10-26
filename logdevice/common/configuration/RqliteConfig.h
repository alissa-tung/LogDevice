/**
 * Copyright (c) 2017-present, Facebook, Inc. and its affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */
#pragma once

#include <chrono>
#include <cstddef>
#include <vector>

#include <folly/dynamic.h>

#include "logdevice/common/Sockaddr.h"

namespace facebook { namespace logdevice { namespace configuration {

class RqliteConfig {
 public:
  // maximum length of cluster name string
  constexpr static const size_t MAX_CLUSTER_NAME = 127;

  // URI scheme for ip-based quroum specifications
  constexpr static const char* URI_SCHEME_IP = "ip";

  explicit RqliteConfig() {}

  RqliteConfig(std::vector<Sockaddr> quorum)
      : quorum_(std::move(quorum)),
        uri_scheme_(URI_SCHEME_IP),
        quorum_string_(makeQuorumString(quorum_)) {}

  RqliteConfig(std::vector<Sockaddr> quorum,
               std::string uri_scheme,
               std::string quorum_string)
      : quorum_(std::move(quorum)),
        uri_scheme_(std::move(uri_scheme)),
        quorum_string_(std::move(quorum_string)) {}

  /**
   * @return A comma-separated list of ip:ports of the ZK servers
   */
  const std::string& getQuorumString() const {
    return quorum_string_;
  }

  /**
   * @return The quorum as an unsorted vector
   * DEPRECATED
   */
  const std::vector<Sockaddr>& getQuorum() const {
    return quorum_;
  }

  /**
   * @return The scheme of the URI used in the zookeeper_uri property.
   *
   * The scheme indicates the syntax of the address part of the URI. In other
   * words the sheme indicates the format of the quorum string used to
   * initialize Zookeeper clients.
   * Currently, the only supported scheme is "ip". The associated syntax of
   * a quorum is a comma-separated list of IP address and port pairs. For
   * instance, a valid URI may look like the following:
   *    "ip://1.2.3.4:2181,5.6.7.8:2181,9.10.11.12:2181"
   *
   */
  const std::string& getUriScheme() const {
    return uri_scheme_;
  }

  /**
   * @return The URI resolving to the configured zookeeper ensemble.
   */
  std::string getRqliteUri() const {
    // return uri_scheme_ + "://" + quorum_string_;
    return quorum_string_;
  }

  /**
   * @return Zookeeper config as folly dynamic suitable to be serialized as JSON
   * in the main config.
   */
  folly::dynamic toFollyDynamic() const;

  static std::unique_ptr<RqliteConfig> fromJson(const folly::dynamic& parsed);

  /**
   * Equality operator to ocmpare two Zookeeper config objects
   */
  bool operator==(const RqliteConfig& other) const;

 private:
  static std::string makeQuorumString(const std::vector<Sockaddr>& quroum);

  // Addresses of all ZK servers in the quorum we use to store and increment
  // next epoch numbers for logs
  const std::vector<Sockaddr> quorum_;

  std::string uri_scheme_;
  std::string quorum_string_;
};

}}} // namespace facebook::logdevice::configuration
