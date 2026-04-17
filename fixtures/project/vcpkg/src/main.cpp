#include <fmt/core.h>
#include <spdlog/spdlog.h>

#include "config.hpp"
#include "server.hpp"

int main(int argc, char** argv) {
    auto config = app::Config::load();
    spdlog::info("Starting {} on port {}", config.name, config.port);

    app::Server server(config);
    server.run();

    return 0;
}
