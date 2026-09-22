#pragma once

#include <string>

#include "buffer.h"

namespace app {
namespace net {

/* A tag-and-alias struct, the shape C headers use and C++ keeps. */
typedef struct SessionStats {
    unsigned long bytes_in;
    unsigned long bytes_out;
} SessionStats;

class Session {
public:
    explicit Session(std::string peer);
    ~Session();

    void write(const std::string& payload);

    SessionStats stats() const;

private:
    std::string peer_;
    AppBuffer outbound_;
    SessionStats stats_;
};

}  // namespace net
}  // namespace app
