using Example.Models;
using Microsoft.Extensions.Logging;

namespace Example.Repositories
{
    /// <summary>
    /// Persists and retrieves User instances.
    /// </summary>
    public class UserRepository
    {
        private readonly ILogger<UserRepository> _logger;

        public UserRepository(ILogger<UserRepository> logger)
        {
            _logger = logger;
        }

        public User? FindById(int id)
        {
            _logger.LogDebug("FindById {Id}", id);
            return null;
        }

        public bool Save(User user)
        {
            _logger.LogInformation("Saving user {Name}", user.Name);
            return true;
        }
    }
}
