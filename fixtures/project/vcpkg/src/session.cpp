#include "session.hpp"

#include <spdlog/spdlog.h>

namespace app {
namespace net {

Session::Session(std::string peer) : peer_(std::move(peer)) {
    outbound_ = app_buffer_create(4096);
    stats_.bytes_in = 0;
    stats_.bytes_out = 0;
}

Session::~Session() {
    app_buffer_destroy(&outbound_);
}

void Session::write(const std::string& payload) {
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(payload.data());
    if (app_buffer_append(&outbound_, bytes, payload.size())) {
        stats_.bytes_out += payload.size();
    } else {
        spdlog::warn("session buffer full for {}", peer_);
    }
}

SessionStats Session::stats() const {
    return stats_;
}

}  // namespace net
}  // namespace app
