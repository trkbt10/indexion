#include "config.hpp"

#include <nlohmann/json.hpp>

namespace app {

Config Config::load() {
    return Config{"my-cpp-app", 8080, false};
}

nlohmann::json Config::to_json() const {
    return nlohmann::json{
        {"name", name},
        {"port", port},
        {"debug", debug},
    };
}

}  // namespace app
