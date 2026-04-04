<?php

namespace App\Services;

/**
 * Manages user operations.
 */
class UserService
{
    private string $dbHost;

    public function __construct(string $dbHost)
    {
        $this->dbHost = $dbHost;
    }

    /**
     * Find a user by ID.
     */
    public function findById(int $id): ?array
    {
        return null;
    }

    public function create(array $data): bool
    {
        return true;
    }

    private function validate(array $data): bool
    {
        return !empty($data['name']);
    }
}

/**
 * Represents a data transfer object.
 */
class UserDto
{
    public string $name;
    public int $age;
}
