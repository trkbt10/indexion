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
    }
}
