function validateEmail(email: string): boolean {
  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return re.test(email);
}

function hashPassword(password: string): string {
  let hash = 0;
  for (let i = 0; i < password.length; i++) {
    const char = password.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash |= 0;
  }
  return hash.toString(16);
}

function createSession(userId: string): object {
  return {
    id: Math.random().toString(36),
    userId: userId,
    createdAt: Date.now(),
    expiresAt: Date.now() + 7200000,
  };
}
