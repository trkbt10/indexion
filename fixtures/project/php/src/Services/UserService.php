<?php

namespace App\Services;

use App\Dto\UserDto;
use GuzzleHttp\Client;

/**
 * Manages user operations.
 */
class UserService
{
    private string $dbHost;
    private Client $http;

    public function __construct(string $dbHost)
    {
        $this->dbHost = $dbHost;
        $this->http = new Client();
    }

    /**
     * Find a user by ID.
     */
    public function findById(int $id): ?UserDto
    {
        return null;
    }

    public function create(UserDto $dto): bool
    {
        return $this->validate($dto);
    }

    private function validate(UserDto $dto): bool
    {
        return $dto->name !== '';
    }
}
