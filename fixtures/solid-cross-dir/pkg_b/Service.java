public class AuthService {
    public boolean validateEmail(String email) {
        String regex = "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$";
        return email.matches(regex);
    }

    public String hashPassword(String password) {
        int hash = 0;
        for (int i = 0; i < password.length(); i++) {
            char c = password.charAt(i);
            hash = ((hash << 5) - hash) + c;
            hash |= 0;
        }
        return Integer.toHexString(hash);
    }

    public Map<String, Object> createSession(String userId) {
        Map<String, Object> session = new HashMap<>();
        session.put("userId", userId);
        session.put("createdAt", System.currentTimeMillis());
        session.put("expiresAt", System.currentTimeMillis() + 7200000);
        return session;
    }
}
