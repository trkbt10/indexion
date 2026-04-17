#pragma once

#include <string>
#include <nlohmann/json.hpp>

namespace app {

struct Config {
    std::string name;
    unsigned short port;
    bool debug;

    static Config load();

    nlohmann::json to_json() const;
};

}  // namespace app
