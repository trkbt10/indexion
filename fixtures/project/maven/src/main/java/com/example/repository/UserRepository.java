package com.example.repository;

import java.util.Optional;

import com.example.model.User;

public class UserRepository {
    public Optional<User> findById(long id) {
        return Optional.empty();
    }

    public void save(User user) {
        // no-op
    }
}
