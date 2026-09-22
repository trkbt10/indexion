using Example.Models;
using Example.Repositories;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace Example.Services
{
    /// <summary>
    /// High-level user operations that compose repository access with validation.
    /// </summary>
    public class UserService
    {
        private readonly UserRepository _repo;
        private readonly ILogger<UserService> _logger;

        public UserService(UserRepository repo, ILogger<UserService> logger)
        {
            _repo = repo;
            _logger = logger;
        }

        public User? Get(int id) => _repo.FindById(id);

        public string Serialize(User user)
        {
            return JsonConvert.SerializeObject(user);
        }

        /// <summary>Renders a user for a log line.</summary>
        public string Describe(User user)
        {
            return $"user {user.Id} <{user.Email}>";
        }

        /// <summary>The on-disk cache path for a user, as a verbatim string.</summary>
        public string CachePath(int id)
        {
            return $@"cache\users\{id}.json";
        }

        /// <summary>A canned JSON payload, as a raw string literal.</summary>
        public string EmptyPayload()
        {
            return """{"users": []}""";
        }
    }
}
