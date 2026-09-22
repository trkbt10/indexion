<?php

namespace App\Repository;

use App\Model\User;

/**
 * How a repository orders the users it returns.
 *
 * PHP has no nested types, so an enum that belongs to one repository lives
 * beside it in the same namespace rather than inside it.
 */
enum SortOrder: string
{
    case ById = 'id';
    case ByName = 'name';

    /**
     * The property name this ordering compares on.
     *
     * Declared after the cases so the enum's scope has to survive them.
     */
    public function column(): string
    {
        return $this->value;
    }
}

/**
 * Repository for user persistence — wraps database access.
 *
 * The store is an identity map: the same ID always yields the same object,
 * so a caller can compare the users it returns by reference.
 */
class UserRepository
{
    /** @var array<int, User> */
    private array $store = [];

    /**
     * Saves a user to the store.
     */
    public function save(User $user): void
    {
        $this->store[$user->id] = $user;
    }

    /** Finds a user by ID. */
    public function findById(int $id): ?User
    {
        return $this->store[$id] ?? null;
    }

    /** Returns all stored users, in the given order. */
    public function findAll(SortOrder $order = SortOrder::ById): array
    {
        $users = array_values($this->store);
        usort($users, fn($a, $b) => $a->{$order->column()} <=> $b->{$order->column()});
        return $users;
    }
}
