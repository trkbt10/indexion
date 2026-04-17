#include "server.hpp"

#include <spdlog/spdlog.h>

namespace app {

Server::Server(const Config& config) : config_(config) {}

void Server::run() {
    spdlog::info("Server listening on {}", config_.port);
    io_.run();
}

}  // namespace app
