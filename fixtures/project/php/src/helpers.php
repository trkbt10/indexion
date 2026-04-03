<?php

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
