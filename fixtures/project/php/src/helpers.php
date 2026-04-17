<?php

namespace App;

use App\Dto\UserDto;
use App\Services\UserService;

/**
 * Create a new user service instance.
 */
function createUserService(string $dbHost): UserService
{
    return new UserService($dbHost);
}

/**
 * Validate an email address.
 */
function isValidEmail(string $email): bool
{
    return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
}

/**
 * Build a DTO from raw input.
 */
function makeUserDto(array $data): UserDto
{
    return new UserDto(
        name: $data['name'] ?? '',
        age: (int)($data['age'] ?? 0),
        email: $data['email'] ?? null,
    );
}
