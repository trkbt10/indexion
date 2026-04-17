#pragma once

#include <boost/asio.hpp>

#include "config.hpp"

namespace app {

class Server {
public:
    explicit Server(const Config& config);

    void run();

private:
    Config config_;
    boost::asio::io_context io_;
};

}  // namespace app
