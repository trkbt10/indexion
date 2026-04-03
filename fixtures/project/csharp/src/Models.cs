namespace Example.Models
{
    /// <summary>
    /// Represents a user in the system.
    /// </summary>
    public class User
    {
        public string Name { get; set; }
        public int Age { get; set; }
    }

    /// <summary>
    /// Validates user data.
    /// </summary>
    public interface IValidator { }

    internal class InternalHelper { }
}
