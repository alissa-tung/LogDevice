/**
 * Copyright (c) 2017-present, Facebook, Inc. and its affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */
#include "logdevice/common/configuration/RqliteConfig.h"

#include "logdevice/common/commandline_util_chrono.h"
#include "logdevice/common/configuration/ParsingHelpers.h"

namespace facebook { namespace logdevice { namespace configuration {

/* static */ constexpr const size_t RqliteConfig::MAX_CLUSTER_NAME;
/* static */ constexpr const char* RqliteConfig::URI_SCHEME_IP;

std::string
RqliteConfig::makeQuorumString(const std::vector<Sockaddr>& quorum) {
  std::string result;
  for (const Sockaddr& addr : quorum) {
    if (!result.empty()) {
      result += ',';
    }
    // Do not include brackets "[a:b:c..]" around IPv6 addresses in Zookeeper
    // quorum string. Zookeeper C client currently only supports
    // a:b:c:..:z:port format of IPv6+port specifiers
    result += addr.toStringNoBrackets();
  }
  return result;
}

std::unique_ptr<RqliteConfig>
RqliteConfig::fromJson(const folly::dynamic& parsed) {
  std::vector<Sockaddr> quorum;
  std::string uri_scheme, quorum_string;

  if (!parsed.isObject()) {
    ld_error("\"rqlite\" cluster is not a JSON object");
    err = E::INVALID_CONFIG;
    return nullptr;
  }

  auto iter = parsed.find("rqlite_uri");
  if (iter != parsed.items().end()) {
    if (!iter->second.isString()) {
      ld_error("rqlite_uri property in the rqlite section "
               "is not a string");
      err = E::INVALID_CONFIG;
      return nullptr;
    }
    std::string uri = iter->second.asString();

    auto delim = uri.find("://");
    if (delim == std::string::npos) {
      ld_error("Invalid rqlite_uri property. The format must be "
               "<scheme>://<value>");
      err = E::INVALID_CONFIG;
      return nullptr;
    }

    uri_scheme = std::string(uri, 0, delim);
    quorum_string = std::string(uri, delim + 3);
  }

  if (quorum_string.empty() || uri_scheme.empty()) {
    ld_error("Missing or invalid rqlite_uri property in rqlite section.");
    err = E::INVALID_CONFIG;
    return nullptr;
  }

  return std::make_unique<RqliteConfig>(
      std::move(quorum), std::move(uri_scheme), std::move(quorum_string));
}

folly::dynamic RqliteConfig::toFollyDynamic() const {
  folly::dynamic rqlite = folly::dynamic::object;
  rqlite["rqlite_uri"] = getRqliteUri();
  return rqlite;
}

bool RqliteConfig::operator==(const RqliteConfig& other) const {
  return getQuorum() == other.getQuorum() &&
      getQuorumString() == other.getQuorumString() &&
      getUriScheme() == other.getUriScheme();
}

}}} // namespace facebook::logdevice::configuration
