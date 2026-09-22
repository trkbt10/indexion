using System;
using System.Collections.Generic;
using System.Linq;

namespace Example.Services;

/// <summary>
/// Manages user accounts — supports lookup and creation.
/// </summary>
public class UserService
{
    private readonly Dictionary<int, User> _store = new();

    /// <summary>
    /// The result of a lookup, carrying both the user and how it was found.
    /// Nested because it names an outcome of this service specifically and
    /// has no meaning on its own.
    /// </summary>
    public sealed class Lookup
    {
        /// <summary>The user that was found, or null.</summary>
        public User? User { get; init; }

        /// <summary>True when the lookup was served from the cache.</summary>
        public bool Cached { get; init; }

        /// <summary>Renders the outcome for a log line.</summary>
        public override string ToString() => User is null ? "miss" : $"hit:{User.Id}";
    }

    /// <summary>Adds a user to the store.</summary>
    public void Add(User user)
    {
        _store[user.Id] = user;
    }

    /// <summary>Finds a user by ID, or null if not found.</summary>
    public User? FindById(int id)
    {
        return _store.GetValueOrDefault(id);
    }

    /// <summary>Finds a user by ID and reports how it was found.</summary>
    public Lookup Find(int id)
    {
        return new Lookup { User = FindById(id), Cached = false };
    }

    /// <summary>Returns all users sorted by name.</summary>
    public IReadOnlyList<User> ListAll()
    {
        return _store.Values.OrderBy(u => u.Name).ToList();
    }

    /// <summary>Renders a one-line summary of the store.</summary>
    public string Summary()
    {
        return $"{_store.Count} user(s), newest {_store.Values.LastOrDefault()?.Name ?? "none"}";
    }
}

/// <summary>Represents a user in the system.</summary>
public record User(int Id, string Name, string Email);
