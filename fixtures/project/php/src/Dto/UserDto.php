<?php

namespace App\Dto;

/**
 * Represents a user data transfer object passed across layers.
 */
class UserDto
{
    public function __construct(
        public readonly string $name,
        public readonly int $age,
        public readonly ?string $email = null,
    ) {
    }
}
