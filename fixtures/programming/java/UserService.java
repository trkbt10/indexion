package com.example.service;

import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.Optional;

/**
 * Service for managing users — supports CRUD operations.
 */
public class UserService {
    private final Map<Long, User> store = new HashMap<>();

    /**
     * The outcome of a lookup that may have been served from a cache.
     *
     * Nested because it is meaningless outside this service: it names a
     * user together with where that user came from.
     */
    public static final class Lookup {
        private final User user;
        private final boolean cached;

        /** Wraps a user together with its provenance. */
        public Lookup(User user, boolean cached) {
            this.user = user;
            this.cached = cached;
        }

        /** The user that was found. */
        public User user() {
            return user;
        }

        /** Whether the user came from the cache rather than the store. */
        public boolean cached() {
            return cached;
        }
    }

    /**
     * Adds a user to the store.
     * @param user the user to add
     */
    public void addUser(User user) {
        store.put(user.id(), user);
    }

    /** Retrieves a user by ID. */
    public Optional<User> getUser(long id) {
        return Optional.ofNullable(store.get(id));
    }

    /** Retrieves a user by ID, reporting where it came from. */
    public Optional<Lookup> lookup(long id) {
        return getUser(id).map(u -> new Lookup(u, false));
    }

    /** Lists all users. */
    public List<User> listUsers() {
        return List.copyOf(store.values());
    }
}
