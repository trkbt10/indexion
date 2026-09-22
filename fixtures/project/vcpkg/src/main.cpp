#include <fmt/core.h>
#include <spdlog/spdlog.h>

#include "buffer.h"
#include "config.hpp"
#include "server.hpp"
#include "session.hpp"

int main(int argc, char** argv) {
    auto config = app::Config::load();
    spdlog::info("Starting {} on port {}", config.name, config.port);

    AppBuffer scratch = app_buffer_create(1024);

    app::net::Session session("127.0.0.1");
    session.write("ping");

    app::Server server(config);
    server.run();

    app_buffer_destroy(&scratch);

    return 0;
}
